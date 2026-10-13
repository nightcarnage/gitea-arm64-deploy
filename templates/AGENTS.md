PROJECT_NAME
============

> Replace this line with one sentence describing the project, in plain language.
> Whoever reads this next may be an AI agent with no context.

The global `~/.codex/AGENTS.md` explains the machine-wide rules (local Gitea server,
credentials, tool locations, known pitfalls). Read it too. This file covers only
this project.

---

## The one rule

**Version control replaces manual copies.** Never create `PROJECT_NAME-2`,
`PROJECT_NAME-backup`, `-final`, `-copy`, `-old`, or dated copies of anything.

Save a **revision** instead:

```powershell
.\scripts\Save-Revision.ps1 "what changed"
```

That commits, tags the next `r<N>`, and pushes. Revisions are `r1`, `r2`, `r3`, … forever.
Never reuse or renumber. **A revision is not safe until it is pushed.**

If you find existing stray copies, say so and offer to fold them into history — never
silently delete someone's work.

---

## Repository

| | |
|---|---|
| Server | {{SERVER_URL}} |
| Repository | {{REPO}} |
| Local path | {{LOCAL_PATH}} |
| Clone | {{CLONE_URL}} |

---

## Working agreement

The person on this project is **not a programmer**. They think in revisions — points they
can return to. Do the version-control work for them and explain changes in plain language:
what they will see, not what the code does.

Before ending a turn that changed anything: commit it, tag it, push it.

### If the server is unreachable

Still commit and tag locally. Then tell the creator, in plain words, that the work is saved
on this PC but not yet backed up, that Docker Desktop needs starting, and that pushing later
will catch it up. Losing a session's work to a stopped container is the one outcome worth
engineering against.

---

## Never commit

- **Secrets**: tokens, passwords, API keys, `.env` files, licence files.
- **Build caches**: `Library/`, `Temp/`, `Obj/`, `Build/`, `Logs/`, `UserSettings/` (Unity),
  `node_modules/`, and generated `*.csproj` / `*.sln`.
- Anything matched by `.gitignore`.

Large binaries are stored with **Git LFS** via `.gitattributes`. Commit them normally — do
not exclude them, and do not add them to `.gitignore`. Each machine needs `git lfs install`
once.

Never force-push, rebase, `reset --hard`, amend pushed commits, rewrite history, delete a
remote branch or tag, or run `git clean -xdf`.

---

## Verify before claiming success

A clean commit says nothing about whether the thing runs. Run it, or say plainly that you
could not verify it.

Where this project's own verification command is:

- _replace this with how to check a change actually works_

---

## Never edit build output

Edit the source and rebuild. A change made directly to a generated file is invisible to Git
and is destroyed by the next build.
