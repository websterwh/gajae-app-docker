#!/usr/bin/env bash
set -e

# ==============================================================================
# Environment Defaults
# ==============================================================================
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

# Addon / Package Provisioning Configuration
export APT_PACKAGES="${APT_PACKAGES:-}"
export UV_TOOLS="${UV_TOOLS:-}"
export PIP_PACKAGES="${PIP_PACKAGES:-}"
export GITHUB_APPS="${GITHUB_APPS:-}"
export AUTO_UPDATE_PACKAGES="${AUTO_UPDATE_PACKAGES:-true}"
export CHECK_PACKAGE_UPDATES="${CHECK_PACKAGE_UPDATES:-true}"
export PACKAGE_UPDATE_INTERVAL="${PACKAGE_UPDATE_INTERVAL:-0}"

# ADB Configuration
export ADB_CONNECT="${ADB_CONNECT:-}"

# SSH Configuration
export SSH_ENABLE="${SSH_ENABLE:-false}"
export SSH_PORT="${SSH_PORT:-2222}"
export SSH_ALLOW_PASSWORD="${SSH_ALLOW_PASSWORD:-false}"
export SSH_PASSWORD="${SSH_PASSWORD:-}"
export SSH_PUBLIC_KEYS="${SSH_PUBLIC_KEYS:-}"
export SSH_NO_AUTH="${SSH_NO_AUTH:-false}"
export SSH_DEFAULT_COMMAND="${SSH_DEFAULT_COMMAND:-gjc}"
export INSTALL_GJC_CLI="${INSTALL_GJC_CLI:-true}"

# Ensure PATH prioritizes /data/bin and aqua bin
export PATH="/data/bin:/root/.local/share/aquaproj-aqua/bin:/usr/local/bin:$PATH"
export UV_CACHE_DIR="/data/cache/uv"
export PIP_CACHE_DIR="/data/cache/pip"
export AQUA_ROOT_DIR="/data/aqua"
export NPM_CONFIG_CACHE="/data/cache/npm"

# ==============================================================================
# Directory & Cache Preparation
# ==============================================================================
mkdir -p "${DATABASE_PATH%/*}" "${WORKSPACES_ROOT}" "${GJC_WORKER_AGENT_DIR}" /data/logs /app
mkdir -p /data/bin /data/cache/apt/archives /data/cache/uv /data/cache/pip /data/cache/aqua /data/cache/npm /data/ssh /data/.installed_hashes
mkdir -p /root/.ssh /var/run/sshd

# Point apt archive cache to persistent /data/cache/apt/archives
if [ ! -L /var/cache/apt/archives ]; then
    rm -rf /var/cache/apt/archives
    ln -sf /data/cache/apt/archives /var/cache/apt/archives
fi

# ==============================================================================
# Application Installation / Update Check
# ==============================================================================
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

# ==============================================================================
# Helper: Comma-separated Parser
# ==============================================================================
parse_csv() {
    local input="$1"
    IFS=',' read -ra items <<< "$input"
    for item in "${items[@]}"; do
        item="$(echo "$item" | xargs)"
        [ -n "$item" ] && echo "$item"
    done
}

# ==============================================================================
# Provisioning: APT Packages
# ==============================================================================
provision_apt() {
    if [ -z "${APT_PACKAGES}" ]; then
        return 0
    fi

    local current_hash
    current_hash="$(echo -n "${APT_PACKAGES}" | md5sum | awk '{print $1}')"
    local saved_hash_file="/data/.installed_hashes/apt.hash"
    local previous_hash=""
    [ -f "$saved_hash_file" ] && previous_hash="$(cat "$saved_hash_file")"

    local should_install="false"
    if [ "$current_hash" != "$previous_hash" ]; then
        should_install="true"
    elif [ "${AUTO_UPDATE_PACKAGES}" = "true" ] || [ "${AUTO_UPDATE_PACKAGES}" = "1" ]; then
        should_install="true"
    fi

    if [ "$should_install" = "true" ]; then
        echo "==> [APT] Provisioning packages: ${APT_PACKAGES}..."
        apt-get update -y
        # Convert comma list to space-separated arguments
        local pkg_list=()
        while IFS= read -r pkg; do
            pkg_list+=("$pkg")
        done < <(parse_csv "${APT_PACKAGES}")

        if [ ${#pkg_list[@]} -gt 0 ]; then
            apt-get install -y --no-install-recommends "${pkg_list[@]}"
        fi
        echo "$current_hash" > "$saved_hash_file"
    elif [ "${CHECK_PACKAGE_UPDATES}" = "true" ] || [ "${CHECK_PACKAGE_UPDATES}" = "1" ]; then
        echo "==> [APT] Checking for package updates..."
        apt-get update -qq || true
        apt-get --just-print upgrade 2>/dev/null | grep -E "^Inst " || true
    fi
}

# ==============================================================================
# Provisioning: Python UV Tools & Pip Packages
# ==============================================================================
provision_uv_pip() {
    # UV Tools (Isolated CLI tools / MCP servers)
    if [ -n "${UV_TOOLS}" ]; then
        while IFS= read -r tool; do
            echo "==> [UV Tool] Installing tool: ${tool}..."
            local uv_upgrade_flag=""
            if [ "${AUTO_UPDATE_PACKAGES}" = "true" ] || [ "${AUTO_UPDATE_PACKAGES}" = "1" ]; then
                uv_upgrade_flag="--upgrade"
            fi
            uv tool install ${uv_upgrade_flag} "${tool}" || true
        done < <(parse_csv "${UV_TOOLS}")
    fi

    # Global Pip Packages
    if [ -n "${PIP_PACKAGES}" ]; then
        local pip_list=()
        while IFS= read -r pkg; do
            pip_list+=("$pkg")
        done < <(parse_csv "${PIP_PACKAGES}")

        if [ ${#pip_list[@]} -gt 0 ]; then
            echo "==> [PIP] Installing packages: ${PIP_PACKAGES}..."
            local pip_upgrade_flag=""
            if [ "${AUTO_UPDATE_PACKAGES}" = "true" ] || [ "${AUTO_UPDATE_PACKAGES}" = "1" ]; then
                pip_upgrade_flag="--upgrade"
            fi
            uv pip install --system ${pip_upgrade_flag} "${pip_list[@]}" || true
        fi
    fi
}

# ==============================================================================
# Provisioning: GitHub Apps via Aqua
# ==============================================================================
provision_aqua() {
    if [ -z "${GITHUB_APPS}" ]; then
        return 0
    fi

    mkdir -p /data/aqua
    local aqua_yaml="/data/aqua/aqua.yaml"

    echo "==> [Aqua] Generating ${aqua_yaml} for GITHUB_APPS..."
    cat > "$aqua_yaml" <<'EOF'
---
registries:
  - type: standard
    ref: v4.325.0
packages:
EOF

    while IFS= read -r app; do
        cat >> "$aqua_yaml" <<EOF
  - name: ${app}
EOF
    done < <(parse_csv "${GITHUB_APPS}")

    echo "==> [Aqua] Installing GitHub apps..."
    AQUA_ROOT_DIR="/data/aqua" aqua install -a -c "$aqua_yaml" || true

    # Link aqua binaries into /data/bin
    if [ -d "/data/aqua/bin" ]; then
        for b in /data/aqua/bin/*; do
            [ -e "$b" ] || continue
            ln -sf "$b" "/data/bin/$(basename "$b")"
        done
    fi

    if [ "${AUTO_UPDATE_PACKAGES}" = "true" ] || [ "${AUTO_UPDATE_PACKAGES}" = "1" ]; then
        echo "==> [Aqua] Updating GitHub apps..."
        AQUA_ROOT_DIR="/data/aqua" aqua update-all -c "$aqua_yaml" || true
    fi
}

# ==============================================================================
# Provisioning: Standalone GJC CLI Binary
# ==============================================================================
provision_gjc_cli() {
    if [ "${INSTALL_GJC_CLI}" = "true" ] || [ "${INSTALL_GJC_CLI}" = "1" ]; then
        if [ ! -f "/data/bin/gjc" ]; then
            echo "==> [GJC CLI] Creating standalone /data/bin/gjc launcher..."
            cat > /data/bin/gjc <<'EOF'
#!/bin/sh
exec bun /app/node_modules/@gajae-code/coding-agent/bin/gjc.js "$@"
EOF
            chmod 0755 /data/bin/gjc
        fi
    fi
}

# ==============================================================================
# Android ADB Auto-Connect
# ==============================================================================
setup_adb() {
    if [ -n "${ADB_CONNECT}" ]; then
        echo "==> [ADB] Starting ADB server..."
        adb start-server || true
        while IFS= read -r endpoint; do
            echo "==> [ADB] Connecting to ${endpoint}..."
            adb connect "$endpoint" || true
        done < <(parse_csv "${ADB_CONNECT}")
    fi
}

# ==============================================================================
# SSH Daemon Bootstrap
# ==============================================================================
setup_ssh() {
    if [ "${SSH_ENABLE}" != "true" ] && [ "${SSH_ENABLE}" != "1" ]; then
        return 0
    fi

    echo "==> [SSH] Configuring SSH daemon on port ${SSH_PORT}..."

    # Persist host keys in /data/ssh
    if [ ! -f /data/ssh/ssh_host_ed25519_key ]; then
        echo "==> [SSH] Generating persistent host ed25519 key..."
        ssh-keygen -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N "" -q
    fi
    if [ ! -f /data/ssh/ssh_host_rsa_key ]; then
        echo "==> [SSH] Generating persistent host RSA key..."
        ssh-keygen -t rsa -b 4096 -f /data/ssh/ssh_host_rsa_key -N "" -q
    fi

    chmod 600 /data/ssh/ssh_host_*_key 2>/dev/null || true
    chmod 644 /data/ssh/ssh_host_*_key.pub 2>/dev/null || true

    local sshd_config="/etc/ssh/sshd_config"
    cat > "$sshd_config" <<EOF
Port ${SSH_PORT}
HostKey /data/ssh/ssh_host_ed25519_key
HostKey /data/ssh/ssh_host_rsa_key
AuthorizedKeysFile .ssh/authorized_keys
ChallengeResponseAuthentication no
UsePAM no
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF

    # Configure Authentication
    if [ "${SSH_NO_AUTH}" = "true" ] || [ "${SSH_NO_AUTH}" = "1" ]; then
        echo "==> [SSH] SSH_NO_AUTH is enabled. Permitting empty passwords and root login."
        cat >> "$sshd_config" <<EOF
PermitRootLogin yes
PermitEmptyPasswords yes
PasswordAuthentication yes
EOF
        passwd -d root 2>/dev/null || true
    else
        cat >> "$sshd_config" <<EOF
PermitRootLogin yes
EOF
        if [ "${SSH_ALLOW_PASSWORD}" = "true" ] || [ "${SSH_ALLOW_PASSWORD}" = "1" ]; then
            cat >> "$sshd_config" <<EOF
PasswordAuthentication yes
EOF
            if [ -n "${SSH_PASSWORD}" ]; then
                echo "root:${SSH_PASSWORD}" | chpasswd
            fi
        else
            cat >> "$sshd_config" <<EOF
PasswordAuthentication no
EOF
        fi
    fi

    # Authorized keys setup
    if [ -n "${SSH_PUBLIC_KEYS}" ]; then
        mkdir -p /root/.ssh
        touch /root/.ssh/authorized_keys
        # Check if SSH_PUBLIC_KEYS is a URL
        if [[ "${SSH_PUBLIC_KEYS}" =~ ^https?:// ]]; then
            echo "==> [SSH] Fetching public keys from URL ${SSH_PUBLIC_KEYS}..."
            curl -fsSL "${SSH_PUBLIC_KEYS}" >> /root/.ssh/authorized_keys || true
        else
            while IFS= read -r key; do
                if [ -n "$key" ]; then
                    echo "$key" >> /root/.ssh/authorized_keys
                fi
            done < <(parse_csv "${SSH_PUBLIC_KEYS}")
        fi
        chmod 700 /root/.ssh
        chmod 600 /root/.ssh/authorized_keys
    fi

    # Set default command or login landing behavior
    if [ "${SSH_DEFAULT_COMMAND}" = "gjc" ]; then
        # Add interactive gjc launch to bashrc for interactive SSH logins
        if ! grep -q "LAUNCH_GJC_ON_LOGIN" /root/.bashrc 2>/dev/null; then
            cat >> /root/.bashrc <<'EOF'

# Auto-launch GJC CLI on interactive SSH login
if [ -n "$SSH_CONNECTION" ] && [ -t 1 ]; then
    export LAUNCH_GJC_ON_LOGIN=1
    if [ -x /data/bin/gjc ]; then
        exec /data/bin/gjc
    fi
fi
EOF
        fi
    fi

    # Start sshd in background
    /usr/sbin/sshd
    echo "==> [SSH] SSH daemon running on port ${SSH_PORT}."
}

# ==============================================================================
# Run All Startup Provisioners
# ==============================================================================
provision_apt
provision_uv_pip
provision_aqua
provision_gjc_cli
setup_adb
setup_ssh

# ==============================================================================
# Startup Banner
# ==============================================================================
echo "=========================================================="
echo " Starting Gajae Code App Container"
echo " Version        : $(cat /app/.installed_version 2>/dev/null || echo 'unknown')"
echo " Bind Address   : ${HOST}:${SERVER_PORT}"
echo " Allowed Hosts  : ${ALLOWED_HOSTS}"
echo " Unauth Remote  : ${GAJAE_ALLOW_UNAUTH_REMOTE}"
echo " Database Path  : ${DATABASE_PATH}"
echo " Workspace Root : ${WORKSPACES_ROOT}"
echo " Auto Update    : ${AUTO_UPDATE} (Interval: ${UPDATE_INTERVAL}s)"
if [ "${SSH_ENABLE}" = "true" ] || [ "${SSH_ENABLE}" = "1" ]; then
echo " SSH Daemon     : Enabled on port ${SSH_PORT}"
fi
echo "=========================================================="

# If running a non-server command (e.g. bash, status, info)
if [ "$#" -gt 0 ] && [ "$1" != "start" ]; then
    if [ "$1" = "status" ] || [ "$1" = "info" ] || [ "$1" = "version" ]; then
        exec node /app/dist-server/server/cli.js "$@"
    else
        exec "$@"
    fi
fi

# ==============================================================================
# Process Supervisor & Background Update Loops
# ==============================================================================
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

# Periodic background app update loop
if [ "${AUTO_UPDATE}" = "true" ] || [ "${AUTO_UPDATE}" = "1" ]; then
    if [ "${UPDATE_INTERVAL}" -gt 0 ] 2>/dev/null; then
        echo "==> [Auto-Update] Periodic app update check enabled (every ${UPDATE_INTERVAL}s)."
        (
            while true; do
                sleep "${UPDATE_INTERVAL}"
                echo "==> [Auto-Update] Running scheduled app update check..."
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

# Periodic background package update loop
if [ "${PACKAGE_UPDATE_INTERVAL}" -gt 0 ] 2>/dev/null; then
    echo "==> [Auto-Update] Periodic package update check enabled (every ${PACKAGE_UPDATE_INTERVAL}s)."
    (
        while true; do
            sleep "${PACKAGE_UPDATE_INTERVAL}"
            echo "==> [Auto-Update] Running scheduled package update check..."
            provision_apt || true
            provision_uv_pip || true
            provision_aqua || true
        done
    ) &
fi

# Supervisor loop
while true; do
    node /app/dist-server/server/cli.js start &
    SERVER_PID=$!
    wait "$SERVER_PID" || true

    sleep 1
done
