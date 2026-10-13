<#
.SYNOPSIS
    Saves a revision: commit, tag as r<N>, and push.

.DESCRIPTION
    Exists so nobody has to remember Git commands.

      1. stages every change in this project,
      2. commits it,
      3. tags it as the next revision number (r1, r2, r3, ...),
      4. pushes it to the server.

    Safe to run with nothing to save - it says so and does nothing.

    A commit only captures what is on disk. If an editor (Unity, an IDE) is open with
    unsaved changes, save first or those changes will not be included.

.EXAMPLE
    .\scripts\Save-Revision.ps1 "fixed the lighting on level 2"

.NOTES
    Double-click scripts\Save-Revision.bat for the same thing without a terminal.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Message = ""
)

# 'Continue' rather than 'Stop': native git writes ordinary warnings to stderr, and under
# 'Stop' a redirected 2>&1 turns those into a terminating error. Every git call is checked
# via $LASTEXITCODE instead.
$ErrorActionPreference = "Continue"

function Info($t) { Write-Host $t -ForegroundColor Cyan }
function Good($t) { Write-Host $t -ForegroundColor Green }
function Warn($t) { Write-Host $t -ForegroundColor Yellow }
function Bad($t)  { Write-Host $t -ForegroundColor Red }

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

if (-not (Test-Path (Join-Path $repoRoot ".git"))) {
    Bad "This folder is not a Git project, so there is nothing to save:"
    Bad "  $repoRoot"
    exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Bad "Git is not installed, or it is not on your PATH."
    exit 1
}

# Switch the Git LFS filters on in this clone. Harmless if already on.
git lfs install --local 2>$null | Out-Null

Info "Checking for changes..."
git add -A

$staged = @(git diff --cached --name-only)
if ($staged.Count -eq 0) {
    Warn "Nothing has changed since the last revision, so there is nothing to save."
    exit 0
}

# Work out the next revision number from the tags that already exist.
$used = @()
foreach ($t in (git tag --list "r*")) {
    if ($t -match "^r(\d+)$") { $used += [int]$Matches[1] }
}
$next = if ($used.Count -gt 0) { ($used | Measure-Object -Maximum).Maximum + 1 } else { 1 }
$tag  = "r$next"

if ([string]::IsNullOrWhiteSpace($Message)) { $Message = "Revision $next" }
$fullMessage = "$tag - $Message"

Info "Saving revision $tag ..."
$shortstat = (git diff --cached --shortstat | Out-String).Trim()

git commit -m $fullMessage | Out-Null
if ($LASTEXITCODE -ne 0) {
    Bad "The save failed while committing. Nothing was lost - run it again."
    exit 1
}

git tag -a $tag -m $fullMessage
if ($LASTEXITCODE -ne 0) {
    Bad "Saved the commit, but could not label it as revision $tag."
    exit 1
}

Info "Uploading to the server..."
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
$remote = (git remote get-url origin 2>$null)

if (-not $remote) {
    Warn "No server is configured for this project, so it was only saved on this PC."
    exit 2
}

git push origin $branch --follow-tags
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Warn "Revision $tag is saved on THIS PC, but the upload failed."
    Warn "That usually means the Gitea server is not running."
    Warn "Start Docker Desktop, wait for 'Engine running', then run this again."
    exit 2
}

Write-Host ""
Good "Revision $tag saved and backed up."
if ($shortstat) { Write-Host "  $shortstat" }
Write-Host "  Server : $remote"
Write-Host "  Branch : $branch"
Write-Host ""
