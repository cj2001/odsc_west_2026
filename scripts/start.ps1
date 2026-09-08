# Bring up the workshop stack safely.
#
# Windows counterpart of start.sh - keep the two in sync.
#
# Prefer this over a bare `docker compose up -d`, because two things have to be
# true BEFORE the containers start:
#
#   1. .\notebooks and .\data must already exist. If a bind-mount source is
#      missing, Docker creates it itself, and on Linux/macOS it does so as root,
#      which leaves the jupyter container unable to write there. Creating them
#      up front avoids the whole class of problem on every platform.
#
#   2. HOST_UID/HOST_GID must be in .env. docker-compose.yml uses them for the
#      jupyter container's user. They are NOT called UID/GID on purpose: in bash
#      UID is never exported and GID is never set at all, so compose silently
#      fell back to 1000:1000 for everyone.

param(
    [switch]$NoInit,
    [switch]$Help
)

if ($Help) {
    Write-Host "Usage: .\scripts\start.ps1 [-NoInit]"
    Write-Host ""
    Write-Host "  -NoInit   Bring the containers up but do not initialize the"
    Write-Host "            Senzing database (run .\scripts\init_database.ps1 later)."
    exit 0
}

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

# docker compose (v2) or docker-compose (v1)
docker compose version 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $DcArgs = @("compose")
} elseif (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    $DcArgs = @()
} else {
    Write-Host "Error: neither 'docker compose' nor 'docker-compose' is available." -ForegroundColor Red
    exit 1
}

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    if ($DcArgs.Count -gt 0) {
        & docker @DcArgs @ComposeArgs
    } else {
        & docker-compose @ComposeArgs
    }
}

Write-Host "============================================"
Write-Host "Starting Workshop Stack"
Write-Host "============================================"
Write-Host "Project root: $ProjectRoot"
Write-Host ""

# --- 1. .env ---------------------------------------------------------------
# compose fails to start without it, because the jupyter service loads it.
if (-not (Test-Path ".env")) {
    if (Test-Path ".env.example") {
        Copy-Item ".env.example" ".env"
        Write-Host "Created .env from .env.example"
    } else {
        Write-Host "Error: no .env and no .env.example to copy from." -ForegroundColor Red
        exit 1
    }
}

# Set a key in .env, replacing any existing definition
function Set-EnvKey {
    param([string]$Key, [string]$Value)
    $lines = @(Get-Content ".env")
    $pattern = "^\s*$Key\s*="
    if ($lines -match $pattern) {
        $lines = $lines | ForEach-Object {
            if ($_ -match $pattern) { "$Key=$Value" } else { $_ }
        }
        Set-Content ".env" -Value $lines
    } else {
        Add-Content ".env" -Value "`n$Key=$Value"
    }
}

# Windows has no POSIX uid, and Docker Desktop maps bind-mount permissions
# through its VM, so the image default of 1000 is correct here. These keys still
# have to be present, because compose reads them for the jupyter user.
$HostUid = 1000
$HostGid = 1000
Set-EnvKey -Key "HOST_UID" -Value $HostUid
Set-EnvKey -Key "HOST_GID" -Value $HostGid
Write-Host "Container user: HOST_UID=$HostUid HOST_GID=$HostGid (written to .env)"

# --- 2. bind-mount directories --------------------------------------------
# Create them before compose so Docker never creates them itself.
foreach ($d in @("notebooks", "data")) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host "Created missing bind-mount directory: $d"
    }
}
Write-Host ""

# --- 3. up ----------------------------------------------------------------
Write-Host "Starting containers..."
Invoke-Compose @("up", "-d")
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Failed to start containers. Check the errors above." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Waiting for services to report healthy..."
for ($i = 0; $i -lt 60; $i++) {
    $starting = docker ps --filter name=erkg_ --format '{{.Status}}' 2>$null |
                Where-Object { $_ -match 'health: starting' }
    if (-not $starting) { break }
    Start-Sleep -Seconds 2
}

Write-Host ""
docker ps --filter name=erkg_ --format '  {{.Names}}`t{{.Status}}'
Write-Host ""

# --- 4. initialize the Senzing schema -------------------------------------
# Safe to run every time: it detects an already-initialized database and
# returns without doing anything. Pass -NoInit to skip.
if ($NoInit) {
    Write-Host "Skipping database initialization (-NoInit)."
    Write-Host "Run it later with: .\scripts\init_database.ps1"
} else {
    & (Join-Path $PSScriptRoot "init_database.ps1")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Database initialization failed. The containers are up; fix the" -ForegroundColor Red
        Write-Host "error above and re-run: .\scripts\init_database.ps1"
        exit 1
    }
}

Write-Host "============================================"
Write-Host "READY" -ForegroundColor Green
Write-Host "============================================"
Write-Host "Open JupyterLab: http://localhost:18888"
Write-Host ""
