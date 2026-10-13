<#
.SYNOPSIS
    Produce a machine profile: everything about this computer that the setup
    scripts currently assume.

.DESCRIPTION
    READ-ONLY. Changes nothing. Writes a markdown report to stdout (or -OutFile)
    that an agent can read and drop into a profile document.

    The point is to separate two kinds of question:

      * facts about the machine - gather these with commands, never ask the user
      * intentions and habits - only the person can answer those (see docs\interview.md)

    Asking a non-programmer how many CPU cores they have is a bad question. Asking
    them whether they work on one computer or three, and whether their files live in
    a synced folder, is a good question - and neither answer can be detected.

.EXAMPLE
    .\scripts\Get-MachineProfile.ps1
    .\scripts\Get-MachineProfile.ps1 -OutFile .\profile-machine.md
    .\scripts\Get-MachineProfile.ps1 -ScanProjects -Format Json
#>
[CmdletBinding()]
param(
    # Write to a file instead of stdout.
    [string]$OutFile,

    # Look for existing git repositories under common project folders.
    [switch]$ScanProjects,

    # markdown (default) or json
    [ValidateSet('markdown', 'json')]
    [string]$Format = 'markdown',

    # Root folders to search when -ScanProjects is given.
    [string[]]$ScanRoots = @("$env:USERPROFILE\Desktop", "$env:USERPROFILE\Documents", "$env:USERPROFILE\source", "$env:USERPROFILE\source\repos")
)

# Native tools write progress to stderr; under 'Stop' a redirected 2>&1 would abort.
$ErrorActionPreference = 'Continue'

function Try-Native([scriptblock]$Action) {
    # Runs a native command and returns its trimmed output, or $null on failure.
    # Tolerates a $null $LASTEXITCODE: in a fresh session it is unset until the first
    # native command runs, and `$null -ne 0` would wrongly reject a success.
    try { $out = & $Action 2>$null | Out-String
          if ($LASTEXITCODE -eq $null -or $LASTEXITCODE -eq 0) { return $out.Trim() } } catch { }
    return $null
}

function Wsl-Text([scriptblock]$Action) {
    # wsl.exe emits UTF-16LE; the NUL bytes break matching and render as "L e g a c y".
    try { return ((& $Action 2>&1 | Out-String) -replace "`0", '').Trim() } catch { return '' }
}

$p = [ordered]@{}

# ---------------------------------------------------------------------- host
$os  = Get-CimInstance Win32_OperatingSystem
$cs  = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$p.Host = [ordered]@{
    OS          = "$($os.Caption) $($os.Version) (build $($os.BuildNumber))"
    Architecture = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    IsArm64     = ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64')
    Manufacturer = "$($cs.Manufacturer) $($cs.Model)"
    CPU         = $cpu.Name
    Cores       = $cpu.NumberOfCores
    Threads     = $cpu.NumberOfLogicalProcessors
    RamGB       = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
    RamFreeGB   = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    PowerShell  = $PSVersionTable.PSVersion.ToString()
    ShellEmulated = ($env:PROCESSOR_ARCHITEW6432 -ne $null)
}

$drives = @()
foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null -and $_.Used -ne $null })) {
    $drives += [ordered]@{
        Drive   = "$($d.Name):"
        UsedGB  = [math]::Round($d.Used / 1GB, 1)
        FreeGB  = [math]::Round($d.Free / 1GB, 1)
    }
}
$p.Drives = $drives

# -------------------------------------------------------------- virtualisation
$vmFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
$wslVer = Wsl-Text { wsl.exe --version }
$p.Virtualisation = [ordered]@{
    HypervisorPresent     = $cs.HypervisorPresent
    VirtualMachinePlatform = if ($vmFeature) { [string]$vmFeature.State } else { 'unknown' }
    WslVersion           = if ($wslVer -match 'WSL version:\s*(\S+)') { $Matches[1] } elseif ($wslVer -match 'Invalid command line option') { 'TOO OLD - does not support --version' } else { 'unknown' }
    WslKernel            = if ($wslVer -match 'Kernel version:\s*(\S+)') { $Matches[1] } else { '' }
    WslDistros           = @( (Wsl-Text { wsl.exe -l -q }) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ } )
}

# ------------------------------------------------------------------- containers
$dockerCli = Get-Command docker -ErrorAction SilentlyContinue
$engine = Try-Native { docker version --format '{{.Server.Version}}' }
$p.Containers = [ordered]@{
    DockerCli        = if ($dockerCli) { $dockerCli.Source } else { 'not found' }
    EngineVersion    = if ($engine) { $engine } else { 'not responding' }
    EnginePlatform   = if ($engine) { Try-Native { docker version --format '{{.Server.Os}}/{{.Server.Arch}}' } } else { '' }
    ComposeVersion   = Try-Native { docker compose version }
    Context          = Try-Native { docker context show }
}
if ($engine) {
    $p.Containers.Images     = Try-Native { (docker images -q | Measure-Object).Count }
    $p.Containers.Containers = Try-Native { (docker ps -aq | Measure-Object).Count }
    $p.Containers.Volumes    = Try-Native { (docker volume ls -q | Measure-Object).Count }
    $vhd = Get-ChildItem "$env:LOCALAPPDATA\Docker\wsl" -Recurse -Filter '*.vhdx' -ErrorAction SilentlyContinue |
           Sort-Object Length -Descending | Select-Object -First 1
    if ($vhd) { $p.Containers.DiskImage = "$($vhd.FullName) ($([math]::Round($vhd.Length/1GB,2)) GB)" }
}

# ---------------------------------------------------------------- version control
$p.VersionControl = [ordered]@{
    Git          = Try-Native { git --version }
    GitLfs       = Try-Native { git lfs version }
    UserName     = Try-Native { git config --global user.name }
    UserEmail    = Try-Native { git config --global user.email }
    Autocrlf     = Try-Native { git config --global core.autocrlf }
    CredentialHelper = Try-Native { git config --global credential.helper }
    GlobalIgnore = Try-Native { git config --global core.excludesfile }
}

# -------------------------------------------------------------------- runtimes
# Note: no '??' here - that operator is PowerShell 7+ and this must run on 5.1.
$py = Try-Native { python --version }
if (-not $py) { $py = Try-Native { py --version } }

# 'dotnet' being on PATH does not mean there is an SDK. dotnet.exe ships with runtimes
# only, and `dotnet --version` then fails outright. Distinguish the two, because a
# deploy that needs to build something cares a great deal.
$dotnetExe = Get-Command dotnet -ErrorAction SilentlyContinue
$sdkList   = if ($dotnetExe) { Try-Native { dotnet --list-sdks } } else { $null }
$dotnetStr = if (-not $dotnetExe) { 'not installed' }
             elseif ($sdkList) { "SDK: " + ((($sdkList -split "`r?`n") | Where-Object { $_ } | ForEach-Object { ($_ -split ' ')[0] }) -join ', ') }
             else { 'present, but NO SDK (runtimes only)' }

$p.Runtimes = [ordered]@{
    Node   = Try-Native { node --version }
    Npx    = Try-Native { npx --version }
    Python = $py
    Dotnet = $dotnetStr
    Cmake  = Try-Native { cmake --version }
}

# ------------------------------------------------------- agent (Codex) state
$codexHome = "$env:USERPROFILE\.codex"
$agentsFile = Join-Path $codexHome 'AGENTS.md'
$cfgFile = Join-Path $codexHome 'config.toml'
$p.Agent = [ordered]@{
    CodexHome        = if (Test-Path $codexHome) { $codexHome } else { 'not found' }
    GlobalAgentsMd   = if (Test-Path $agentsFile) { "$((Get-Item $agentsFile).Length) bytes" } else { 'MISSING' }
    ConfigToml       = if (Test-Path $cfgFile) { "$((Get-Item $cfgFile).Length) bytes" } else { 'MISSING' }
    McpServersDeclared = if (Test-Path $cfgFile) { @(Select-String -Path $cfgFile -Pattern '^\[mcp_servers\.([^.]+)\]\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value }) } else { @() }
    SkillsDir        = if (Test-Path "$env:USERPROFILE\.agents\skills") { @(Get-ChildItem "$env:USERPROFILE\.agents\skills" -Directory | ForEach-Object { $_.Name }) } else { @() }
}

# ------------------------------------------------------------- creative tools
# Only the ones that change the version-control setup are worth listing.
$toolChecks = [ordered]@{
    'Unity Hub'      = @("$env:ProgramFiles\Unity\Unity Hub\Unity Hub.exe")
    'Unity Editor'   = @(Get-ChildItem "$env:ProgramFiles\Unity\Hub\Editor" -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    'Unity CLI'      = @("$env:LOCALAPPDATA\Unity\bin\unity.exe")
    'Unreal Engine'  = @("$env:ProgramFiles\Epic Games")
    'Godot'          = @("$env:ProgramFiles\Godot", "$env:LOCALAPPDATA\Programs\Godot")
    'Blender'        = @("$env:ProgramFiles\Blender Foundation")
    'GZDoom'         = @("$env:ProgramFiles\GZDoom\gzdoom.exe")
    'Ultimate Doom Builder' = @("$env:ProgramFiles\Ultimate Doom Builder\Builder.exe")
    'SLADE'          = @("$env:ProgramFiles\SLADE\SLADE.exe")
    'Aseprite'       = @("$env:ProgramFiles\Aseprite", "$env:ProgramFiles\Steam\steamapps\common\Aseprite")
    'Krita'          = @("$env:ProgramFiles\Krita (x64)", "$env:ProgramFiles\Krita")
    'Adobe Photoshop'= @("$env:ProgramFiles\Adobe")
    'Audacity'       = @("$env:ProgramFiles\Audacity")
    'Reaper'         = @("$env:ProgramFiles\REAPER")
    'Visual Studio'  = @("$env:ProgramFiles\Microsoft Visual Studio")
    'VS Code'        = @("$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe")
}
$found = [ordered]@{}
foreach ($k in $toolChecks.Keys) {
    $hit = @($toolChecks[$k] | Where-Object { $_ -and (Test-Path $_) })
    if ($hit.Count -gt 0) { $found[$k] = ($hit | ForEach-Object { Split-Path $_ -Leaf }) -join ', ' }
}
$p.CreativeTools = $found

# --------------------------------------------------------------- cloud sync
# This section exists because "my files are in OneDrive" and "my Desktop is in
# OneDrive" are very different statements, and only the second one protects anything.
$usf = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$desktop = (Get-ItemProperty $usf -Name 'Desktop' -ErrorAction SilentlyContinue).Desktop
$docs    = (Get-ItemProperty $usf -Name 'Personal' -ErrorAction SilentlyContinue).Personal
$odAcct  = Get-ItemProperty 'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal' -ErrorAction SilentlyContinue
$odProc  = @(Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue)
$p.CloudSync = [ordered]@{
    OneDriveFolder      = $env:OneDrive
    OneDriveRunning     = ($odProc.Count -gt 0)
    OneDriveAccount     = if ($odAcct) { $odAcct.UserEmail } else { '' }
    KnownFolderMove     = if ($odAcct -and $odAcct.KfmFoldersConfiguredValues) { $odAcct.KfmFoldersConfiguredValues } else { 'NOT ENABLED' }
    DesktopPath         = $desktop
    DesktopInOneDrive   = ($desktop -like "*OneDrive*")
    DocumentsPath       = $docs
    DocumentsInOneDrive = ($docs -like "*OneDrive*")
    DropboxRunning      = (@(Get-Process -Name 'Dropbox' -ErrorAction SilentlyContinue).Count -gt 0)
    GoogleDriveRunning  = (@(Get-Process -Name 'GoogleDriveFS' -ErrorAction SilentlyContinue).Count -gt 0)
}

# ------------------------------------------------------------------- ports
function Get-ReservedTcpRanges {
    $ranges = @()
    foreach ($line in (& netsh interface ipv4 show excludedportrange protocol=tcp 2>&1)) {
        if ($line -match '^\s*(\d+)\s+(\d+)(\s+\*)?\s*$') { $ranges += [pscustomobject]@{ Start = [int]$Matches[1]; End = [int]$Matches[2] } }
    }
    return $ranges
}
$reserved = Get-ReservedTcpRanges
$portReport = @()
foreach ($port in 3000, 3022, 2222, 8080) {
    $blocked = $reserved | Where-Object { $port -ge $_.Start -and $port -le $_.End } | Select-Object -First 1
    $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    $owner = if ($inUse) { (Get-Process -Id $inUse[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName } else { '' }
    $portReport += [ordered]@{
        Port     = $port
        Status   = if ($blocked) { "RESERVED by Windows ($($blocked.Start)-$($blocked.End))" } elseif ($owner) { "in use by $owner" } else { 'free' }
    }
}
$p.Ports = [ordered]@{
    ReservedRanges = ($reserved | ForEach-Object { "$($_.Start)-$($_.End)" }) -join ', '
    Candidates     = $portReport
}

# ---------------------------------------------------------- existing projects
if ($ScanProjects) {
    $repos = @()
    foreach ($root in $ScanRoots) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '.git' } |
            ForEach-Object { $repos += (Split-Path $_.FullName -Parent) }
    }
    # Folders that look like manual copies of a project - the habit this setup replaces.
    $copyish = @()
    foreach ($root in $ScanRoots) {
        if (-not (Test-Path $root)) { continue }
        $copyish += (Get-ChildItem $root -Directory -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)(-copy|-backup|-old|_old|-final|final\d*$|v\d+$|\d{4}-\d{2}-\d{2}|\(\d+\)$)' } |
            Select-Object -First 40 -ExpandProperty FullName)
    }
    $p.ExistingProjects = [ordered]@{
        GitReposFound       = @($repos | Sort-Object -Unique)
        PossibleManualCopies = @($copyish | Sort-Object -Unique)
    }
}

# ------------------------------------------------------------------- emit
if ($Format -eq 'json') {
    $json = $p | ConvertTo-Json -Depth 6
    if ($OutFile) { $json | Set-Content $OutFile -Encoding UTF8; "wrote $OutFile" } else { $json }
    return
}

$sb = [System.Text.StringBuilder]::new()
function Line($t) { [void]$sb.AppendLine($t) }
function KV($k, $v) {
    $val = if ($v -is [array]) { if ($v.Count) { $v -join '; ' } else { '(none)' } } else { "$v" }
    if ([string]::IsNullOrWhiteSpace($val)) { $val = '(not set)' }
    Line ("| {0} | {1} |" -f $k, $val)
}
function Section($name) { Line ''; Line "## $name"; Line ''; Line '| | |'; Line '|---|---|' }

Line '# Machine profile'
Line ''
Line "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')  (read-only; nothing was changed)"

Section 'Host'
foreach ($k in $p.Host.Keys) { KV $k $p.Host[$k] }

Section 'Disks'
foreach ($d in $p.Drives) { KV "$($d.Drive) free" "$($d.FreeGB) GB of $([math]::Round($d.FreeGB + $d.UsedGB,1)) GB" }

Section 'Virtualisation'
foreach ($k in $p.Virtualisation.Keys) { KV $k $p.Virtualisation[$k] }

Section 'Containers'
foreach ($k in $p.Containers.Keys) { KV $k $p.Containers[$k] }

Section 'Version control'
foreach ($k in $p.VersionControl.Keys) { KV $k $p.VersionControl[$k] }

Section 'Runtimes'
foreach ($k in $p.Runtimes.Keys) { KV $k $p.Runtimes[$k] }

Section 'Agent (Codex)'
foreach ($k in $p.Agent.Keys) { KV $k $p.Agent[$k] }

Section 'Creative tools found'
if ($p.CreativeTools.Count -eq 0) { KV '(none detected)' '' }
else { foreach ($k in $p.CreativeTools.Keys) { KV $k $p.CreativeTools[$k] } }

Section 'Cloud sync'
foreach ($k in $p.CloudSync.Keys) { KV $k $p.CloudSync[$k] }

Section 'Ports'
KV 'Windows-reserved ranges' $p.Ports.ReservedRanges
foreach ($c in $p.Ports.Candidates) { KV "port $($c.Port)" $c.Status }

if ($ScanProjects) {
    Section 'Existing projects (scanned)'
    KV 'git repositories' $p.ExistingProjects.GitReposFound
    KV 'possible manual copies' $p.ExistingProjects.PossibleManualCopies
}

Line ''
Line '---'
Line ''
Line 'Next: `docs/interview.md` - the questions only the person can answer.'
Line 'Questions this output already answers must NOT be asked.'

$text = $sb.ToString()
if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, $text, [System.Text.UTF8Encoding]::new($false)); "wrote $OutFile" }
else { $text }
