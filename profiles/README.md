# profiles/

One filled-in profile per client or project, produced by running the interview in
[../docs/interview.md](../docs/interview.md).

Start from [../templates/PROFILE.md](../templates/PROFILE.md):

```powershell
Copy-Item ..\templates\PROFILE.md .\<client>.md
```

Attach the machine facts first — never ask a person what a command can answer:

```powershell
..\scripts\Get-MachineProfile.ps1 -OutFile .\<client>-machine.md
```

## What belongs here

A profile records:

- the **success criteria**, in the client's own words
- the **baseline** — what the workflow looks like *before* any change, so there is
  something to compare against at the end
- answers **verbatim**, plus what each one implies
- the **assumptions** the setup is running on, written down
- **open questions** — what is still unknown
- the **change list** — every answer that altered something

## Why it lives in the repo

So the next session does not rediscover the same facts, and so the reasoning behind each
setting is reviewable. `compose.yaml` records *what* was configured; a profile records
*why*, and what was still uncertain.

## Rules

- **This folder is tracked, so it is visible to anyone with the repository.** Keep
  credentials out of it — reference `.env` and `.gitea-token` instead of copying values in.
  A profile is a record of decisions, not a place to store secrets.
- **Date every edit.** A stale profile is worse than no profile, because it is trusted.
- **Re-run the interview** when the client changes machine, adds a collaborator, moves
  where projects live, or starts working with a new kind of asset.
- Keep the **open questions** section honest. A pilot that pretends to certainty cannot be
  improved.

> This file also exists for a mechanical reason: **Git cannot track an empty folder.**
> Without it, `profiles/` would never appear on the server or in a clone.
