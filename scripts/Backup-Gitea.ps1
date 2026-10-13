<#
.SYNOPSIS
    Back up Gitea to a folder of your choosing - including a OneDrive folder.

.DESCRIPTION
    Uses Gitea's own `gitea dump`, which is the correct way to back this up. It
    captures, in one archive:

      * data/gitea.db    the SQLite database (users, issues, settings, permissions)
      * repos/           every git repository, bare, with full history
      * data/lfs/        every Git LFS object
      * app.ini          the server configuration and secrets
      * gitea-db.sql     a plain SQL dump as well

    Why not just copy the database file - or the Docker volume?

      * A *live* SQLite file copied mid-write can be torn and will not open.
      * The Docker volume does not exist as a folder on Windows. It lives inside
        %LOCALAPPDATA%\Docker\wsl\disk\docker_data.vhdx, a multi-gigabyte virtual
        disk holding *all* of Docker's data - not just Gitea.
      * The database alone is worthless. It holds no code; the repositories hold
        the code, and they are not in it.

    The dump is taken by Gitea itself, which knows how to do it consistently, and
    the result is a single file that can be copied anywhere - including a OneDrive
    folder, where it will sync.

    Old backups are pruned so the folder does not grow without limit.

.EXAMPLE
    .\scripts\Backup-Gitea.ps1

.EXAMPLE
    .\scripts\Backup-Gitea.ps1 -Destination 'D:\Backups\Gitea' -Keep 30

.EXAMPLE
    # Verify the backup mechanism without keeping anything
    .\scripts\Backup-Gitea.ps1 -Destination "$env:TEMP\gitea-bk" -Keep 1
#>
[CmdletBinding()]
param(
    # Where to write the .zip. Defaults to a OneDrive folder when OneDrive is present,
    # otherwise <project>\backups.
    [string]$Destination,

    # How many backups to keep. Older ones are deleted.
    [int]$Keep = 14,

    # Folder containing compose.yaml. Defaults to the parent of this script's folder.
    [string]$ProjectDir,

    [string]$Service = 'gitea',

    # Skip the check for whether OneDrive is actually running.
    [switch]$SkipUploadCheck
)

# Native docker writes progress to stderr; under 'Stop' a redirected 2>&1 would abort.
$ErrorActionPreference = 'Continue'

function Step($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Good($t) { Write-Host "   OK   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "   WARN $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "   FAIL $t" -ForegroundColor Red }

$root = if ($ProjectDir) { $ProjectDir } else { Split-Path -Parent $PSScriptRoot }
$compose = Join-Path $root 'compose.yaml'
if (-not (Test-Path $compose)) { Bad "No compose.yaml at $compose"; exit 1 }

# ------------------------------------------------------------------ destination folder
Step 'Destination'
if (-not $Destination) {
    # OneDrive's sync root is the folder that actually uploads. A subfolder of it syncs too.
    if ($env:OneDrive -and (Test-Path $env:OneDrive)) {
        $Destination = Join-Path $env:OneDrive 'GiteaBackups'
    } else {
        $Destination = Join-Path $root 'backups'
    }
}
if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Good "created $Destination"
} else {
    Good "using $Destination"
}

# ------------------------------------------------------------- will it actually upload?
if (-not $SkipUploadCheck) {
    if ($Destination -like "*$env:OneDrive*" -and $env:OneDrive) {
        $od = Get-Process -Name 'OneDrive' -ErrorAction SilentlyContinue
        if (-not $od) {
            Warn 'OneDrive is installed but NOT RUNNING.'
            Warn 'The backup will be written, but it will NOT be uploaded until OneDrive runs.'
            Warn 'Start OneDrive from the Start menu and sign in.'
        } else {
            Good 'OneDrive is running, so the backup will upload'
        }
    } else {
        Warn "destination is not inside OneDrive ($env:OneDrive) - this backup stays on this PC only"
    }
}

# --------------------------------------------------------------------- container up?
Step 'Gitea'
$cid = (& docker compose -f $compose ps -q $Service 2>$null | Out-String).Trim()
if (-not $cid) {
    Bad "service '$Service' is not running."
    Bad "Start it with: docker compose up -d"
    exit 1
}
$running = (& docker inspect -f '{{.State.Running}}' $cid 2>$null | Out-String).Trim()
if ($running -ne 'true') { Bad "container $cid exists but is not running."; exit 1 }
Good "container running ($($cid.Substring(0,12)))"

# ------------------------------------------------------------------------- run the dump
Step 'Dumping'
$stamp    = Get-Date -Format 'yyyy-MM-dd_HHmmss'
$name     = "gitea-backup-$stamp.zip"
$inTheBox = "/data/gitea/$name"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
& docker compose -f $compose exec -T -u git $Service gitea dump -c /data/gitea/conf/app.ini -f $inTheBox 2>&1 |
    ForEach-Object { if ($_ -match 'Finish dumping') { Write-Host "   $_" -ForegroundColor DarkGray } }
$sw.Stop()
if ($LASTEXITCODE -ne 0) { Bad 'gitea dump failed. Is the service named correctly?'; exit 1 }
Good "dumped in $([math]::Round($sw.Elapsed.TotalSeconds,1))s"

# --------------------------------------------------------------------- copy it out
$tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) $name
& docker cp "${cid}:$inTheBox" $tmpZip 2>$null | Out-Null
if (-not (Test-Path $tmpZip)) { Bad 'could not copy the dump out of the container.'; exit 1 }

# Remove the in-container copy either way, so the volume does not accumulate dumps.
& docker compose -f $compose exec -T -u git $Service sh -c "rm -f '$inTheBox'" 2>$null | Out-Null

# ------------------------------------------------------------------ verify the contents
# A dump missing repos/ would be a database with no code in it - worse than useless,
# because it looks like a backup.
Step 'Verifying archive'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$hasDb = $false; $hasRepos = $false; $repoCount = 0; $hasLfs = $false; $hasConfig = $false
try {
    $z = [System.IO.Compression.ZipFile]::OpenRead($tmpZip)
    try {
        foreach ($e in $z.Entries) {
            $n = $e.FullName
            if ($n -eq 'data/gitea.db' -or $n -eq 'gitea-db.sql') { $hasDb = $true }
            if ($n -eq 'app.ini') { $hasConfig = $true }
            if ($n -like 'data/lfs/*') { $hasLfs = $true }
            if ($n -match '^repos/.+\.git/HEAD$') { $repoCount++ }
        }
        $hasRepos = $repoCount -gt 0
    } finally { $z.Dispose() }
} catch { Bad "archive is unreadable: $($_.Exception.Message)"; exit 1 }

if ($hasDb)      { Good 'database present' }        else { Bad 'database MISSING from the archive' }
if ($hasConfig)  { Good 'app.ini present' }         else { Warn 'app.ini not found (configuration only)' }
if ($hasRepos)   { Good "$repoCount repositories present" } else { Bad 'NO repositories in the archive - the code is not in this backup' }
if ($hasLfs)     { Good 'LFS objects present' }     else { Warn 'no LFS objects (fine if nothing large is stored)' }
if (-not ($hasDb -and $hasRepos)) { Bad 'refusing to keep an incomplete backup'; Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue; exit 1 }

# ------------------------------------------------------------------------------ store
$final = Join-Path $Destination $name
Move-Item $tmpZip $final -Force
$mb = [math]::Round((Get-Item $final).Length / 1MB, 2)
Good "wrote $final ($mb MB)"

# ------------------------------------------------------------------------------- prune
Step 'Retention'
$old = Get-ChildItem $Destination -Filter 'gitea-backup-*.zip' -File |
       Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep
if ($old) {
    foreach ($f in $old) { Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue }
    Good "removed $($old.Count) backup(s) older than the newest $Keep"
} else {
    Good "nothing to prune (keeping the newest $Keep)"
}
$all = @(Get-ChildItem $Destination -Filter 'gitea-backup-*.zip' -File | Sort-Object LastWriteTime -Descending)
Write-Host "   $($all.Count) backup(s) held, newest: $($all[0].Name)"

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " Backup complete" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host "  File      : $final"
Write-Host "  Size      : $mb MB"
Write-Host "  Contains  : database, $repoCount repositories, LFS objects, configuration"
Write-Host "  On OneDrive: $(if ($Destination -like "*$env:OneDrive*") { 'yes - will upload when OneDrive runs' } else { 'no - local only' })"
Write-Host ""
Write-Host "  Restore: see docs\backup-and-restore.md" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Schedule it daily (run once, as the current user):" -ForegroundColor Cyan
Write-Host "    `$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"'" -ForegroundColor DarkGray
Write-Host "    Register-ScheduledTask -TaskName 'Gitea backup' -Action `$a -Trigger (New-ScheduledTaskTrigger -Daily -At 18:00)" -ForegroundColor DarkGray
Write-Host ""
