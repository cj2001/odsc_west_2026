#!/bin/bash

# Project root, so the licence and network are found no matter where this is
# run from (cwd is NOT used - running from scripts/ used to guess wrong)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Auto-detect the Docker network from the project directory name, which is how
# docker-compose prefixes it. Fall back to whatever *_erkg-network actually
# exists, so a renamed clone still works.
DIR_NAME=$(basename "$PROJECT_ROOT")
NETWORK_NAME="${DIR_NAME}_erkg-network"

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    FOUND=$(docker network ls --format '{{.Name}}' 2>/dev/null | grep -E '_erkg-network$' | head -n 1)
    if [ -n "$FOUND" ]; then
        echo "ℹ️  Network '$NETWORK_NAME' not found; using '$FOUND' instead."
        NETWORK_NAME="$FOUND"
    fi
fi

echo "============================================"
echo "Initializing Senzing Database"
echo "============================================"
echo "Directory: $DIR_NAME"
echo "Network: $NETWORK_NAME"
echo ""

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
#   3. $SENZING_LICENSE_FILE
#   4. $PROJECT_ROOT/g2.lic_base64
# ---------------------------------------------------------------------------

# Read a single key out of .env without sourcing the whole file
env_value() {
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$2" 2>/dev/null \
        | tail -n 1 \
        | tr -d '\r' \
        | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" -e 's/[[:space:]]*$//'
}

ENV_FILE="$PROJECT_ROOT/.env"
if [ -f "$ENV_FILE" ]; then
    [ -z "$SENZING_LICENSE_BASE64" ] && SENZING_LICENSE_BASE64=$(env_value SENZING_LICENSE_BASE64 "$ENV_FILE")
    [ -z "$SENZING_LICENSE_FILE" ]   && SENZING_LICENSE_FILE=$(env_value SENZING_LICENSE_FILE "$ENV_FILE")
fi

LICENSE_FILE="${SENZING_LICENSE_FILE:-$PROJECT_ROOT/g2.lic_base64}"
LICENSE_B64=$(printf '%s' "$SENZING_LICENSE_BASE64" | tr -d '[:space:]')
LICENSE_SOURCE="SENZING_LICENSE_BASE64"

if [ -z "$LICENSE_B64" ] && [ -f "$LICENSE_FILE" ]; then
    LICENSE_B64=$(tr -d '[:space:]' < "$LICENSE_FILE")
    LICENSE_SOURCE="$LICENSE_FILE"
fi

if [ -n "$LICENSE_B64" ]; then
    if ! printf '%s' "$LICENSE_B64" | base64 -d >/dev/null 2>&1; then
        echo "❌ Error: licence from $LICENSE_SOURCE is not valid base64!"
        echo ""
        echo "Expected the base64 licence string Senzing ships (g2.lic_base64),"
        echo "not the binary g2.lic file."
        echo ""
        exit 1
    fi
    echo "🔑 Licence: $LICENSE_SOURCE (${#LICENSE_B64} base64 chars)"
else
    echo "🔑 Licence: none found (looked for $LICENSE_FILE)"
    echo "   Senzing will run with the default 500-record limit."
fi
echo ""

# Build the engine configuration, adding the licence only when we have one.
# Base64 needs no JSON escaping.
PIPELINE_JSON='"CONFIGPATH":"/etc/opt/senzing","RESOURCEPATH":"/opt/senzing/er/resources","SUPPORTPATH":"/opt/senzing/data"'
if [ -n "$LICENSE_B64" ]; then
    PIPELINE_JSON="${PIPELINE_JSON},\"LICENSESTRINGBASE64\":\"${LICENSE_B64}\""
fi
SQL_JSON='"CONNECTION":"postgresql://postgres:workshop@postgres:5432:erkg?sslmode=disable"'

# Exported rather than passed as --env KEY=VALUE so the licence stays out of
# the process list; `docker run --env KEY` pulls it from this environment.
export SENZING_ENGINE_CONFIGURATION_JSON="{\"PIPELINE\":{${PIPELINE_JSON}},\"SQL\":{${SQL_JSON}}}"

# Check if network exists
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    echo "❌ Error: Network '$NETWORK_NAME' not found!"
    echo ""
    echo "Make sure containers are running:"
    echo "  docker-compose up -d"
    echo ""
    exit 1
fi

# Check if database is already initialized
echo "Checking if database is already initialized..."
CHECK_RESULT=$(docker run --rm --network "$NETWORK_NAME" postgres:15 psql "postgresql://postgres:workshop@postgres:5432/erkg" -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='sys_vars';" 2>/dev/null || echo "0")

if [ "$CHECK_RESULT" = "1" ]; then
    echo ""
    echo "============================================"
    echo "ℹ️  ALREADY INITIALIZED"
    echo "============================================"
    echo "Senzing database is already set up."
    echo "No action needed."
    echo ""
    echo "If you want to reset and start fresh:"
    echo "  docker-compose down -v"
    echo "  ./scripts/start.sh"
    echo ""
    exit 0
fi

# Run initialization
echo "Database not initialized. Running setup..."
echo ""

docker run --rm --network "$NETWORK_NAME" --env SENZING_ENGINE_CONFIGURATION_JSON senzing/init-database --install-senzing-er-configuration

# Check result
if [ $? -eq 0 ]; then
    echo ""
    echo "============================================"
    echo "✅ SUCCESS!"
    echo "============================================"
    echo "Senzing database initialized successfully."
    echo ""
    echo "Next steps:"
    echo "1. Open http://localhost:18888"
    echo "2. Run notebooks/00_test_setup.ipynb"
    echo ""
else
    echo ""
    echo "============================================"
    echo "❌ FAILED"
    echo "============================================"
    echo "Initialization failed. Check errors above."
    echo ""
    exit 1
fi
