FROM node:22-bookworm-slim

LABEL org.opencontainers.image.title="Gajae Code App" \
      org.opencontainers.image.description="Dynamic runtime container for Gajae Code App with automatic self-updating, SSH, and package provisioning" \
      org.opencontainers.image.source="https://github.com/websterwh/gajae-app-docker" \
      org.opencontainers.image.licenses="MIT"

# Install system dependencies:
# - build / archive tools & utilities
# - openssh-server for container SSH access
# - Playwright / Chromium headless rendering dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    ca-certificates \
    curl \
    git \
    python3 \
    python3-pip \
    procps \
    tar \
    gzip \
    unzip \
    jq \
    openssh-server \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    && rm -rf /var/lib/apt/lists/*

# Install uv & uvx (fast Python package / tool runner)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh && \
    chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx 2>/dev/null || true

# Install aqua (CLI package manager for GitHub releases) directly from GitHub release
RUN curl -sSfL https://github.com/aquaproj/aqua/releases/download/v2.66.0/aqua_linux_amd64.tar.gz | tar -xz -C /usr/local/bin aqua && \
    chmod 0755 /usr/local/bin/aqua

# Configure Git system-wide to trust all mounted directories
RUN git config --system --add safe.directory '*'
WORKDIR /data/app

# Copy installation & update scripts
COPY scripts/install-release.sh /usr/local/bin/install-release
COPY scripts/install-github-app.py /usr/local/bin/install-github-app
RUN chmod +x /usr/local/bin/install-release /usr/local/bin/install-github-app

# Install global CLI wrapper for convenience
RUN printf '#!/bin/sh\nexec node /app/dist-server/server/cli.js "$@"\n' > /usr/local/bin/gajae-app && \
    chmod 0755 /usr/local/bin/gajae-app

# Create default mount points for persistence and set up /app link
RUN mkdir -p /data /data/bin /workspace /root/.gjc /data/app /var/run/sshd && \
    ln -sf /data/app /app
# Default environment configuration
ENV PATH="/data/bin:/root/.local/share/aquaproj-aqua/bin:/usr/local/bin:$PATH" \
    UV_CACHE_DIR="/data/cache/uv" \
    PIP_CACHE_DIR="/data/cache/pip" \
    UV_LINK_MODE="copy" \
    AQUA_ROOT_DIR="/data/aqua" \
    NPM_CONFIG_CACHE="/data/cache/npm" \
    HOST=0.0.0.0 \
    SERVER_PORT=3001 \
    GAJAE_ALLOW_UNAUTH_REMOTE=1 \
    ALLOWED_HOSTS=* \
    DATABASE_PATH=/data/auth.db \
    WORKSPACES_ROOT=/workspace \
    GJC_WORKER_AGENT_DIR=/root/.gjc/agent \
    AUTO_UPDATE=true \
    UPDATE_INTERVAL=0 \
    UPSTREAM_REPO=devswha/gajae-code-app \
    VERSION=latest \
    NODE_ENV=production \
    AUTO_UPDATE_PACKAGES=true \
    CHECK_PACKAGE_UPDATES=true \
    POST_COMMANDS="" \
    INSTALL_GJC_CLI=true \
    SSH_ENABLE=false \
    SSH_PORT=2222 \
    SSH_ALLOW_PASSWORD=false \
    SSH_PASSWORD="" \
    SSH_PUBLIC_KEYS="" \
    SSH_NO_AUTH=false \
    SSH_DEFAULT_COMMAND=""
EXPOSE 3001 2222

VOLUME ["/data", "/workspace", "/root/.gjc"]

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start"]
