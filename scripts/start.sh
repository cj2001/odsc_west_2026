#!/bin/bash
#
# Bring up the workshop stack safely.
#
# Prefer this over a bare `docker compose up -d`, because two things have to be
# true BEFORE the containers start:
#
#   1. ./notebooks and ./data must already exist. If a bind-mount source is
#      missing, Docker creates it as root, and the jupyter container (which runs
#      as your user, not root) then cannot write there - notebooks will not save
#      and pyvis .html output fails with "Permission denied".
#
#   2. HOST_UID/HOST_GID must be in .env. docker-compose.yml uses them for the
#      jupyter container's user. They are NOT called UID/GID on purpose: bash
#      sets UID but never exports it, and never sets GID at all, so compose
#      silently fell back to 1000:1000 for everyone.
#
set -u

SKIP_INIT=0
for arg in "$@"; do
    case "$arg" in
        --no-init) SKIP_INIT=1 ;;
        -h|--help)
            echo "Usage: ./scripts/start.sh [--no-init]"
            echo ""
            echo "  --no-init   Bring the containers up but do not initialize the"
            echo "              Senzing database (run ./scripts/init_database.sh later)."
            exit 0
            ;;
        *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
    esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
cd "$PROJECT_ROOT" || exit 1

# docker compose (v2) or docker-compose (v1)
if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    echo "❌ Error: neither 'docker compose' nor 'docker-compose' is available."
    exit 1
fi

echo "============================================"
echo "Starting Workshop Stack"
echo "============================================"
echo "Project root: $PROJECT_ROOT"
echo ""

# --- 1. .env ---------------------------------------------------------------
# compose fails to start without it, because the jupyter service loads it.
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        cp .env.example .env
        echo "📄 Created .env from .env.example"
    else
        echo "❌ Error: no .env and no .env.example to copy from."
        exit 1
    fi
fi

# Set a key in .env, replacing any existing definition
set_env_key() {
    local key="$1" value="$2"
    if grep -qE "^[[:space:]]*${key}=" .env; then
        # in-place, portable across GNU/BSD sed
        sed -i.bak -E "s|^[[:space:]]*${key}=.*|${key}=${value}|" .env && rm -f .env.bak
    else
        printf '\n%s=%s\n' "$key" "$value" >> .env
    fi
}

HOST_UID=$(id -u)
HOST_GID=$(id -g)
set_env_key HOST_UID "$HOST_UID"
set_env_key HOST_GID "$HOST_GID"
echo "👤 Container user: HOST_UID=$HOST_UID HOST_GID=$HOST_GID (written to .env)"

# --- 2. bind-mount directories --------------------------------------------
# Create them before compose so Docker never creates them as root.
for d in notebooks data; do
    if [ ! -d "$d" ]; then
        mkdir -p "$d"
        echo "📁 Created missing bind-mount directory: $d"
    fi
done

# Repair anything already owned by another user (typically root, from an
# earlier run where Docker created the directory). No sudo needed - we borrow
# root from a throwaway container that has the directory mounted.
NEEDS_FIX=""
for d in notebooks data; do
    if [ ! -w "$d" ] || [ "$(stat -c '%u' "$d" 2>/dev/null)" != "$HOST_UID" ]; then
        NEEDS_FIX="$NEEDS_FIX $d"
    fi
done

if [ -n "$NEEDS_FIX" ]; then
    echo "🔧 Fixing ownership of:$NEEDS_FIX"
    for d in $NEEDS_FIX; do
        docker run --rm -v "$PROJECT_ROOT/$d:/fix" alpine \
            sh -c "chown -R ${HOST_UID}:${HOST_GID} /fix && chmod -R u+rwX,g+rwX /fix" \
            || { echo "❌ Could not fix ownership of $d"; exit 1; }
    done
    echo "   Done."
fi
echo ""

# --- 3. up ----------------------------------------------------------------
echo "Starting containers..."
if ! $DC up -d; then
    echo ""
    echo "❌ Failed to start containers. Check the errors above."
    exit 1
fi

echo ""
echo "Waiting for services to report healthy..."
for _ in $(seq 1 60); do
    UNHEALTHY=$(docker ps --filter name=erkg_ --format '{{.Names}} {{.Status}}' \
        | grep -c 'health: starting')
    [ "$UNHEALTHY" = "0" ] && break
    sleep 2
done

echo ""
docker ps --filter name=erkg_ --format '  {{.Names}}\t{{.Status}}'
echo ""

# --- 4. initialize the Senzing schema -------------------------------------
# Safe to run every time: it detects an already-initialized database and
# returns without doing anything. Pass --no-init to skip.
if [ "$SKIP_INIT" = "1" ]; then
    echo "Skipping database initialization (--no-init)."
    echo "Run it later with: ./scripts/init_database.sh"
else
    if ! "$SCRIPT_DIR/init_database.sh"; then
        echo "❌ Database initialization failed. The containers are up; fix the"
        echo "   error above and re-run: ./scripts/init_database.sh"
        exit 1
    fi
fi

echo "============================================"
echo "✅ READY"
echo "============================================"
echo "Open JupyterLab: http://localhost:18888"
echo ""
