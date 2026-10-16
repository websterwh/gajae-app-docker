# Gajae Code App Docker

Official Docker packaging for **Gajae Code App** (`gajae-app`), featuring **dynamic runtime release pulling and automated in-container self-updates**.

---

## Highlights

- 🚀 **Zero Pre-baked Versions**: The Docker image is a lightweight, pure runtime environment (Node 22, Bun, Git, Python 3). No application versions are hardcoded or pre-baked into the image layers.
- 📥 **Pulls Latest at First Boot**: When you launch the container, it automatically queries GitHub for the latest release, downloads the server bundle, verifies the SHA256 checksum, and launches it.
- 🔄 **Automatic Updates**: On every subsequent restart (and optionally periodically while running via `UPDATE_INTERVAL`), the container checks GitHub for new releases. If an update is detected, it downloads and hot-restarts in-place.
- ⚙️ **Configurable**: Easily override any setting using standard Docker environment variables (`.env`).
- 💾 **Persistent Data**: Separate volumes for application database, agent credentials, and coding workspaces.
- 🛡️ **Secure by Default**: Never requires mounting `/var/run/docker.sock`.

---

## Quick Start

### 1. Using Docker Compose (Recommended)

1. Clone this repository:
   ```bash
   git clone https://github.com/websterwh/gajae-app-docker.git
   cd gajae-app-docker
   ```

2. (Optional) Customize environment variables:
   ```bash
   cp .env.example .env
   # Edit .env to adjust port, workspace directory, or API keys
   ```

3. Start the application:
   ```bash
   docker compose up -d
   ```

4. Open the Web UI:
   Navigate to **`http://localhost:3001`** in your browser.

---

### 2. Using `docker run` Directly

```bash
docker run -d \
  --name gajae-app \
  --restart unless-stopped \
  -p 3001:3001 \
  -e HOST=0.0.0.0 \
  -e SERVER_PORT=3001 \
  -e GAJAE_ALLOW_UNAUTH_REMOTE=1 \
  -e ALLOWED_HOSTS=* \
  -e AUTO_UPDATE=true \
  -v ./data:/data \
  -v ./workspace:/workspace \
  -v ./gjc-config:/root/.gjc \
  ghcr.io/websterwh/gajae-app-docker:latest
```

---

## How In-Container Updates Work

```
[ Container First Boot ]
          │
          ▼
[ Check GitHub API (devswha/gajae-code-app) ]
          │
          ├─► Download latest release tarball & .sha256
          ├─► Verify SHA256 checksum
          ├─► Extract into /app
          └─► Launch Gajae Code App (0.0.0.0:3001)

[ Subsequent Boots / Background Checks ]
          │
          ▼
[ Compare Local Version vs Remote Release ]
          │
    ┌─────┴─────┐
    ▼           ▼
[ Matches ] [ Newer Release Found ]
    │           │
    │           ├─► Download & verify checksum
    │           ├─► Extract new version
    │           └─► Hot-restart server in container
    ▼
[ Continue Serving ]
```

- **Startup Check (`AUTO_UPDATE=true`, Default)**: Checks GitHub on boot; skips download if already up to date.
- **Fail-Safe Offline Mode**: If GitHub is unreachable (offline/rate-limited), it gracefully boots the existing installed version without crashing.
- **Periodic Background Updates (`UPDATE_INTERVAL`)**: Set `UPDATE_INTERVAL=21600` (every 6 hours) or `86400` (daily). While running, a background worker checks for updates and reloads the server process automatically.
- **Version Pinning**: To freeze a specific version rather than latest:
  ```env
  VERSION=v2.0.0-beta.20
  AUTO_UPDATE=false
  ```

---

## Environment Variables

| Variable | Default in Container | Description |
|---|---|---|
| `AUTO_UPDATE` | `true` | Check GitHub for new releases on container start. |
| `UPDATE_INTERVAL` | `0` | Seconds between background update checks (0 = on startup only; e.g. `21600` for every 6h). |
| `VERSION` | `latest` | Upstream version tag to target (`latest` or specific tag like `v2.0.0-beta.20`). |
| `UPSTREAM_REPO` | `devswha/gajae-code-app` | GitHub repository to track for releases. |
| `SERVER_PORT` | `3001` | Port the internal server listens on. |
| `HOST` | `0.0.0.0` | Bind IP inside container (`0.0.0.0` required for container port mapping). |
| `GAJAE_ALLOW_UNAUTH_REMOTE` | `1` | Permits binding to `0.0.0.0` across network interfaces. |
| `ALLOWED_HOSTS` | `*` | Admitted hostnames/origins. Use `*` to allow all, or specify comma-separated domains. |
| `DATABASE_PATH` | `/data/auth.db` | Path to persistent SQLite database. |
| `WORKSPACES_ROOT` | `/workspace` | Default directory root for GJC agent projects. |
| `GJC_WORKER_AGENT_DIR` | `/root/.gjc/agent` | Storage directory for agent sessions and custom skills. |
| `ANTHROPIC_API_KEY` | *(empty)* | Optional Anthropic API key. |
| `OPENAI_API_KEY` | *(empty)* | Optional OpenAI API key. |
| `GEMINI_API_KEY` | *(empty)* | Optional Google Gemini API key. |

---

## Directory & Volume Structure

| Container Path | Host Path (Compose) | Purpose |
|---|---|---|
| `/data` | `./data` | Application database (`auth.db`), logs, and server state. |
| `/workspace` | `./workspace` | Projects directory where the coding agent inspects and edits code. |
| `/root/.gjc` | `./gjc-config` | Agent configurations, credentials, and custom skills. |

---

## License

MIT
