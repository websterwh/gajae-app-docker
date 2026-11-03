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
export POST_COMMANDS="${POST_COMMANDS:-}"
# SSH Configuration
export SSH_ENABLE="${SSH_ENABLE:-false}"
export SSH_PORT="${SSH_PORT:-2222}"
export SSH_ALLOW_PASSWORD="${SSH_ALLOW_PASSWORD:-false}"
export SSH_PASSWORD="${SSH_PASSWORD:-}"
export SSH_PUBLIC_KEYS="${SSH_PUBLIC_KEYS:-}"
export SSH_NO_AUTH="${SSH_NO_AUTH:-false}"
export SSH_DEFAULT_COMMAND="${SSH_DEFAULT_COMMAND:-}"
export INSTALL_GJC_CLI="${INSTALL_GJC_CLI:-true}"

# Ensure PATH prioritizes /data/bin, /root/.local/bin, and aqua bin
export PATH="/data/bin:/root/.local/bin:/root/.local/share/aquaproj-aqua/bin:/usr/local/bin:$PATH"
export UV_CACHE_DIR="/data/cache/uv"
export PIP_CACHE_DIR="/data/cache/pip"
export UV_LINK_MODE="copy"
export AQUA_ROOT_DIR="/data/aqua"
export NPM_CONFIG_CACHE="/data/cache/npm"
# ==============================================================================
# Directory & Cache Preparation
# ==============================================================================
mkdir -p "${DATABASE_PATH%/*}" "${WORKSPACES_ROOT}" "${GJC_WORKER_AGENT_DIR}" /data/logs /data/app /data/share
mkdir -p /data/bin /data/cache/apt/archives /data/cache/uv /data/cache/pip /data/cache/aqua /data/cache/npm /data/ssh /data/.installed_hashes
mkdir -p /root/.ssh /var/run/sshd /var/lib/dbus

# Ensure machine-id exists and persists in /data so GJC machine-local identity is valid
if [ ! -f /data/machine-id ]; then
    od -vN 16 -An -tx1 /dev/urandom | tr -d ' \r\n' > /data/machine-id
    printf '\n' >> /data/machine-id
fi
cp -f /data/machine-id /etc/machine-id
cp -f /data/machine-id /var/lib/dbus/machine-id 2>/dev/null || true
# Ensure /app symlink points to /data/app
if [ ! -L /app ]; then
    rm -rf /app
    ln -s /data/app /app
fi

# Ensure working directory exists and cd into it so uv_cwd never fails
cd /data/app
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

# Ensure upstream gjc-bun-sdk-adapter recognizes auth: none (credentialless) providers
if [ -f "/app/dist-server/server/gjc-bun-sdk-adapter.js" ]; then
    sed -i 's/if (!eligibleProviders.has(provider) && await authStorage.peekApiKey(provider) !== undefined)/if (!eligibleProviders.has(provider) \&\& (modelRegistry.isCredentiallessProvider(provider) || await authStorage.peekApiKey(provider) !== undefined))/' /app/dist-server/server/gjc-bun-sdk-adapter.js 2>/dev/null || true
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

    if [ "$current_hash" != "$previous_hash" ]; then
        echo "==> [APT] Package list changed. Provisioning: ${APT_PACKAGES}..."
        local pkg_list=()
        while IFS= read -r pkg; do
            pkg_list+=("$pkg")
        done < <(parse_csv "${APT_PACKAGES}")

        if [ ${#pkg_list[@]} -gt 0 ]; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends "${pkg_list[@]}" >/dev/null
        fi
        echo "$current_hash" > "$saved_hash_file"
        echo "==> [APT] Finished provisioning packages."
    elif [ "${AUTO_UPDATE_PACKAGES}" = "true" ] || [ "${AUTO_UPDATE_PACKAGES}" = "1" ]; then
        echo "==> [APT] Checking for updates on installed packages..."
        apt-get update -qq || true
        local upgradable
        upgradable="$(apt-get --just-print upgrade 2>/dev/null | grep -E '^Inst ' || true)"
        if [ -n "$upgradable" ]; then
            echo "==> [APT] Upgrades available. Updating packages..."
            DEBIAN_FRONTEND=noninteractive apt-get upgrade -qq -y >/dev/null || true
            echo "==> [APT] Finished upgrading packages."
        else
            echo "==> [APT] Packages are up to date."
        fi
    fi
}

# ==============================================================================
# Provisioning: Python UV Tools & Pip Packages
# ==============================================================================
provision_uv_pip() {
    # UV Tools (Isolated CLI tools / MCP servers)
    if [ -n "${UV_TOOLS}" ]; then
        local current_uv_hash
        current_uv_hash="$(echo -n "${UV_TOOLS}" | md5sum | awk '{print $1}')"
        local saved_uv_hash_file="/data/.installed_hashes/uv.hash"
        local prev_uv_hash=""
        [ -f "$saved_uv_hash_file" ] && prev_uv_hash="$(cat "$saved_uv_hash_file")"

        if [ "$current_uv_hash" != "$prev_uv_hash" ]; then
            while IFS= read -r tool; do
                echo "==> [UV Tool] Installing tool: ${tool}..."
                uv tool install -q "${tool}" || true
            done < <(parse_csv "${UV_TOOLS}")
            echo "$current_uv_hash" > "$saved_uv_hash_file"
        elif [ "${AUTO_UPDATE_PACKAGES}" = "true" ] || [ "${AUTO_UPDATE_PACKAGES}" = "1" ]; then
            echo "==> [UV Tool] Checking for tool updates..."
            uv tool upgrade --all -q 2>/dev/null || true
            echo "==> [UV Tool] Tools are up to date."
        fi
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
            uv pip install -q --system ${pip_upgrade_flag} "${pip_list[@]}" || true
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

    mkdir -p /data/aqua /data/bin /data/share
    while IFS= read -r app; do
        [ -z "$app" ] && continue
        /usr/local/bin/install-github-app "${app}" || true
    done < <(parse_csv "${GITHUB_APPS}")
}

# ==============================================================================
# Provisioning: Standalone GJC CLI Binary
# ==============================================================================
provision_gjc_cli() {
    if [ "${INSTALL_GJC_CLI}" != "true" ] && [ "${INSTALL_GJC_CLI}" != "1" ]; then
        return 0
    fi

    local standalone_bin="/data/bin/gjc-standalone"
    local needs_download="false"

    if [ ! -f "$standalone_bin" ]; then
        needs_download="true"
    elif [ "${AUTO_UPDATE}" = "true" ] || [ "${AUTO_UPDATE}" = "1" ]; then
        needs_download="true"
    fi

    if [ "$needs_download" = "true" ]; then
        local latest_release
        latest_release="$(curl -fsSL -H "User-Agent: GJC-Installer" "https://api.github.com/repos/Yeachan-Heo/gajae-code/releases/latest" 2>/dev/null || true)"
        local download_url
        download_url="$(echo "$latest_release" | jq -r '.assets[] | select(.name == "gjc-linux-x64") | .browser_download_url' 2>/dev/null || true)"
        local tag
        tag="$(echo "$latest_release" | jq -r '.tag_name // empty' 2>/dev/null || true)"

        if [ -n "$download_url" ] && [ "$download_url" != "null" ]; then
            local current_ver=""
            [ -f "/data/bin/.gjc_version" ] && current_ver="$(cat /data/bin/.gjc_version)"
            if [ "$current_ver" != "$tag" ] || [ ! -f "$standalone_bin" ]; then
                echo "==> [GJC CLI] Downloading latest standalone gjc binary (${tag:-latest})..."
                curl -fsSL -o "${standalone_bin}.tmp" "$download_url" && \
                    mv "${standalone_bin}.tmp" "$standalone_bin" && \
                    chmod 0755 "$standalone_bin" && \
                    echo "$tag" > /data/bin/.gjc_version
                echo "==> [GJC CLI] Standalone gjc updated to ${tag}."
            fi
        fi
    fi

    # Create /data/bin/gjc wrapper that runs standalone or fallback
    cat > /data/bin/gjc <<'EOF'
#!/bin/sh
if [ -x "/data/bin/gjc-standalone" ]; then
    exec /data/bin/gjc-standalone "$@"
fi
if [ -x "/root/.local/bin/gjc" ]; then
    exec /root/.local/bin/gjc "$@"
fi
exec bun /app/node_modules/@gajae-code/coding-agent/bin/gjc.js "$@"
EOF
    chmod 0755 /data/bin/gjc
}

# ==============================================================================
# Post Commands Execution
# ==============================================================================
run_post_commands() {
    if [ -n "${POST_COMMANDS}" ]; then
        echo "==> [Post Commands] Executing custom post commands..."
        eval "${POST_COMMANDS}" || true
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
SetEnv PATH=/data/bin:/root/.local/bin:/root/.local/share/aquaproj-aqua/bin:/usr/local/bin:/usr/bin:/bin
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

    # Configure interactive shell landing in WORKSPACES_ROOT and default command
    # Also set /workspace as home or cd on login
    cat > /root/.bash_profile <<EOF
export PATH="/data/bin:/root/.local/bin:/root/.local/share/aquaproj-aqua/bin:/usr/local/bin:\$PATH"
export EDITOR="nano"
export VISUAL="nano"
if [ -f /root/.bashrc ]; then
    . /root/.bashrc
fi
if [ -d "${WORKSPACES_ROOT}" ]; then
    cd "${WORKSPACES_ROOT}" 2>/dev/null || true
fi
EOF

    cat > /root/.bashrc <<EOF
export PATH="/data/bin:/root/.local/bin:/root/.local/share/aquaproj-aqua/bin:/usr/local/bin:\$PATH"
export EDITOR="nano"
export VISUAL="nano"
# Set shell working directory to WORKSPACES_ROOT
if [ -d "${WORKSPACES_ROOT}" ]; then
    cd "${WORKSPACES_ROOT}" 2>/dev/null || true
fi

# Run custom SSH command if specified (e.g. SSH_DEFAULT_COMMAND=gjc)
if [ -n "\${SSH_DEFAULT_COMMAND:-}" ] && [ -n "\$SSH_CONNECTION" ] && [ -t 1 ] && [ -z "\$LAUNCHED_SSH_COMMAND" ]; then
    export LAUNCHED_SSH_COMMAND=1
    \${SSH_DEFAULT_COMMAND} || true
fi
EOF
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
run_post_commands
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

# Periodic background combined update loop (App + Addon Packages)
if [ "${AUTO_UPDATE}" = "true" ] || [ "${AUTO_UPDATE}" = "1" ]; then
    if [ "${UPDATE_INTERVAL}" -gt 0 ] 2>/dev/null; then
        echo "==> [Auto-Update] Periodic update check enabled (every ${UPDATE_INTERVAL}s)."
        (
            while true; do
                sleep "${UPDATE_INTERVAL}"
                echo "==> [Auto-Update] Running scheduled update check..."
                # Check and update packages
                provision_apt || true
                provision_uv_pip || true
                provision_aqua || true

                # Check and update Gajae Code App
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
