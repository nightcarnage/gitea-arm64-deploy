<#
.SYNOPSIS
    Read-only preflight check before deploying Gitea: WSL, virtualisation, Docker,
    git, Codex, ports and disk.

.DESCRIPTION
    Changes nothing. Every check reports OK / WARN / FAIL with the reason and, where
    there is one, the exact command that fixes it.

    Designed for the "they already have most of the dependencies" case - run this to
    find out precisely which one is missing rather than guessing.

    Exits 1 if anything FAILs, so it is usable as a gate.

.EXAMPLE
    .\scripts\Inspect-Environment.ps1
    .\scripts\Inspect-Environment.ps1 -HttpPort 3300 -SshPort 3222
#>
[CmdletBinding()]
param(
    [int]$HttpPort = 3000,
    [int]$SshPort  = 3022
)

$script:fail = 0
$script:warn = 0

function Check($label, $state, $detail, $fix) {
    # state: OK | WARN | FAIL
    $colour = switch ($state) { 'OK' { 'Green' } 'WARN' { 'Yellow' } default { 'Red' } }
    Write-Host ("  {0,-4} {1,-26} {2}" -f $state, $label, $detail) -ForegroundColor $colour
    if ($fix) { Write-Host ("       -> {0}" -f $fix) -ForegroundColor DarkGray }
    if ($state -eq 'FAIL') { $script:fail++ }
    if ($state -eq 'WARN') { $script:warn++ }
}

Write-Host ""
Write-Host "Gitea on Windows - environment check" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

# ------------------------------------------------------------------ operating system
$os = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
$isArm = $os -eq 'Arm64'
Check 'architecture' 'OK' "$os  ($([System.Environment]::OSVersion.VersionString))"
if ($isArm) {
    Write-Host "       Arm64 detected - gitea/gitea publishes a native linux/arm64 image," -ForegroundColor DarkGray
    Write-Host "       so it runs without x64 emulation." -ForegroundColor DarkGray
}
if ($os -eq 'X64' -and $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') {
    Check 'power shell arch' 'WARN' 'running x64 PowerShell under Arm emulation' `
        'Prefer the native Arm64 PowerShell for speed; everything still works.'
}

# --------------------------------------------------------------------------------- WSL
$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Check 'WSL' 'FAIL' 'wsl.exe not found' 'wsl --install   (then reboot)'
} else {
    # wsl.exe writes UTF-16LE. Read naively, the interleaved NUL bytes break regex
    # matching and render as "L e g a c y", so strip them before parsing.
    $ver = ((& wsl.exe --version 2>&1 | Out-String) -replace "`0", '')
    if ($ver -match 'WSL version:\s*(\S+)') {
        Check 'WSL' 'OK' "version $($Matches[1])"
    } elseif ($ver -match 'Invalid command line option') {
        # The legacy inbox wsl.exe does not understand --version. Docker Desktop
        # reads this as "WSL update required" and refuses to start its engine.
        Check 'WSL' 'FAIL' 'the inbox wsl.exe does not support --version (too old)' `
            'wsl --update   then fully restart Docker Desktop'
    } else {
        Check 'WSL' 'WARN' 'could not read the WSL version' 'wsl --update'
    }
    $distroText = ((& wsl.exe -l -q 2>&1 | Out-String) -replace "`0", '')
    $distroNames = @($distroText -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($distroNames.Count -gt 0) {
        Check 'WSL distros' 'OK' ($distroNames -join ', ')
    } else {
        Check 'WSL distros' 'WARN' 'no distribution installed' `
            'Only needed for interactive Linux use; Docker brings its own distro.'
    }
}

# ------------------------------------------------------------------------ virtualisation
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
if ($vmFeature) {
    if ($vmFeature.State -eq 'Enabled') { Check 'VirtualMachinePlatform' 'OK' 'enabled' }
    else {
        Check 'VirtualMachinePlatform' 'FAIL' $vmFeature.State `
            'Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All  (needs admin + reboot)'
    }
}
$hv = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).HypervisorPresent
if ($hv) { Check 'hypervisor' 'OK' 'present (a hypervisor is running)' }
else { Check 'hypervisor' 'WARN' 'not detected' 'Usually means virtualization is off in BIOS/UEFI.' }

# ------------------------------------------------------------------------------- Docker
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Check 'docker CLI' 'FAIL' 'not found on PATH' 'Install Docker Desktop for Windows.'
} else {
    Check 'docker CLI' 'OK' $docker.Source
    $engine = (& docker version --format '{{.Server.Version}}' 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $engine -match '^\d') {
        Check 'docker engine' 'OK' "server $engine"
        $srvArch = (& docker version --format '{{.Server.Arch}}' 2>&1 | Out-String).Trim()
        $srvOs   = (& docker version --format '{{.Server.Os}}' 2>&1 | Out-String).Trim()
        Check 'engine platform' 'OK' "$srvOs/$srvArch"
        if ($isArm -and $srvArch -eq 'amd64') {
            Check 'arm64 native' 'WARN' 'engine is amd64 under emulation' `
                'Install the Arm64 build of Docker Desktop for full speed.'
        }
    } else {
        Check 'docker engine' 'FAIL' 'not responding (Docker Desktop not running?)' `
            'Start Docker Desktop and wait for "Engine running".'
    }
    $compose = (& docker compose version 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -eq 0) { Check 'docker compose' 'OK' $compose }
    else { Check 'docker compose' 'FAIL' 'compose plugin unavailable' 'Update Docker Desktop.' }
}

# ----------------------------------------------------------------------- git and LFS
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Check 'git' 'OK' (& git --version) } else { Check 'git' 'FAIL' 'not found' 'winget install Git.Git' }
$lfs = $null
if ($git) { $lfs = (& git lfs version 2>&1 | Out-String).Trim() }
if ($lfs -and $lfs -match 'git-lfs') { Check 'git-lfs' 'OK' $lfs }
else { Check 'git-lfs' 'FAIL' 'not installed' 'git lfs install  (or winget install GitHub.GitLFS)' }

# ------------------------------------------------------------------------------ Codex
$codexDir = Join-Path $env:USERPROFILE '.codex'
if (Test-Path $codexDir) {
    Check 'codex home' 'OK' $codexDir
    $agents = Join-Path $codexDir 'AGENTS.md'
    if (Test-Path $agents) {
        $len = (Get-Item $agents).Length
        if ($len -gt 0) { Check 'codex AGENTS.md' 'OK' "$len bytes - the agent will pick this up" }
        else {
            Check 'codex AGENTS.md' 'WARN' 'exists but is EMPTY' `
                'An empty AGENTS.md teaches the agent nothing. Copy templates\AGENTS.md into it.'
        }
    } else {
        Check 'codex AGENTS.md' 'WARN' 'missing' `
            'Copy templates\AGENTS.md to %USERPROFILE%\.codex\AGENTS.md so the agent knows the rules.'
    }
    $cfg = Join-Path $codexDir 'config.toml'
    if (Test-Path $cfg) { Check 'codex config.toml' 'OK' "$((Get-Item $cfg).Length) bytes" }
} else {
    Check 'codex home' 'WARN' "no $codexDir" 'Only needed if this machine runs OpenAI Codex.'
}

# ----------------------------------------------------------------------- port availability
function Get-ReservedTcpRanges {
    $ranges = @()
    $out = & netsh interface ipv4 show excludedportrange protocol=tcp 2>&1
    foreach ($line in $out) {
        if ($line -match '^\s*(\d+)\s+(\d+)(\s+\*)?\s*$') {
            $ranges += [pscustomobject]@{ Start = [int]$Matches[1]; End = [int]$Matches[2] }
        }
    }
    return $ranges
}

function Test-PortForGitea($label, $port) {
    $reserved = Get-ReservedTcpRanges | Where-Object { $port -ge $_.Start -and $port -le $_.End }
    if ($reserved) {
        Check $label 'FAIL' "port $port is inside a Windows-reserved range ($($reserved[0].Start)-$($reserved[0].End))" `
            'Pick another port. Windows blocks these even when nothing is listening.'
        return
    }
    $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($inUse) {
        $procName = (Get-Process -Id $inUse[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName
        # Docker's port proxy is what owns a published port. On Windows on Arm and on
        # recent x64 builds that shows up as 'wslrelay', not 'com.docker.backend'.
        $dockerOwners = @('wslrelay', 'com.docker.backend', 'docker-proxy', 'vpnkit', 'com.docker.build')
        if ($procName -in $dockerOwners) {
            Check $label 'OK' "port $port is already published by Docker ('$procName') - Gitea is probably already up"
        } else {
            Check $label 'WARN' "port $port is in use by '$procName'" 'Free it, or choose another port.'
        }
    } else {
        Check $label 'OK' "port $port is free"
    }
}

Test-PortForGitea 'http port' $HttpPort
Test-PortForGitea 'ssh port'  $SshPort

# --------------------------------------------------------------------------- disk space
$drive = (Get-Item $env:USERPROFILE).PSDrive
$freeGB = [math]::Round((Get-PSDrive $drive.Name).Free / 1GB, 1)
if ($freeGB -lt 5) { Check 'free disk' 'WARN' "$freeGB GB free on $($drive.Name):" 'Images need a few GB.' }
else { Check 'free disk' 'OK' "$freeGB GB free on $($drive.Name):" }

# ------------------------------------------------------------------------------- verdict
Write-Host ""
if ($script:fail -eq 0) {
    Write-Host "Ready to deploy. ($script:warn warning(s))" -ForegroundColor Green
    Write-Host "  .\scripts\Deploy-Gitea.ps1" -ForegroundColor Cyan
    exit 0
} else {
    Write-Host "$script:fail problem(s) must be fixed first, $script:warn warning(s)." -ForegroundColor Red
    Write-Host "See docs\troubleshooting.md" -ForegroundColor Cyan
    exit 1
}
