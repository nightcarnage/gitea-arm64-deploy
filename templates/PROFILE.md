PROFILE — {{CLIENT_OR_PROJECT}}
================================

> Copy this to `profiles/<name>.md` when you run the interview
> (`docs/interview.md`), and fill it in. It is the written record of what was
> assumed, what was actually true, and what is still unknown.
>
> Keep it up to date. Date every edit — a stale profile is worse than none,
> because it is trusted.

| | |
|---|---|
| Prepared for | {{NAME}} |
| Interviewed | {{DATE}} by {{WHO}} |
| Machine | {{HOSTNAME}} |
| Kit version | {{rN of the deploy repo}} |
| Status | draft / agreed / superseded |

---

## 1. Success criteria (verbatim)

> **"If this works perfectly, what's different in a month?"**

_{{paste their answer, in their words — do not paraphrase}}_

> **"What's the most annoying part of how you save things now?"**

_{{their words}}_

**How we will judge this pilot:**

- [ ] {{measurable statement}}
- [ ] {{measurable statement}}

---

## 2. Baseline — what it looks like today

Record this **before** changing anything, or there is nothing to compare against
at the end.

| Measure | Value on {{DATE}} |
|---|---|
| Where projects live | |
| How a version is saved today | |
| Number of folder copies of one project | |
| Can they say which copy is the real one? | yes / no |
| How they recover a broken version | |
| Roughly how long that takes | |
| Have they ever lost work? | |
| Approx. size of a typical project | |
| Kinds of files they work in | |
| Anyone else involved | |
| Machines used | |
| Current backup situation | |

---

## 3. Machine profile

_Paste the output of `scripts\Get-MachineProfile.ps1` here, or link the file._

```
{{paste machine profile}}
```

### Things the machine profile settled — do NOT ask these again

- OS / architecture: {{ }}
- Docker / engine: {{ }}
- WSL: {{ }}
- git + LFS: {{ }}
- Codex AGENTS.md present and not empty: {{ }}
- Creative tools detected: {{ }}
- **Cloud sync:** OneDrive folder `{{ }}`, running: {{ }}, Known Folder Move: {{ }}
- **Desktop in OneDrive:** {{ }}  ← if `False`, their "backed up" belief is wrong
- Ports reserved by Windows: {{ }} — so HTTP `{{ }}`, SSH `{{ }}`
- Existing git repositories found: {{ }}
- Possible manual copies found: {{ }}

---

## 4. Answers

Record **verbatim**, then note what it implies. Add "don't know" rather than guessing.

### Where the files live

**Q: Where do your project files actually live?**
> _

Implies: _

**Q: Do you ever work on a second computer or a laptop?**
> _

Implies: _

**Q: Does anyone else need to see or change these files?**
> _

Implies: _

**Q: Anything that must never leave this machine?**
> _

Implies: _

### The habit being replaced

**Q: How do you save a version you might want to come back to?**
> _

**Q: How many copies do you have right now / which one is the real one?**
> _

Implies: _

**Q: When something breaks, how do you get back to a version that worked?**
> _

Implies: _

**Q: Roughly how big is one of these projects?**
> _

Implies: _

### Assets

**Q: What kind of files do you spend most of your time in?**
> _

Implies (LFS patterns): _

**Q: Do you have a folder structure or naming convention you care about?**
> _

Implies: _

### Workflow

**Q: When you finish something worth keeping, what should happen without you thinking about it?**
> _

Implies: _

**Q: Should the assistant save revisions on its own, or ask first?**
> _

**Q: What should it never do without asking?**
> _

Implies (AGENTS.md autonomy section): _

**Q: What do you call a version when it matters?**
> _

Implies (tag scheme): _

### Operations

**Q: How often should backups run, and where — this machine, the cloud, or both?**
> _

Implies: _

**Q: Is there a time of day this machine is on but not busy?**
> _

Implies (schedule): _

**Q: If a week of work vanished tomorrow, what would you wish you'd done differently?**
> _

**Q: Anything about your setup you'd describe as held together with tape?**
> _

---

## 5. Decisions

What we are actually going to do, given the above.

| Decision | Value | Because |
|---|---|---|
| Server | local Gitea in Docker | |
| HTTP port | | |
| SSH port | | |
| Reachable from | localhost only / LAN | |
| Projects live at | | |
| Repos | one per project | |
| LFS | on / off | |
| Revision tags | r1… / other | |
| Backups | destination + frequency + retention | |
| Agent autonomy | saves on its own / asks first | |

---

## 6. Change list

Every interview answer that altered something. If a row is empty, the interview
did not change the setup — which is worth knowing.

| Answer | Change made | Done? |
|---|---|---|
| | | [ ] |
| | | [ ] |
| | | [ ] |

---

## 7. Assumptions we are running on

Stated plainly, so they can be checked later. An assumption nobody wrote down is a
future argument.

- We assume **{{one machine}}**. If that changes, remote access must be revisited.
- We assume projects are **{{not}}** inside a cloud-synced folder.
- We assume **{{no}}** collaborator needs access.
- We assume assets are **{{small enough for plain Git / need LFS}}**.
- We assume the person will run the save button rather than the agent doing it silently.
- _

---

## 8. Open questions

Unanswered, or answered with a guess that needs confirming.

- _
- _

---

## 9. What changed after the pilot

Fill in at the end, against the baseline in §2.

| Measure | Before | After |
|---|---|---|
| Folder copies of one project | | |
| Can they say which copy is real? | | |
| Time to recover a previous version | | |
| Backups running | | |
| Lost work? | | |

**Did it meet the success criteria in §1?** yes / partly / no — because:

_

---

## 10. Re-run history

| Date | Who | What changed |
|---|---|---|
| | | |
