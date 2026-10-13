# Backup and restore

## The short version

```powershell
.\scripts\Backup-Gitea.ps1
```

That writes a single archive into a OneDrive folder by default, and it is a **complete**
backup: database, every git repository with full history, every Git LFS object, and the
server configuration.

It has been **restored and verified**, not just written — see "Proof it works" at the end.

---

## Where the database actually is

Three layers, and each one matters when deciding how to back it up:

| Layer | Location |
|---|---|
| Inside the container | `/data/gitea/gitea.db` — SQLite, per `app.ini` (`DB_TYPE = sqlite3`, `PATH = /data/gitea/gitea.db`) |
| The Docker volume | `gitea_gitea-data` → `/var/lib/docker/volumes/gitea_gitea-data/_data` **inside the Docker VM** |
| On Windows | `%LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx` — a multi-GB virtual disk holding **all** of Docker's data, not just Gitea |

The volume is **not a folder you can browse on Windows.** There is no
`C:\...\gitea\data` directory to copy. `docker volume inspect` reports a path that only
exists inside the VM that Docker runs.

Alongside the database, `/data` also holds:

```
/data/git/repositories/   every project's git history   <- the actual code
/data/gitea/              gitea.db, attachments, avatars, indexers, jwt, conf
/data/lfs/                Git LFS objects
```

---

## Can the database live in a OneDrive folder?

**Not the live one — and you should not try.** Three separate reasons:

**1. OneDrive syncing a live SQLite database risks corruption.** SQLite depends on file
locking and careful write ordering. A sync client that copies or locks the file mid-
transaction can produce a database that will not open. Agit commit is not atomic with
respect to an external file copier.

**2. You cannot put the file there directly.** It is inside a Docker volume, inside a
virtual disk. To relocate it you would have to either change Docker Desktop's disk image
location (which moves *everything* Docker stores, a multi-GB file that would then be
re-uploaded constantly) or switch the compose volume to a Windows bind mount
(`./data:/data`). Bind mounts into WSL2 also bring slow I/O and uid/gid mapping problems,
which Gitea hits as permission errors.

**3. A database is not a backup.** It contains no code. The repositories do. Backing up
`gitea.db` alone gives you a list of projects whose contents no longer exist.

**What to do instead:** leave the live data where it is, and write **backups** into
OneDrive. That is what `Backup-Gitea.ps1` does.

---

## OneDrive caveats on this machine

Two things were true when this was written, and both matter:

### OneDrive is installed and signed in, but was not running

```powershell
Get-Process OneDrive
```

returned **nothing**. Files written into `%USERPROFILE%\OneDrive` do not upload until
OneDrive is running. The account is configured (`UserFolder = C:\Users\<you>\OneDrive`,
signed in as `your-account@example.com`), so starting OneDrive from the Start menu is all
that is needed.

`Backup-Gitea.ps1` checks for this and warns rather than letting you believe a
non-functioning backup exists.

### Known Folder Move is NOT enabled

```
HKCU\Software\Microsoft\OneDrive\Accounts\Personal
  KfmFoldersConfiguredValues = (empty)
```

and the shell folders still point at the local disk:

| Folder | Actual path |
|---|---|
| Desktop | `C:\Users\<you>\Desktop` — **not** in OneDrive |
| Documents | `C:\Users\<you>\Documents` — **not** in OneDrive |
| Pictures | `C:\Users\<you>\OneDrive\Pictures` — synced |
| Downloads | `C:\Users\<you>\Downloads` — **not** in OneDrive |

**Desktop and Documents are not being backed up.** That matters more than it sounds,
because the working assumption on this machine is that projects live on the Desktop.

Note that `C:\Users\<you>\OneDrive\Desktop` exists, but it is a **link pointing out** to
the real Desktop. A link into a sync folder does not cause the target to upload. It looks
like a backup and provides none.

To actually enable it, use OneDrive's own UI: **Settings → Sync and backup → Manage
backup**, and turn on Desktop/Documents. That moves the real folders (the link situation
is worth checking afterwards) and is a deliberate, visible change — do not do it as a
side effect of something else.

---

## Running a backup

```powershell
# default: %USERPROFILE%\OneDrive\GiteaBackups, keep the newest 14
.\scripts\Backup-Gitea.ps1

# somewhere else
.\scripts\Backup-Gitea.ps1 -Destination 'D:\Backups\Gitea'

# a different compose project
.\scripts\Backup-Gitea.ps1 -ProjectDir 'C:\path\to\gitea' -Service gitea
```

It does this:

1. resolves the destination (OneDrive if present, else `<project>\backups`);
2. warns if OneDrive is not running;
3. confirms the container is actually up;
4. runs `gitea dump` inside the container;
5. copies the archive out and **deletes the in-container copy**;
6. **verifies the archive** contains the database *and* at least one repository — an
   incomplete archive is deleted rather than kept, because a backup that silently holds
   no code is worse than no backup;
7. prunes old backups, keeping the newest `-Keep`.

Runtime on the reference instance: **about 0.4 seconds, 35 MB** for 5 repositories.

### What the archive contains

```
app.ini                 configuration, including secrets
gitea-db.sql            plain SQL dump
data/gitea.db           the SQLite database
data/lfs/               Git LFS objects
data/conf/app.ini       the authoritative config
data/{avatars,indexers,jwt,queues,...}
repos/<owner>/<repo>.git/   every repository, bare, full history
```

Note the repositories live under **`repos/`**, not `repositories/`. When writing a check
for "is my code in here", look for `repos/`.

### Scheduling it

Run once, as the user who owns the Docker Desktop session:

```powershell
$a = New-ScheduledTaskAction -Execute 'powershell.exe' `
       -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\<you>\Desktop\doom\gitea-arm64-deploy\scripts\Backup-Gitea.ps1"'
Register-ScheduledTask -TaskName 'Gitea backup' -Action $a `
       -Trigger (New-ScheduledTaskTrigger -Daily -At 18:00)
```

**Do not run this task as SYSTEM or as a different user.** Docker Desktop is a per-user
application; a task running as another account will not see the Docker engine and the
backup will fail.

---

## Restoring

The procedure below is the one that was actually performed and verified.

### 1. Stop the running instance

```powershell
cd C:\Users\<you>\Desktop\docker\gitea
docker compose down
```

### 2. Extract the archive

```powershell
$work = "$env:TEMP\gitea-restore"
Expand-Archive -Path "$env:OneDrive\GiteaBackups\gitea-backup-<stamp>.zip" -DestinationPath $work -Force
```

The archive contains `repos/`, `data/`, `app.ini` and `gitea-db.sql`. You need to
reassemble `/data` from two of them:

| From the archive | Goes to inside the container |
|---|---|
| `repos/<owner>/` | `/data/git/repositories/<owner>/` |
| `data/*` | `/data/gitea/*` |

Build that layout on disk first:

```powershell
$mirror = "$env:TEMP\gitea-mirror"
New-Item -ItemType Directory -Path "$mirror\git","$mirror\gitea" -Force | Out-Null
robocopy "$work\repos" "$mirror\git\repositories" /E
robocopy "$work\data"  "$mirror\gitea"             /E
```

> Use `robocopy` (or `Copy-Item -Recurse` on the *folders*, not with a `\*` wildcard).
> Copying `repos\*` with a wildcard can flatten the `<owner>/` level, and Gitea will then
> find no repositories at all. The owner folder is part of the path.

### 3. Create the container without starting it

```powershell
docker compose create
$cid = docker compose ps -a -q gitea
```

`docker cp` works on a container that exists but has not started, which is what makes this
clean — the data is in place before Gitea ever opens the database.

### 4. Copy the data into the volume

```powershell
Push-Location $mirror
docker cp . "${cid}:/data/"
Pop-Location
```

### 5. Start it

```powershell
docker compose up -d
docker compose logs -f
```

Gitea runs any needed database migrations on startup. Restoring into a **different Gitea
version** is where migrations matter — restore into the same image tag to avoid surprises.

### 6. Check it

```powershell
# does a credential from the restored database still work?
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('doom:<password>'))
Invoke-RestMethod -Uri 'http://localhost:3000/api/v1/user' -Headers @{ Authorization = "Basic $b64" }

# is the history there, including revision tags?
git ls-remote http://doom:<password>@localhost:3000/doom/doom-work.git
```

### 7. If you restored to a different port

`app.ini` records the original `ROOT_URL`. Environment variables in `compose.yaml`
override it, so set `HTTP_PORT` in `.env` and the clone URLs follow. Otherwise Gitea hands
out clone URLs pointing at the old port.

---

## Proof it works

A backup that has never been restored is not a backup. This one was.

A dump was restored into a throwaway instance on ports 3400/3422 and checked:

| Check | Result |
|---|---|
| Server came up | Gitea 1.27.3 |
| Credential from the restored database | authenticated as `doom`, admin |
| Repositories in restored metadata | all 4, sizes matching the original |
| Git history | `refs/tags/r1`, `r2`, `r3` present, SHAs matching the live instance |
| `main` | `f149eea`, matching the live instance |

The scratch instance was then torn down with `docker compose down -v`.

---

## Related

- [troubleshooting.md](troubleshooting.md) — the LFS and port pitfalls that also apply here
- `scripts/Backup-Gitea.ps1` — the script, with the reasoning in its comments
