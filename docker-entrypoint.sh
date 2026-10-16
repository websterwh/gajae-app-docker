#!/usr/bin/env bash
set -e

# Default environment configurations
export HOST="${HOST:-0.0.0.0}"
export SERVER_PORT="${SERVER_PORT:-3001}"
export GAJAE_ALLOW_UNAUTH_REMOTE="${GAJAE_ALLOW_UNAUTH_REMOTE:-1}"
export ALLOWED_HOSTS="${ALLOWED_HOSTS:-*}"
export DATABASE_PATH="${DATABASE_PATH:-/data/auth.db}"
export WORKSPACES_ROOT="${WORKSPACES_ROOT:-/workspace}"
export GJC_WORKER_AGENT_DIR="${GJC_WORKER_AGENT_DIR:-/root/.gjc/agent}"
export AUTO_UPDATE="${AUTO_UPDATE:-true}"
export UPDATE_INTERVAL="${UPDATE_INTERVAL:-0}"
export UPSTREAM_REPO="${UPSTREAM_REPO:-devswha/gajae-code-app}"
export VERSION="${VERSION:-latest}"

# Ensure required directories exist
mkdir -p "${DATABASE_PATH%/*}" "${WORKSPACES_ROOT}" "${GJC_WORKER_AGENT_DIR}" /data/logs /app

# Initial installation or startup update check
if [ ! -f "/app/dist-server/server/cli.js" ]; then
    echo "==> [First Run] Gajae Code App not installed. Downloading ${VERSION} from ${UPSTREAM_REPO}..."
    /usr/local/bin/install-release "${UPSTREAM_REPO}" "${VERSION}" /app
elif [ "${AUTO_UPDATE}" = "true" ] || [ "${AUTO_UPDATE}" = "1" ]; then
    echo "==> [Auto-Update] Checking for updates on startup..."
    /usr/local/bin/install-release "${UPSTREAM_REPO}" "${VERSION}" /app || true
fi

# Ensure bun is in PATH if present in dist-native
if [ -f "/app/dist-native/bun" ] && [ ! -f "/usr/local/bin/bun" ]; then
    ln -sf /app/dist-native/bun /usr/local/bin/bun
    chmod +x /usr/local/bin/bun 2>/dev/null || true
fi

echo "=========================================================="
echo " Starting Gajae Code App Container"
echo " Version        : $(cat /app/.installed_version 2>/dev/null || echo 'unknown')"
echo " Bind Address   : ${HOST}:${SERVER_PORT}"
echo " Allowed Hosts  : ${ALLOWED_HOSTS}"
echo " Unauth Remote  : ${GAJAE_ALLOW_UNAUTH_REMOTE}"
echo " Database Path  : ${DATABASE_PATH}"
echo " Workspace Root : ${WORKSPACES_ROOT}"
echo " Auto Update    : ${AUTO_UPDATE} (Interval: ${UPDATE_INTERVAL}s)"
echo "=========================================================="

# If running a non-server command (e.g. bash, status, info)
if [ "$#" -gt 0 ] && [ "$1" != "start" ]; then
    if [ "$1" = "status" ] || [ "$1" = "info" ] || [ "$1" = "version" ]; then
        exec node /app/dist-server/server/cli.js "$@"
    else
        exec "$@"
    fi
fi

# In-container server supervisor with optional periodic update checker
SERVER_PID=""

shutdown_handler() {
    echo "==> Shutting down Gajae Code App..."
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    exit 0
}

trap shutdown_handler SIGTERM SIGINT SIGQUIT

# Periodic background update loop if UPDATE_INTERVAL > 0
if [ "${AUTO_UPDATE}" = "true" ] || [ "${AUTO_UPDATE}" = "1" ]; then
    if [ "${UPDATE_INTERVAL}" -gt 0 ] 2>/dev/null; then
        echo "==> [Auto-Update] Periodic update check enabled (every ${UPDATE_INTERVAL}s)."
        (
            while true; do
                sleep "${UPDATE_INTERVAL}"
                echo "==> [Auto-Update] Running scheduled update check..."
                OLD_VER="$(cat /app/.installed_version 2>/dev/null || true)"
                /usr/local/bin/install-release "${UPSTREAM_REPO}" "${VERSION}" /app || true
                NEW_VER="$(cat /app/.installed_version 2>/dev/null || true)"
                
                if [ -n "$NEW_VER" ] && [ "$NEW_VER" != "$OLD_VER" ]; then
                    echo "==> [Auto-Update] Update detected (${OLD_VER} -> ${NEW_VER}). Restarting server process..."
                    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
                        kill -TERM "$SERVER_PID" 2>/dev/null || true
                    fi
                fi
            done
        ) &
    fi
fi

# Supervisor loop
while true; do
    node /app/dist-server/server/cli.js start &
    SERVER_PID=$!
    wait "$SERVER_PID" || true
    
    sleep 1
done
