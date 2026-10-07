# Initialize the Senzing database.
#
# Windows counterpart of init_database.sh - keep the two in sync.

# Project root, so the licence and network are found no matter where this is
# run from (the current directory is NOT used - running from scripts\ used to
# guess the wrong network name)
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Auto-detect the Docker network from the project directory name, which is how
# docker-compose prefixes it. Fall back to whatever *_erkg-network actually
# exists, so a renamed clone still works.
$DirName = Split-Path -Leaf $ProjectRoot
$NetworkName = "${DirName}_erkg-network"

docker network inspect $NetworkName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    $found = docker network ls --format '{{.Name}}' 2>$null |
             Where-Object { $_ -match '_erkg-network$' } |
             Select-Object -First 1
    if ($found) {
        Write-Host "Network '$NetworkName' not found; using '$found' instead."
        $NetworkName = $found
    }
}

Write-Host "============================================"
Write-Host "Initializing Senzing Database"
Write-Host "============================================"
Write-Host "Directory: $DirName"
Write-Host "Network: $NetworkName"
Write-Host ""

# ---------------------------------------------------------------------------
# Senzing licence
#
# Without a licence Senzing accepts 500 records. The licence is a base64 string
# that goes into the engine configuration as PIPELINE.LICENSESTRINGBASE64. It
# may be wrapped across several lines in the file; the engine wants one line, so
# all whitespace is stripped below.
#
# Precedence:
#   1. SENZING_LICENSE_BASE64 from the environment
#   2. SENZING_LICENSE_BASE64 / SENZING_LICENSE_FILE from .env
#   3. $env:SENZING_LICENSE_FILE
#   4. <project root>\g2.lic_base64
# ---------------------------------------------------------------------------

# Read a single key out of .env without sourcing the whole file
function Get-EnvValue {
    param([string]$Key, [string]$Path)
    if (-not (Test-Path $Path)) { return "" }
    $match = Select-String -Path $Path -Pattern "^\s*$Key\s*=\s*(.*)$" |
             Select-Object -Last 1
    if (-not $match) { return "" }
    $value = $match.Matches[0].Groups[1].Value.Trim()
    return $value.Trim('"').Trim("'")
}

$licenseB64 = $env:SENZING_LICENSE_BASE64
$licenseFile = $env:SENZING_LICENSE_FILE
$envFile = Join-Path $ProjectRoot ".env"

if (Test-Path $envFile) {
    if ([string]::IsNullOrWhiteSpace($licenseB64)) {
        $licenseB64 = Get-EnvValue -Key "SENZING_LICENSE_BASE64" -Path $envFile
    }
    if ([string]::IsNullOrWhiteSpace($licenseFile)) {
        $licenseFile = Get-EnvValue -Key "SENZING_LICENSE_FILE" -Path $envFile
    }
}

if ([string]::IsNullOrWhiteSpace($licenseFile)) {
    $licenseFile = Join-Path $ProjectRoot "g2.lic_base64"
}

$licenseB64 = ($licenseB64 -replace '\s', '')
$licenseSource = "SENZING_LICENSE_BASE64"

if ([string]::IsNullOrWhiteSpace($licenseB64) -and (Test-Path $licenseFile)) {
    $licenseB64 = ((Get-Content $licenseFile -Raw) -replace '\s', '')
    $licenseSource = $licenseFile
}

if (-not [string]::IsNullOrWhiteSpace($licenseB64)) {
    try {
        [void][Convert]::FromBase64String($licenseB64)
    } catch {
        Write-Host "Error: licence from $licenseSource is not valid base64!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Expected the base64 licence string Senzing ships (g2.lic_base64),"
        Write-Host "not the binary g2.lic file."
        Write-Host ""
        exit 1
    }
    Write-Host "Licence: $licenseSource ($($licenseB64.Length) base64 chars)"
} else {
    $licenseB64 = ""
    Write-Host "Licence: none found (looked for $licenseFile)"
    Write-Host "         Senzing will run with the default 500-record limit."
}
Write-Host ""

# Build the engine configuration, adding the licence only when we have one.
# Base64 needs no JSON escaping.
$pipelineJson = '"CONFIGPATH":"/etc/opt/senzing","RESOURCEPATH":"/opt/senzing/er/resources","SUPPORTPATH":"/opt/senzing/data"'
if (-not [string]::IsNullOrWhiteSpace($licenseB64)) {
    $pipelineJson = $pipelineJson + ',"LICENSESTRINGBASE64":"' + $licenseB64 + '"'
}
$sqlJson = '"CONNECTION":"postgresql://postgres:workshop@postgres:5432:erkg?sslmode=disable"'

# Set in this process's environment rather than passed as --env KEY=VALUE, so
# the licence stays off the command line; `docker run --env KEY` picks it up.
$env:SENZING_ENGINE_CONFIGURATION_JSON = '{"PIPELINE":{' + $pipelineJson + '},"SQL":{' + $sqlJson + '}}'

# Check if the network exists (after the fallback above, this is fatal)
docker network inspect $NetworkName 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Network '$NetworkName' not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Make sure containers are running:"
    Write-Host "  .\scripts\start.ps1"
    Write-Host ""
    exit 1
}

# Check if database is already initialized
Write-Host "Checking if database is already initialized..."
$checkResult = docker run --rm --network $NetworkName postgres:15 psql "postgresql://postgres:workshop@postgres:5432/erkg" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='sys_vars';" 2>$null
if ($LASTEXITCODE -ne 0) { $checkResult = "0" }

if ("$checkResult".Trim() -eq "1") {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "ALREADY INITIALIZED"
    Write-Host "============================================"
    Write-Host "Senzing database is already set up."
    Write-Host "No action needed."
    Write-Host ""
    Write-Host "If you want to reset and start fresh:"
    Write-Host "  docker-compose down -v"
    Write-Host "  .\scripts\start.ps1"
    Write-Host ""
    exit 0
}

# Run initialization
Write-Host "Database not initialized. Running setup..."
Write-Host ""

docker run --rm --network $NetworkName --env SENZING_ENGINE_CONFIGURATION_JSON senzing/init-database --install-senzing-er-configuration

# Check result
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "SUCCESS!" -ForegroundColor Green
    Write-Host "============================================"
    Write-Host "Senzing database initialized successfully."
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Open http://localhost:18888"
    Write-Host "2. Run notebooks/00_test_setup.ipynb"
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "============================================"
    Write-Host "FAILED" -ForegroundColor Red
    Write-Host "============================================"
    Write-Host "Initialization failed. Check errors above."
    Write-Host ""
    exit 1
}
