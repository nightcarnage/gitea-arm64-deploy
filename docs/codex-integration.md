# Codex integration — how the agent learns the rules

The point of this kit is that an agent picks up the house rules **without being told each
time**. That happens through `AGENTS.md` files.

---

## Where Codex looks

| File | Scope | Purpose |
|---|---|---|
| `%USERPROFILE%\.codex\AGENTS.md` | **Every** session, every folder | The index: which projects exist, where they live, the server, credentials, tool paths, known pitfalls |
| `<project>\AGENTS.md` | That project | How to work on it, how to verify it, what is project-specific |
| `%USERPROFILE%\.codex\config.toml` | Machine | Codex configuration, including `[mcp_servers.*]` |

Both `AGENTS.md` files are read. The global one carries facts that are true everywhere;
the project one carries facts that are true of one project. Duplicating the universal
rules into every project is how they drift out of sync.

---

## The empty-file trap

The single most common failure: **`AGENTS.md` exists but is empty.**

```powershell
Get-Item $env:USERPROFILE\.codex\AGENTS.md | Select-Object Length
```

`0` means it is doing nothing at all, while looking configured. This is exactly the kind
of thing that wastes an afternoon, because the file's existence is mistaken for its
effect.

`scripts\Inspect-Environment.ps1` reports the byte count and warns explicitly when the
file is present but empty.

---

## What belongs in AGENTS.md

**Rules, not prose.** The agent needs to know what to do and what never to do.

Worth including:

- **The one rule.** "Never create copies; save a revision." Stated first, bluntly.
- **The revision vocabulary.** Tags are `r1`, `r2`, `r3`, …; never reused.
- **Never commit**: secrets, build caches, copyrighted assets, generated files.
- **Never do**: force-push, rebase, `reset --hard`, amend pushed commits, `clean -xdf`.
  Force-pushing is worth calling out because with LFS it can orphan objects and break
  future clones.
- **Verify before claiming success**, with the project's actual command. "Run
  `unity recompile`" beats "verify the change".
- **The specific pitfalls of this machine** — reserved ports, the LFS default, empty
  folders. These are cheap to write down and expensive to rediscover.
- **Exact paths.** The absolute path to `gzdoom.exe` or the Unity CLI saves a search.

Worth leaving out: general advice the model already has, long rationale, and anything
that will be stale in a month. An over-long `AGENTS.md` is read less reliably than a
short one.

---

## MCP servers (`config.toml`)

MCP servers are declared in `%USERPROFILE%\.codex\config.toml`:

```toml
[mcp_servers.unity]
command = "C:\\Users\\you\\AppData\\Local\\Unity\\bin\\unity.exe"
args = ["mcp"]
```

Two things learned the hard way:

1. **Codex rewrites this file.** Tools like `unity mcp configure codex` add their own
   sections and adjust sandbox network policy. Back it up before letting anything
   touch it:

   ```powershell
   Copy-Item $env:USERPROFILE\.codex\config.toml $env:USERPROFILE\.codex\config.toml.bak
   ```

2. **The tool may not be on `PATH`.** Unity's CLI is not, so the config records an
   absolute path and says so:

   > `'unity' not found on PATH. Using absolute path: ...`
   > `This path is machine-specific — update the config if you move the binary.`

   That comment is a real warning: moving the tool silently breaks the entry.

### Windows caveat: Node-based MCP servers

Many MCP servers are launched through `npx`. On a machine without Node on `PATH` those
fail to start, and the failure shows up as the agent simply not having the tools.

Codex ships **its own Node runtime**, so a Node-based server can be pointed at it:

```
%LOCALAPPDATA%\OpenAI\Codex\runtimes\cua_node\<hash>\bin\node.exe
```

Check whether Node exists before assuming:

```powershell
Get-Command node, npx -ErrorAction SilentlyContinue
```

`Inspect-Environment.ps1` does not check Node, because this kit needs none.

---

## Skills

Some tools install an agent skill — a folder of instructions the agent can consult:

```
%USERPROFILE%\.agents\skills\<name>\
```

The Unity CLI does this (`unity skill install codex`), which is a good pattern to copy:
it puts a large, structured reference next to the agent instead of bloating `AGENTS.md`.

---

## A working arrangement

1. Put the machine-wide facts in `%USERPROFILE%\.codex\AGENTS.md` **once**.
2. Let `New-Project.ps1` drop a filled-in project `AGENTS.md` into each new project.
3. Keep the revision button (`Save-Revision.ps1`) in the project, so the agent and the
   person use the same mechanism.
4. Re-run `Inspect-Environment.ps1` when something behaves oddly — it is read-only and
   answers "is this machine actually configured?" faster than reading config files.

The test of whether it is working: start a fresh session in a project and ask the agent
what the revision rules are. If it has to go looking, something is in the wrong place.
