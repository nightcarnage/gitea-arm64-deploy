# Windows on Arm notes

## Short version

Nothing here needs x64 emulation. `gitea/gitea:1` ships a native `linux/arm64` image, so
on Windows on Arm the server runs natively. Install the **Arm64** build of Docker Desktop
and you are done.

---

## Verified image support

```powershell
docker manifest inspect gitea/gitea:1
```

returns manifests for:

```
linux/amd64
linux/arm64      <- the one that matters on Windows on Arm
linux/riscv64
```

The same multi-arch tag serves both architectures, so `compose.yaml` needs no `platform:`
override and no special handling.

---

## Confirm what your engine is actually doing

A multi-arch image is only native if the *engine* is native. Check both:

```powershell
docker version --format '{{.Server.Os}}/{{.Server.Arch}}'
```

- `linux/arm64` — native. Nothing to do.
- `linux/amd64` — the engine is running under x64 emulation. It works, but every
  container instruction is translated, which costs real performance and memory.

`scripts\Inspect-Environment.ps1` performs this check and warns when it sees an amd64
engine on an Arm64 host.

---

## Which builds to install

| Component | Install | Note |
|---|---|---|
| Docker Desktop | the **Arm64** build | The x64 installer also runs, under emulation — slower, and easy to do by accident. |
| WSL2 | `wsl --install` | Picks the arm64 distribution for the host automatically. |
| Git for Windows | arm64 build if offered | The x64 build works under emulation. |
| Git LFS | bundled with Git | — |
| PowerShell | native Arm64 | See below. |

### Watch out for emulated PowerShell

An x64 PowerShell running on Arm64 works, and is a common default. If your shell is
emulated, everything it launches inherits that, including `docker` and `git`.

```powershell
[System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture   # genuinely Arm64
$env:PROCESSOR_ARCHITECTURE                                           # AMD64 means emulated shell
$env:PROCESSOR_ARCHITEW6432                                           # ARM64 means "I am emulated on Arm"
```

`Inspect-Environment.ps1` reports this combination as a warning. It is a performance
issue, not a correctness one.

---

## What is identical to x64

These are **not** architecture-specific. They will bite on Arm exactly as they do on x64,
and they are the ones that actually cost time:

1. **Windows reserves blocks of TCP ports** for Hyper-V/WSL. Binding inside one fails with
   a misleading *"access permissions"* error even when the port is free. Port 2222 is the
   usual casualty, which is why SSH defaults to 3022 here.

   ```powershell
   netsh interface ipv4 show excludedportrange protocol=tcp
   ```

2. **Docker Desktop needs a full restart after a WSL update.** `wsl --version` on an old
   binary makes the engine report `WSL update required` and refuse to start.

3. **Gitea ships `LFS_START_SERVER = false`**, so Git LFS pushes 404 until it is enabled.

4. **Virtual Machine Platform must be enabled** (`Enable-WindowsOptionalFeature
   -Online -FeatureName VirtualMachinePlatform -All`), which needs admin and a reboot.

5. **Git cannot track an empty folder.** It will not appear on the remote and is not
   created by a clone.

---

## Performance expectations

For this workload — a single-user Gitea on SQLite — the difference between native arm64
and emulated amd64 is not dramatic. Most time goes in Git object packing and file I/O,
which are not CPU-bound in a way that emulation punishes badly.

The case for native is: lower memory overhead, no translation layer to misbehave, and
correct `docker version` reporting. If you find yourself running the server under
emulation and it works, that is a legitimate place to stop.

---

## Caveat on this kit

The scripts and Compose file here were **executed and verified on x64** Windows 10 with
Docker Desktop 29.8.2 — deployments, health checks, admin creation, token authentication,
idempotent re-runs, and a full teardown.

They were **not executed on Arm hardware.** The Arm64 claim rests on:

- the published multi-arch image manifest for `gitea/gitea:1` (verified, see above), and
- Docker Desktop's documented Arm64 build for Windows on Arm.

Nothing in this kit is architecture-specific — there is no `platform:` pin, no compiled
binary, no x64-only tooling — so there is no reason it should behave differently. But if
you are standing this up on Arm, **run `scripts\Inspect-Environment.ps1` first** and read
what it says about your engine.
