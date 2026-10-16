FROM node:22-bookworm-slim

LABEL org.opencontainers.image.title="Gajae Code App" \
      org.opencontainers.image.description="Dynamic runtime container for Gajae Code App with automatic self-updating" \
      org.opencontainers.image.source="https://github.com/websterwh/gajae-app-docker" \
      org.opencontainers.image.licenses="MIT"

# Install system dependencies required by GJC coding agent and developer tools
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installation & update script
COPY scripts/install-release.sh /usr/local/bin/install-release
RUN chmod +x /usr/local/bin/install-release

# Install global CLI wrapper for convenience
RUN printf '#!/bin/sh\nexec node /app/dist-server/server/cli.js "$@"\n' > /usr/local/bin/gajae-app && \
    chmod 0755 /usr/local/bin/gajae-app

# Create default mount points for persistence
RUN mkdir -p /data /workspace /root/.gjc /app

# Default environment configuration
ENV HOST=0.0.0.0 \
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
    NODE_ENV=production

EXPOSE 3001

VOLUME ["/data", "/workspace", "/root/.gjc"]

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start"]
