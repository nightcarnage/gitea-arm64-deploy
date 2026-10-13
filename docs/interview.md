# The interview

How to work out what a person actually needs, before trusting any script in this kit.

---

## Why this exists

Every script here encodes **our** assumptions: that projects live in a normal folder, that
one person uses one machine, that the user thinks in revisions. Some of those will be
wrong. On a pilot, the interview is how you find out *which* ones — and finding out costs
far less than shipping the wrong setup and discovering it three weeks later.

The output is a filled-in profile (`templates/PROFILE.md`) that lives in the repo, so the
next session — human or agent — does not have to rediscover any of it.

---

## The single most important rule

> **Detect machine facts with commands. Ask the person only about intent.**

```powershell
.\scripts\Get-MachineProfile.ps1 -OutFile .\profiles\<client>-machine.md
```

That answers: OS, architecture, CPU, RAM, disk, WSL, Docker, git, LFS, Codex state, which
creative tools are installed, cloud-sync status, reserved ports, and (with `-ScanProjects`)
which folders are already git repos and **which look like manual copies**.

> **A caveat on `-ScanProjects`.** The "possible manual copies" list is a name-based
> heuristic (`-copy`, `-backup`, `final`, `v2`, `(2)`, dates) and it produces **false
> positives** — on the reference machine it flagged book folders in a Calibre library and a
> folder called `New folder (2)`. Treat it as a **prompt for a question, never a finding**:
> "I noticed some folders that look like saved versions — is that how you do it?" Confirm
> with the person before concluding anything or touching any of it.
>
> **Also note `Library/`-style folders inside a Calibre, Lightroom or similar library.**
> Those are managed by their own application and are usually not project folders at all.

**Never ask a non-programmer any of the following.** They are already in the profile:

| Do not ask | Because |
|---|---|
| How many cores / how much RAM? | The machine reports it |
| Do you have Docker installed? | Detectable |
| Is WSL set up? | Detectable |
| What version of Unity / GZDoom? | Detectable, or findable on disk |
| Is OneDrive running? | Detectable, and the answer is often "no" when they think yes |
| Do you use Git already? | Non-programmers will say "yes" to sound cooperative |

Ask about **what they do, what they're afraid of, and what would make this worth it.** None
of that is in any registry key.

---

## How to ask

The thing people get wrong is treating this as a form. It is a conversation with a
non-technical person about their own work. Rules:

**1. Every question must change a decision.** If no answer would alter the setup, the
question is noise. Delete it. This is why the bank below has a "what the answer changes"
column — if you cannot fill that in for a question, do not ask it.

**2. Plain words, no jargon.** Compare:

| Bad | Good |
|---|---|
| "Do you want Git LFS with a custom filter set?" | "Do you work with big files — Photoshop, audio, 3D models?" |
| "Should we enable Known Folder Move?" | "Are the folders you work in backed up anywhere right now?" |
| "Single-user or multi-tenant?" | "Is this just you, or does someone else need to get at these files?" |

**3. One question at a time, with choices.** Freeform answers from non-technical people
about tooling are usually guesses. Offer 3–4 concrete options; "I don't know" is always
allowed.

**4. Every question needs a safe default.** If they do not know, you say *"we'll assume X,
and here's what that means"* — and write that assumption in the profile. An unanswered
question with a stated default is fine. An unanswered question with silence is a landmine.

**5. Ask in batches of 5–7, and save after each batch.** This is a pilot; the person has
actual work to do. A 25-question intake at once produces guessed answers.

**6. Ask about the past, not the future.** "How do you recover a broken version today?" gets
a truthful answer. "Do you want semantic versioning?" gets a confident guess.

**7. Record verbatim answers.** Their words are the specification. When they say "I keep a
backup copy in case the timeline breaks", that phrase should end up in the setup, not your
paraphrase of it.

**8. Ask the success question first.** It shapes everything else, and it is the one thing a
pilot cannot be evaluated without.

---

## Phase 1 — the opening two questions

Ask these before anything technical. Do not skip them.

> **1. "If this works perfectly, what's different in a month?"**
>
> *What it changes:* the definition of done. Write it down verbatim; quote it back at the
> end of the pilot.
>
> *Typical real answers:* "I stop having `final-FINAL` folders"; "I can show a client what
> changed"; "I stop losing a day's work when something breaks".

> **2. "What's the most annoying part of how you save things now?"**
>
> *What it changes:* which part of the workflow must actually be good, versus merely
> present. If the pain is "I can't tell which copy is newest", then tag naming and `git log`
> matter more than anything else in this kit.

---

## Phase 2 — the question bank

Ordered by how much the answer changes. Stop when the answers stop changing decisions.

### Where the files live

> **3. "Where do your project files actually live — Desktop, Documents, an external drive, somewhere else?"**
>
> *Why:* this is the highest-risk unknown in the whole setup.
>
> *What the answer changes:*
> - **A cloud-synced folder** (OneDrive, Dropbox, Google Drive) → **stop and raise it.** A
>   git repository inside a synchronised folder is a well-known way to corrupt both the
>   repository and the sync. Plan to move the working copy out, or exclude the folder.
> - **An external drive** → drive letter stability, and backups need to know about it.
> - **Desktop** → check whether Desktop is synced before congratulating yourself. On the
>   reference machine it *looked* synced and was not.
>
> *Safe default:* `<user>\source\repos`, which is outside every sync folder.

> **4. "Do you ever work on a second computer or a laptop?"**
>
> *What the answer changes:* a single machine can use a purely local server and forget about
> remote access. More than one means deciding between SSH keys and HTTPS tokens, whether the
> server must be reachable from the network, and what happens when a laptop is offline.
>
> *Safe default:* assume one machine, keep the server on `localhost` only.

> **5. "Does anyone else need to see or change these files?"**
>
> *What the answer changes:* access control, whether Gitea binds to `127.0.0.1` or the LAN,
> and how strong the password policy must be. A LAN-reachable server with a 7-character
> password is a different risk from a laptop-only one.
>
> *Safe default:* just them; bind to localhost only.

> **6. "Is there anything in these projects that must never leave this machine — client material, licensed art, personal files?"**
>
> *What the answer changes:* whether a local server was even the right call (it usually is,
> and this is the reason), plus what must be added to `.gitignore`.
>
> *Safe default:* assume yes, and keep everything local.

### The habit being replaced

> **7. "How do you save a version you might want to come back to?"**
>
> *Why:* this describes the thing being replaced. On the reference machine the answer was
> folder copies (`project-main0`, `project-main1`), which had already silently drifted apart.
>
> *What the answer changes:* how much migration work exists, and whether the revision
> vocabulary (`r1`, `r2`, `r3`) will feel natural to them or need a different name.
>
> *Follow-up if the answer is "I copy the folder":* **"How many copies do you have right
> now?"** and **"Which one is the real one?"** — the second usually has no clean answer, and
> that silence is the argument for the whole pilot.

> **8. "When something breaks, how do you get back to a version that worked?"**
>
> *What the answer changes:* how confident restore needs to be, and whether to rehearse it
> together. If they cannot currently recover, that is a headline finding.

> **9. "Roughly how big is one of these projects?"**
>
> *What the answer changes:* whether Git LFS is essential or merely nice. A code-sized
> project (tens of MB) needs nothing; an art-heavy Unity project needs LFS on day one.

### Assets

> **10. "What kind of files do you spend most of your time in — code, images, audio, 3D models, video, documents?"**
>
> *What the answer changes:* the `.gitattributes` LFS patterns, which is exactly the file a
> generic template gets wrong.

> **11. "Do you already have a folder structure or naming convention you care about?"**
>
> *What the answer changes:* whether to fight it or follow it. Follow it.

### Workflow

> **12. "When you finish something worth keeping, what should happen without you having to think about it?"**
>
> *What the answer changes:* whether the revision is automatic on agent turn-end, manual via
> a button, or scheduled. It also reveals which word they use for "finished".
>
> *Safe default:* a button they press, plus the agent saving on their behalf. Never only one.

> **13. "Should the assistant save revisions on its own, or ask you first?"**
>
> *Why:* this is the guardrail question, and the answer changes how the agent behaves more
> than any technical setting.
>
> *What the answer changes:* the AGENTS.md instructions — how much autonomy the agent has,
> and what it must never do unsilenced.
>
> *Ask the follow-up:* **"What should it never do without asking?"** Expect answers about
> deleting and overwriting.

> **14. "What do you call a version when it matters? 'v2', 'final', 'August build'?"**
>
> *What the answer changes:* the naming scheme for revision tags. If they say "final", the
> tagging scheme needs to accommodate `final`, `final2`, `final-final` gracefully rather
> than fighting it — or you explain, once, why a date and a number beat a word.

### Operations

> **15. "How often should backups run, and do you want them on this machine, in the cloud, or both?"**
>
> *What the answer changes:* retention count, destination, and the scheduled task. "Both" is
> the right answer and worth steering toward, because a backup on the same disk as the
> original is not a backup.
>
> *Safe default:* daily, local plus cloud, keep 14.

> **16. "Is there a time of day this machine is usually on but not busy?"**
>
> *What the answer changes:* the backup schedule window. Do not pick 3 a.m. for a machine
> that sleeps at midnight — a scheduled task that never fires is worse than none, because it
> looks like a backup.

> **17. "If a week of work vanished tomorrow, what would you wish you'd done differently?"**
>
> *Why:* this converts a theoretical risk into a felt one, and it is the question that gets
> people to actually care about backups.

### Closing

> **18. "Anything about your setup you'd describe as held together with tape?"**
>
> *Why:* the best finding in the whole interview is usually volunteered here. Working
> around a broken thing for two years makes it invisible to its owner.

---

## Phase 3 — write the profile

Copy `templates/PROFILE.md` into `profiles/<client>.md` in the repo. Paste the machine
profile in, record the answers **verbatim**, then fill in the derived decisions.

Then — the part that makes the interview worth doing — produce a **change list**:

| Answer | Change to make |
|---|---|
| Projects live in a synced folder | Move working copies out; explain why |
| More than one machine | Add SSH keys or a token; decide remote reachability |
| Big art assets | LFS patterns in `.gitattributes` |
| Backups: "both" | Set destination + schedule; verify OneDrive is actually running |
| Agent: "ask first" | Tighten AGENTS.md autonomy section |
| Calls them "builds" | Tag scheme `b1`, `b2`… instead of `r1`, `r2`… |

Every row must become either an action or an explicit "not needed, because…". An interview
whose conclusions do not change the setup was theatre.

---

## Phase 4 — say what you still do not know

The profile ends with **Open questions** and **Assumptions we are running on**. Both are
required.

A pilot that pretends to certainty cannot be improved. "We assumed one machine; if that is
wrong, remote access needs revisiting" is a *good* line to leave in the document — it tells
the next person exactly where the setup will flex and where it will break.

---

## What not to do

- **Do not ask a question the machine can answer.** It wastes their attention and signals
  you have not done your homework.
- **Do not ask for a preference about a technology they have never heard of.** Ask about the
  outcome.
- **Do not run all 18 questions in one sitting.**
- **Do not treat the answers as final.** Write the date and the person; re-ask when the
  workflow changes.
- **Do not skip the success question.** A pilot with no stated success criteria can never be
  declared a success.
- **Do not let a wrong answer pass silently.** If they say "my files are in OneDrive" and the
  machine profile says `DesktopInOneDrive: False`, that discrepancy is the single most
  valuable thing in the interview. Show them; do not paper over it.

---

## Running it again

Re-run when: the client changes machine, adds a collaborator, moves where projects live,
starts using a new kind of asset, or the pilot moves from one person to a team.

The profile is a living document. Date every edit.
