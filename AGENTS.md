# AGENTS.md — gitea-arm64-deploy

Instructions for an agent working **on this kit**. Read the machine-wide
`~/.codex/AGENTS.md` too; it has the server details and the pitfalls that this kit exists
to solve.

---

## What this repository is

A deployment kit: a `compose.yaml` for a single-user self-hosted Gitea, three PowerShell
scripts, project templates, and documentation. It is a **deliverable** — someone else will
run it on a machine you cannot see, likely Windows on Arm.

That framing decides most of the rules below. Convenience for the author is worth less
than reliability for the person running it unattended.

---

## The rules that matter here

### Test every script you touch

This is a deployment kit. A script that "looks right" is worthless; the README makes
specific promises (idempotent, read-only, exits non-zero on failure) and they must be
true.

Non-negotiable before claiming a change works:

- **Idempotency must be demonstrated.** Run it 2-3 times and show the result is unchanged
  — same user count, same commit count, same file contents.
- **Read-only scripts must change nothing.** Verify, do not assume.
- **Failure paths must actually fail.** Confirm a check that should exit 1 does exit 1.
- **Never claim success from a clean exit code alone.** `exit 0` from a script that did
  nothing is still `exit 0`.

When testing `Deploy-Gitea.ps1`, use **different ports and a throwaway directory** so a
running instance is not disturbed, then tear it down with `docker compose down -v` and
delete any test repository you created.

### Keep the documentation true

The README and `docs/` make checkable claims ("idempotent", "verified end-to-end",
"exits 1 if anything FAILs"). If a change invalidates one, correct the document in the
same change. Stale confidence is worse than no documentation.

If something was not verified, say so where the claim is made — the README has a
"Verified" section with an explicit caveat for the arm64 path for exactly this reason.
Do not quietly upgrade a caveat into a guarantee.

### Never commit credentials

- `.env` holds the admin password.
- `.gitea-token` is a live API credential with full scope.

Both are in `.gitignore`. If you ever find one staged, stop and remove it — and treat the
token as compromised, because it has been written to disk in a commit.

A backup archive also contains secrets: `app.ini` holds `LFS_JWT_SECRET` and similar.
Never commit a backup into the repository, and never puzzle over why `data/jwt/private.pem`
is in one.

### Backups: never copy the live files

The database is inside a Docker volume, inside `docker_data.vhdx`, which holds all of
Docker's data. There is no folder to copy, and a live SQLite file copied mid-write can be
torn. Use `gitea dump` via `scripts\Backup-Gitea.ps1`, which takes a consistent snapshot
and verifies the result contains repositories before keeping it.

If you touch the backup or restore path, **prove the round trip**: restore into a scratch
instance on spare ports and confirm the revision tags come back. A backup that has never
been restored is an untested assumption, and this one has been restored once already — do
not regress that.

### Prefer the boring, verifiable approach

- PowerShell 5.1 compatibility. This must run on stock Windows, not only on PowerShell 7.
  That means no `??`, no ternary `? :`, no `-in` assumptions about newer behaviour, and
  care with `Set-Content` encoding.
- No new dependencies. The whole point is that "they already have most of the
  dependencies" — adding a requirement undercuts the deliverable.
- Use `python`/`node` only if already required. Neither is required today.

### Windows specifics to respect

- **`$ErrorActionPreference`**: native tools write ordinary progress to stderr. Under
  `'Stop'`, a redirected `2>&1` turns that into a terminating error and aborts the run.
  Use `'Continue'` plus explicit `$LASTEXITCODE` checks, or `2>$null`. This bug has
  already been fixed once here; do not reintroduce it.
- **`Set-Content` appends a trailing newline** on every call, so rewriting a file grows it
  each run and every re-run looks like a real change. Use
  `[System.IO.File]::WriteAllText()`.
- **`wsl.exe` writes UTF-16LE.** Strip NUL bytes before parsing, or output reads as
  `L e g a c y`.
- **Ports inside Windows' reserved ranges cannot be bound**, with a misleading
  "access permissions" error. Default to 3022 for SSH, never 2222.
- **`container_name` is deliberately absent** from `compose.yaml`, so two checkouts do not
  collide. Do not add it back.

### Be honest about verification limits

The scripts were verified on x64 Windows with Docker Desktop 29.8.2. arm64 support rests
on the published multi-arch image manifest, not on a run on Arm hardware. Keep that
distinction visible rather than letting it blur into a general "verified" claim.

---

## Layout

```
compose.yaml          server definition; every setting carries its reason in a comment
.env.example          template -> .env (gitignored)
scripts/              Inspect-Environment.ps1, Deploy-Gitea.ps1, New-Project.ps1, Backup-Gitea.ps1
templates/            AGENTS.md, Save-Revision.*, gitignore.default, gitattributes.default
docs/                 troubleshooting.md, backup-and-restore.md, arm64-notes.md, codex-integration.md
```

When adding a `compose.yaml` setting, put the **why** in a comment above it. Every
non-obvious line here exists because a default was wrong, and that reason is the most
valuable part of the file.

---

## Revision discipline

Revisions are tagged `r1`, `r2`, `r3`, … and pushed. Commit, tag, push at the end of a
turn that changed something. Never force-push, rebase, `reset --hard`, or amend a pushed
commit — with Git LFS in play, rewriting history can orphan objects and break future
clones.
