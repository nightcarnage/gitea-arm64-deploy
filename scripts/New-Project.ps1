<#
.SYNOPSIS
    Put a folder under version control on the local Gitea, wired up for an AI agent.

.DESCRIPTION
    Takes a folder that is not yet a repository and makes it one:

      1. reads the server URL and token from .env / .gitea-token,
      2. initialises git if needed (adopts an existing folder, never wipes it),
      3. copies in the templates - AGENTS.md, .gitignore, .gitattributes, and the
         Save-Revision script - WITHOUT overwriting files that already exist,
      4. for -Kind unity, runs `unity vcs doctor --fix` so the ignore and LFS rules come
         from Unity itself rather than from a generic guess,
      5. creates the repository on the Gitea server,
      6. makes the first commit and pushes it as revision r1.

    Safe to re-run: existing files are left alone and an existing repo is reused.

.EXAMPLE
    .\scripts\New-Project.ps1 -Name MyGame -Kind unity

.EXAMPLE
    .\scripts\New-Project.ps1 -Name Website -Path D:\projects\website
#>
[CmdletBinding()]
param(
    # Project and repository name.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name,

    # Local folder. Defaults to <parent>\<Name>.
    [string]$Path,

    # Parent folder for new projects. Ignored when -Path is given.
    [string]$ParentDir = (Join-Path $env:USERPROFILE 'source\repos'),

    # generic | unity  - unity also runs `unity vcs doctor --fix`.
    [ValidateSet('generic', 'unity')]
    [string]$Kind = 'generic',

    # Repository owner on the server. Defaults to the admin user in .env.
    [string]$Owner,

    # API token. Defaults to the contents of .gitea-token.
    [string]$Token,

    [switch]$Public,

    # Name of the first revision tag.
    [string]$FirstTag = 'r1'
)

$ErrorActionPreference = 'Continue'

function Step($t) { Write-Host "`n== $t" -ForegroundColor Cyan }
function Good($t) { Write-Host "   OK   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "   WARN $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "   FAIL $t" -ForegroundColor Red }

$root = Split-Path -Parent $PSScriptRoot

# ---------------------------------------------------------------- server + credentials
Step 'Reading configuration'
$envFile   = Join-Path $root '.env'
$tokenFile = Join-Path $root '.gitea-token'
$httpPort  = 3000

if (Test-Path $envFile) {
    foreach ($line in (Get-Content $envFile)) {
        if ($line -match '^\s*HTTP_PORT\s*=\s*(\d+)')          { $httpPort = [int]$Matches[1] }
        if ($line -match '^\s*GITEA_ADMIN_USER\s*=\s*(.+)$')   { if (-not $Owner) { $Owner = $Matches[1].Trim() } }
    }
}
if (-not $Owner) { $Owner = 'gitadmin' }
if (-not $Token -and (Test-Path $tokenFile)) { $Token = (Get-Content $tokenFile -Raw).Trim() }

$serverUrl = "http://localhost:$httpPort"
if (-not $Token) {
    Bad "No API token found."
    Bad "Run scripts\Deploy-Gitea.ps1 first, or pass -Token."
    exit 1
}
Good "server $serverUrl, owner '$Owner'"

# Confirm the server is actually up before creating folders.
try {
    $null = Invoke-RestMethod -Uri "$serverUrl/api/v1/version" -TimeoutSec 8 -ErrorAction Stop
} catch {
    Bad "No answer from $serverUrl - is Gitea running?"
    Bad "Start it with: docker compose up -d"
    exit 1
}

# ------------------------------------------------------------------------ local folder
Step 'Local project'
if (-not $Path) { $Path = Join-Path $ParentDir $Name }
$exists = Test-Path $Path
if (-not $exists) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Good "created $Path"
} else {
    $items = @(Get-ChildItem $Path -Force | Where-Object { $_.Name -ne '.git' })
    Good "using existing folder $Path ($($items.Count) item(s))"
}
$Path = (Resolve-Path $Path).Path

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Bad 'git is not on PATH.'; exit 1 }

Push-Location $Path
try {
    # ------------------------------------------------------------------- git init
    if (-not (Test-Path (Join-Path $Path '.git'))) {
        git init -b main 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { git init 2>&1 | Out-Null; git checkout -b main 2>&1 | Out-Null }
        Good 'initialised git (branch main)'
    } else {
        Good 'already a git repository'
    }

    # Identity must exist or the first commit fails on a clean machine.
    if (-not (git config user.name))  { git config user.name  $Owner }
    if (-not (git config user.email)) { git config user.email "$Owner@localhost.local" }

    git lfs install --local 2>$null | Out-Null

    # --------------------------------------------------------------- templates
    # Never overwrite: this script is safe on a folder that already has a project.
    $tpl = Join-Path $root 'templates'
    $copied = @()
    $skipped = @()

    $fileMap = @{
        'gitignore.default'    = '.gitignore'
        'gitattributes.default' = '.gitattributes'
        'AGENTS.md'            = 'AGENTS.md'
    }
    foreach ($src in $fileMap.Keys) {
        $dest = Join-Path $Path $fileMap[$src]
        if (Test-Path $dest) { $skipped += $fileMap[$src]; continue }
        Copy-Item (Join-Path $tpl $src) $dest -Force
        $copied += $fileMap[$src]
    }

    New-Item -ItemType Directory -Path (Join-Path $Path 'scripts') -Force | Out-Null
    foreach ($f in 'Save-Revision.ps1', 'Save-Revision.bat') {
        $dest = Join-Path $Path "scripts\$f"
        if (Test-Path $dest) { $skipped += "scripts\$f"; continue }
        Copy-Item (Join-Path $tpl $f) $dest -Force
        $copied += "scripts\$f"
    }

    if ($copied)  { Good "added: $($copied -join ', ')" }
    if ($skipped) { Warn "left alone (already present): $($skipped -join ', ')" }

    # Fill the placeholders in the AGENTS.md template.
    #
    # Only rewrite when a placeholder is actually still present, and write with
    # [System.IO.File]::WriteAllText rather than Set-Content. Set-Content appends a
    # trailing newline on every call, so each re-run grew the file by one blank line -
    # which made every re-run of this script produce a spurious commit.
    $agents = Join-Path $Path 'AGENTS.md'
    if (Test-Path $agents) {
        $text = [System.IO.File]::ReadAllText($agents)
        if ($text -match 'PROJECT_NAME|\{\{') {
            $cloneUrl = "$serverUrl/$Owner/$Name.git"
            $text = $text -replace 'PROJECT_NAME', $Name
            $text = $text -replace '\{\{SERVER_URL\}\}',   $serverUrl
            $text = $text -replace '\{\{REPO\}\}',         "$Owner/$Name"
            $text = $text -replace '\{\{LOCAL_PATH\}\}',   ($Path -replace '\\', '\\')
            $text = $text -replace '\{\{CLONE_URL\}\}',    $cloneUrl
            # UTF-8 without a BOM: exactly these bytes, nothing appended.
            [System.IO.File]::WriteAllText($agents, $text, [System.Text.UTF8Encoding]::new($false))
            Good 'filled in AGENTS.md'
        } else {
            Good 'AGENTS.md already filled in'
        }
    }

    # ------------------------------------------------------------------ unity kind
    if ($Kind -eq 'unity') {
        Step 'Unity repository hygiene'
        $unity = Join-Path $env:LOCALAPPDATA 'Unity\bin\unity.exe'
        $isUnityProject = Test-Path (Join-Path $Path 'ProjectSettings\ProjectVersion.txt')
        if (-not $isUnityProject) {
            Warn 'not a Unity project yet (no ProjectSettings\ProjectVersion.txt).'
            Warn 'For Unity: create the project in Unity Hub first, then run this with -Kind unity.'
        } elseif (Test-Path $unity) {
            # unity vcs doctor --fix is authoritative: it generates the ignore rules, LFS
            # patterns and merge-driver config from Unity's own knowledge.
            & $unity --no-pager --no-banner --color never --non-interactive vcs doctor --fix 2>&1 |
                ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
            if ($LASTEXITCODE -eq 0) { Good 'ran unity vcs doctor --fix' }
            else { Warn 'unity vcs doctor --fix did not complete; check its output above.' }

            & $unity --no-pager --no-banner --color never --non-interactive vcs merge-setup 2>&1 |
                Out-Null
            if ($LASTEXITCODE -eq 0) { Good 'wired UnityYAMLMerge for scene/prefab merges' }
        } else {
            Warn "unity CLI not found at $unity - skipping Unity hygiene."
        }
    }

    # ------------------------------------------------------------------ remote repo
    Step 'Server repository'
    # NOTE: the branch name is resolved later, after the first commit exists.
    # `git rev-parse --abbrev-ref HEAD` fails on a repository with no commits and
    # prints a scary "fatal: ambiguous argument 'HEAD'" - `git symbolic-ref` works on
    # an unborn branch and is used below instead.
    $existsOnServer = $true
    try { $null = Invoke-RestMethod -Uri "$serverUrl/api/v1/repos/$Owner/$Name" -Headers @{ Authorization = "token $Token" } -ErrorAction Stop }
    catch { $existsOnServer = $false }

    if ($existsOnServer) {
        Good "repository '$Owner/$Name' already exists - reusing it"
    } else {
        $body = @{ name = $Name; private = (-not $Public); auto_init = $false; default_branch = 'main' } | ConvertTo-Json
        try {
            $null = Invoke-RestMethod -Uri "$serverUrl/api/v1/user/repos" -Method Post `
                -Headers @{ Authorization = "token $Token" } -ContentType 'application/json' `
                -Body $body -ErrorAction Stop
            Good "created '$Owner/$Name'"
        } catch {
            Bad "could not create the repository: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) { Write-Host $_.ErrorDetails.Message -ForegroundColor DarkGray }
            exit 1
        }
    }

    # Remote, with the token embedded so pushes work without a credential prompt.
    $remoteUrl = "$serverUrl/$Owner/$Name.git"
    $authUrl   = $serverUrl -replace '^http://', "http://$Owner`:$Token@"
    $authUrl   = "$authUrl/$Owner/$Name.git"

    $current = (git remote get-url origin 2>$null)
    if ($current) { git remote set-url origin $authUrl }
    else          { git remote add origin $authUrl }
    Good "remote origin -> $remoteUrl"

    # ----------------------------------------------------------------- first commit
    Step 'First revision'
    git add -A 2>$null
    $staged = @(git diff --cached --name-only)
    if ($staged.Count -eq 0) {
        Warn 'nothing to commit yet - add some files, then run scripts\Save-Revision.ps1'
    } else {
        $branch = (git symbolic-ref --short HEAD 2>$null)
        if (-not $branch) { $branch = (git rev-parse --abbrev-ref HEAD 2>$null) }
        if (-not $branch) { $branch = 'main' }
        $branch = "$branch".Trim()
        git commit -m "$FirstTag - Initial commit" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            git tag -a $FirstTag -m "$FirstTag - Initial commit" 2>$null
            git push -u origin $branch --follow-tags 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
            if ($LASTEXITCODE -eq 0) { Good "pushed $FirstTag on branch $branch" }
            else { Warn 'commit made locally, but the push failed - check the output above' }
        } else {
            Warn 'commit failed - check the output above'
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " $Name is under version control" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host "  Local  : $Path"
Write-Host "  Web    : $serverUrl/$Owner/$Name"
Write-Host "  Clone  : $serverUrl/$Owner/$Name.git"
Write-Host ""
Write-Host "  Save a revision:  .\scripts\Save-Revision.bat" -ForegroundColor Cyan
Write-Host "  Or from the CLI:  .\scripts\Save-Revision.ps1 `"what changed`"" -ForegroundColor Cyan
Write-Host ""
