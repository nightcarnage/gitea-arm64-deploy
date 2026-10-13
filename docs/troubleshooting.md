# Troubleshooting

Every entry here is a failure that actually happened while building this, with the
real cause — not a guess. Most of them look like something else, which is why they
cost time.

---

## Docker Desktop will not finish starting

### "WSL update required"

Docker Desktop's engine reports:

```
engine linux/wsl failed to start: checking preconditions: WSL update required
```

The precondition test runs `wsl.exe --version`. If that binary is the old inbox stub,
it prints usage text instead of a version, and Docker concludes WSL is out of date and
refuses to start the engine — even though `wsl`, `bash` and your distributions all work
perfectly.

Diagnose:

```powershell
wsl --version          # a version, or "Invalid command line option"?
```

Fix:

```powershell
wsl --update
```

Then **fully restart Docker Desktop**. Updating WSL is not enough on its own — the
running Docker Desktop process has already latched onto the old state. Quit it from the
tray (not just closing the window) and start it again.

### "Virtual Machine Platform not enabled"

```
checking preconditions: Virtual Machine Platform not enabled
```

```powershell
Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform |
  Select-Object FeatureName, State

Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All
```

Needs administrator rights and a **reboot**. There is no way to do this from a normal
user session.

---

## A port will not bind: "access permissions"

```
Error response from daemon: ports are not available: exposing port TCP 0.0.0.0:2222 ->
  ... bind: An attempt was made to access a socket in a way forbidden by its access permissions.
```

Nothing is listening on that port, yet Windows refuses to let anything bind it. Windows
reserves blocks of TCP ports for Hyper-V and WSL, and the kernel blocks bindings inside
those blocks.

Check:

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

Typical output on a machine with WSL and Docker:

```
Start Port    End Port
      2007        2106
      2107        2206
      2207        2306      <- 2222 falls in here
      2869        2869
      5357        5357
     10243       10243
     50000       50059   *
```

**Port 2222 — the conventional Gitea SSH port — commonly lands inside a reserved block.**
That is why this project publishes SSH on **3022** by default.

Fix: pick a port outside every reserved range. `scripts\Inspect-Environment.ps1` reports
this for you and names the range that is in the way.

Moving the reserved ranges themselves requires changing the dynamic port range and
rebooting, which has a good chance of landing the reservation somewhere else. Choosing a
different port is simpler and sticks.

---

## Git

### The repository is empty / a folder is missing

```
warning: You appear to have cloned an empty repository.
```

or a folder present locally that simply does not exist on the server.

**Git cannot track an empty folder.** An empty directory is not an object in Git, so it
never appears on the remote and is never created by a clone.

Fix: put a file in it.

```powershell
New-Item -ItemType File -Path myfolder\.gitkeep -Force
```

A `README.md` explaining the folder's purpose is more useful than `.gitkeep`.

### A stray file appeared in a commit

Windows Explorer can leave a 0-byte `New Text Document.txt` behind. `git add -A` sweeps
it into the commit. Check `git status` before committing, and delete it:

```powershell
git rm --cached "New Text Document.txt"
```

### "shallow update not allowed"

```
! [remote rejected] main -> main (shallow update not allowed)
```

You cloned with `--depth 1` and are now pushing that shallow history. Gitea refuses.

If you are deliberately importing a snapshot, start clean instead of pushing the shallow
clone — note this **re-commits** the files, so the provenance differs from a true mirror:

```powershell
Remove-Item .git -Recurse -Force
git init -b main
git add -A
git commit -m "Import snapshot"
git remote add origin <url>
git push -u origin main
```

If you want real upstream history, re-clone without `--depth`.

---

## Git LFS

### Every LFS push 404s

```
Uploading LFS objects:   0% (0/1), 0 B | 0 B/s, done.
batch response: Repository or object not found: .../info/lfs/objects/batch
```

**Gitea ships `LFS_START_SERVER = false` in its default `app.ini`.** With that default the
LFS endpoint does not exist at all and no binary can be uploaded.

Confirm inside the container:

```powershell
docker compose exec gitea grep -i lfs /data/gitea/conf/app.ini
```

Fix in `compose.yaml`:

```yaml
environment:
  GITEA__server__LFS_START_SERVER: "true"
```

Then `docker compose up -d`. The `compose.yaml` here already sets it.

### A committed asset is a small text file, not the real binary

It is an LFS pointer, and the object was never uploaded. Check:

```powershell
git lfs ls-files          # what LFS thinks it is tracking
git lfs env               # endpoint and configuration
```

The usual cause is that `git lfs install` was never run on that machine.

### Cloning gives pointers instead of files

```powershell
git lfs install
git lfs pull
```

---

## Gitea

### The install wizard appears on every start, and the API is unusable

Gitea serves an installation page until an admin exists. Unattended deployment cannot
click through it.

Fix in `compose.yaml`:

```yaml
environment:
  GITEA__security__INSTALL_LOCK: "true"
```

The deployment script also creates the admin user through `gitea admin user create`, so
no browser step is ever required.

### "password is too short"

Gitea's default minimum is **8 characters**, and it enforces that on user creation. A
7-character password is rejected.

```yaml
environment:
  GITEA__security__MIN_PASSWORD_LENGTH: "6"
```

The real fix for anything reachable from another machine is a longer password.

### Cannot reach the server after a reboot

Gitea does not start by itself unless Docker Desktop does. Check Docker Desktop's own
setting ("Start Docker Desktop when you sign in"), and note that the container has
`restart: unless-stopped`, so it comes back as soon as the engine does.

### The container name is already in use

Two checkouts of this project both declaring `container_name: gitea` collide. This
project deliberately declares **no** `container_name`, so Compose derives the name from
the folder and multiple copies can coexist.

---

## Codex

### The agent ignores the project rules

Codex picks up `AGENTS.md`. Common causes:

1. The file is in the wrong place. A **global** one lives at
   `%USERPROFILE%\.codex\AGENTS.md`; a per-project one lives in the project root.
2. The file is **empty**. An empty `AGENTS.md` teaches nothing — this is easy to miss
   because the file existing *looks* like it is configured.
3. `config.toml` has been overwritten and lost the `mcp_servers` section.

`scripts\Inspect-Environment.ps1` reports whether the global `AGENTS.md` exists and how
many bytes it holds.

---

## Scripts

### "Cannot find an overload for new and the argument count: 1"

A PowerShell/.NET constructor mistake — `[System.Text.ASCIIEncoding]::new($false)` takes
no arguments (it is `UTF8Encoding` that takes `encoderShouldEmitUTF8Identifier`). Write
`[System.Text.ASCIIEncoding]::new()`.

### A script aborts on a native command's output

With `$ErrorActionPreference = 'Stop'`, redirecting a native command's stderr (`2>&1`)
turns ordinary progress output into a **terminating error**:

```
docker.exe :  Image gitea/gitea:1 Pulling
    + CategoryInfo : NotSpecified: ( Image gitea/gitea:1 Pulling :String) [], RemoteException
```

`docker compose pull` and `git` both write normal progress and warnings to stderr.

Fix: use `$ErrorActionPreference = 'Continue'` and check `$LASTEXITCODE` explicitly, or
suppress with `2>$null` instead of `2>&1`. Every script here follows that pattern.

### Re-running a script creates an empty commit each time

`Set-Content` appends a trailing newline on every call, so a file it rewrites grows by a
blank line per run — and each run then looks like a real change.

Fix: write with `[System.IO.File]::WriteAllText()`, which writes exactly the bytes given,
and skip the write entirely when there is nothing to change.

### `wsl -l` output looks like `L e g a c y`

`wsl.exe` writes UTF-16LE. Read as text, the NUL bytes interleave and break both pattern
matching and display.

Fix:

```powershell
$text = ((& wsl.exe -l -q 2>&1 | Out-String) -replace "`0", '')
```
