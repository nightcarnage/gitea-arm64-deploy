# Self-hosted Gitea for Windows (including Windows on Arm) — set up for AI agents

A small, complete kit for putting a workstation's projects under version control on a
**local** Gitea server running in Docker Desktop, configured so that an AI agent
(**OpenAI Codex on Windows**) knows the rules without being told each time.

No cloud account. No subscription. Nothing leaves the machine.

---

## What you get

| | |
|---|---|
| A private Git server | <http://localhost:3000>, in Docker Desktop |
| One-command deploy | `scripts\Deploy-Gitea.ps1` — start, wait for health, create the admin, issue an API token |
| One-command project setup | `scripts\New-Project.ps1` — put a folder under version control, wired up and pushed |
| A preflight check | `scripts\Inspect-Environment.ps1` — read-only; says exactly what is missing |
| An agent contract | `templates\AGENTS.md` — the rules the agent follows, installed into each project |
| Large-file support | Git LFS, enabled and **verified end-to-end** |
| One-button revisions | `Save-Revision.bat` — commit, tag `r<N>`, push |

---

## The idea

People who do not program do not want to learn Git. They want **revisions**: named points
they can return to, without a desktop littered with `project-2`, `project-final` and
`project-final-FINAL`.

So the flow is deliberately two commands:

```powershell
.\scripts\Save-Revision.bat          # a button, for the person
.\scripts\Save-Revision.ps1 "text"   # the same thing, described, for the agent
```

Both commit, tag the next revision number, and push. `r1`, `r2`, `r3`, … forever.

The other half is `AGENTS.md`. An AI agent will happily invent its own workflow — making
copies, force-pushing, committing a build cache — unless it is told otherwise. A short
`AGENTS.md` in the project root is how the rules travel with the project.

---

## Start here: profile before you deploy

These scripts encode **our** assumptions. On a pilot, some of them will be wrong, and
finding out afterwards is expensive.

```powershell
# 1. machine facts - never ask a person what a command can answer
.\scripts\Get-MachineProfile.ps1 -ScanProjects -OutFile .\profiles\<client>-machine.md

# 2. read docs/interview.md, then talk to the person in batches of 5-7 questions

# 3. record it
Copy-Item .\templates\PROFILE.md .\profiles\<client>.md

# 4. only now deploy, adjusted to the answers
```

The split matters: **detect machine facts, ask about intent.** `Get-MachineProfile` covers
OS, architecture, CPU/RAM/disk, WSL, Docker, git, LFS, Codex state, installed creative
tools, cloud-sync status, reserved ports, and existing repos. None of that should ever be a
question to a non-programmer.

The interview covers what a command cannot know — where the files really live, who else
needs access, how they recover a broken version today, and what would make this worth it.
It ends with a **change list**: every answer that altered a setting. An interview that
changes nothing was either unnecessary or badly asked.

Notably, it asks **where the project files live**, because a git repository inside a
cloud-synced folder (OneDrive, Dropbox) is a known way to corrupt both — and that is not
something a client will volunteer.

---

## Requirements

Windows 11 (or 10), plus:

| Requirement | Why | Check |
|---|---|---|
| Docker Desktop | runs the server | `docker version` |
| WSL2 | Docker Desktop's engine backend | `wsl --version` |
| Virtual Machine Platform | required by WSL2 | `Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform` |
| Git + Git LFS | version control and large files | `git lfs version` |
| Codex (optional) | the agent this is set up for | `%USERPROFILE%\.codex\` |

Run this first. It changes nothing and tells you precisely what is missing:

```powershell
.\scripts\Inspect-Environment.ps1
```

It checks architecture, WSL, virtualisation, Docker, git, LFS, Codex, whether your chosen
ports are usable, and free disk — and it names the **reserved port range** when Windows
would refuse to bind a port.

---

## Quick start

```powershell
# 1. Put the server up
.\scripts\Deploy-Gitea.ps1

# 2. Put a project under version control
.\scripts\New-Project.ps1 -Name MyProject

# 3. From then on, save revisions
cd ~\source\repos\MyProject
.\scripts\Save-Revision.bat
```

`Deploy-Gitea.ps1` is **idempotent** — run it as often as you like. It will not duplicate
the admin user or destroy data. It finishes by printing the URLs and credentials, and it
saves an API token to `.gitea-token` (gitignored).

To move a NON-default port, copy `.env.example` to `.env` and edit it. Compose reads it
automatically:

```powershell
Copy-Item .env.example .env
```

---

## Daily use

```powershell
# what changed?
git log --oneline --decorate
git show                       # exactly what the last revision changed

# go back and look, without losing anything
git switch --detach r3
git switch main                # return

# the server
docker compose up -d           # start
docker compose ps              # status
docker compose logs -f         # live logs
docker compose down            # stop  (DATA IS KEPT)
docker compose down -v         # stop  (DELETES EVERY REPOSITORY)
```

---

## Backing up

```powershell
.\scripts\Backup-Gitea.ps1
```

Writes one archive into a OneDrive folder by default, containing **the database, every
repository with full history, every Git LFS object, and the configuration**. Verifies the
archive really contains your code before keeping it, and prunes old copies.

Runs in about **0.4 seconds** on the reference instance. The round trip was tested: the
dump was **restored into a scratch instance** and the revision tags `r1`, `r2`, `r3` came
back with matching commit SHAs.

**Read [docs/backup-and-restore.md](docs/backup-and-restore.md) before relying on this.**
Two things there are easy to get wrong:

- Do **not** try to keep the live database in OneDrive. It lives inside a Docker volume,
  inside a multi-GB virtual disk, and syncing a live SQLite file risks corruption — and a
  database contains no code anyway.
- On this machine OneDrive was **installed but not running**, and **Known Folder Move is
  off** — so Desktop and Documents are *not* being backed up. That matters if projects
  live on the Desktop.

---

## Windows on Arm

`gitea/gitea:1` is a multi-arch image. Verified with:

```powershell
docker manifest inspect gitea/gitea:1
```

which publishes `linux/amd64`, **`linux/arm64`** and `linux/riscv64`. On Windows on Arm
this therefore runs as a **native Arm64 container — no x64 emulation**, no translation
penalty. See [docs/arm64-notes.md](docs/arm64-notes.md).

---

## How the agent knows the rules

Two files, both named `AGENTS.md`:

| Location | Scope |
|---|---|
| `%USERPROFILE%\.codex\AGENTS.md` | Every session on the machine — the index. Projects, server, credentials, pitfalls. |
| `<project>\AGENTS.md` | That project only — how to work on it, how to verify it. |

An **empty** `AGENTS.md` is the commonest mistake: the file exists, so it looks
configured, and it teaches nothing. `Inspect-Environment.ps1` reports the byte count.

See [docs/codex-integration.md](docs/codex-integration.md).

---

## Troubleshooting

[docs/troubleshooting.md](docs/troubleshooting.md) — written from failures that actually
happened, each with its real cause. The ones worth knowing about up front:

- **"WSL update required"** — Docker's precondition test reads `wsl.exe --version`; an old
  binary makes it refuse to start its engine even though WSL works. `wsl --update`, then
  **fully restart Docker Desktop**.
- **A port that will not bind, with an "access permissions" error** — it is inside a range
  Windows reserved for Hyper-V/WSL. `netsh interface ipv4 show excludedportrange protocol=tcp`.
  Port 2222 is the usual victim, which is why SSH is on **3022** here.
- **Every Git LFS push returns 404** — Gitea ships `LFS_START_SERVER = false`.
- **A folder is missing from the repository** — Git cannot track an empty folder.
- **A script dies on Docker's output** — `$ErrorActionPreference = 'Stop'` plus `2>&1`
  turns ordinary stderr progress into a terminating error.

---

## Layout

```
compose.yaml          the server. Every setting has its reason in a comment
.env.example          ports, timezone, admin credentials -> copy to .env
scripts/
  Inspect-Environment.ps1   read-only preflight; exits 1 if anything is actually broken
  Get-MachineProfile.ps1    read-only report of everything the scripts assume about this PC
  Deploy-Gitea.ps1          start the server, create the admin, issue a token
  New-Project.ps1           put a folder under version control, initialised and pushed
  Backup-Gitea.ps1          verify-and-prune backup, into OneDrive by default
templates/
  AGENTS.md                 the agent contract, installed into new projects
  Save-Revision.ps1 / .bat  the revision button
  gitignore.default         sane defaults, including secrets and build caches
  gitattributes.default     Git LFS rules and line-ending policy
  PROFILE.md                the filled-in record of an interview
docs/
  interview.md              how to find out what this person actually needs
  troubleshooting.md        real failures, real causes
  backup-and-restore.md     where the data lives, and a tested restore procedure
  arm64-notes.md            Windows on Arm specifics
  codex-integration.md      how Codex discovers the rules
profiles/                   one filled-in profile per client
```

---

## Verified

Everything in `scripts/` was executed, not just written:

- `Deploy-Gitea.ps1` — deployed to isolated ports (3300/3222), API answered, admin created,
  **token authenticated against the API as an admin**, then torn down. Re-run confirmed
  idempotent: one user, no duplicates.
- `New-Project.ps1` — created a real repository on the server and pushed `r1`. Run **three
  times** against the same folder: still exactly **one commit**, clean tree, one tag.
- `Inspect-Environment.ps1` — reports 0 warnings on a healthy machine, correctly **fails**
  on a port inside a reserved range, and correctly parses `wsl.exe`'s UTF-16 output.
- `Backup-Gitea.ps1` — dump, archive verification, pruning (3 stale backups correctly
  removed at `-Keep 2`) and the OneDrive upload check. Then the **restore was performed and
  verified**: dump → mirror of `/data` → `docker compose create` → `docker cp` →
  `up -d`, on ports 3400/3422. A credential from the restored database authenticated, all
  4 repositories were listed, and `git ls-remote` returned `refs/tags/r1`, `r2`, `r3` with
  SHAs matching the live instance. Torn down afterwards.

**Caveat, stated plainly:** the deployment was validated on **x64** Windows 10 with Docker
Desktop 29.8.2. The arm64 support claim rests on the published multi-arch image manifest
and on Docker Desktop's documented Arm64 build, **not** on a run on Arm hardware. The
scripts are architecture-agnostic — `Inspect-Environment.ps1` will tell you which
architecture your engine is really running.
