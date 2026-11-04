# Gajae Code App Docker

Docker packaging for **Gajae Code App** (`gajae-app`) built from a pinned revision of the [`websterwh/gajae-code-app`](https://github.com/websterwh/gajae-code-app) source fork. It includes universal package provisioning (APT/UV/Pip/Aqua), Android ADB auto-connect, and direct SSH CLI access.

---

## Highlights

- 🔒 **Reproducible application builds**: The image compiles a specific source commit during `docker compose build`; startup never downloads or modifies application code.
- 🔀 **Upstream-friendly fork workflow**: Merge `devswha/gajae-code-app` into the source fork, update `APP_REF`, then rebuild the image.
- 📦 **Universal Addon Package Provisioning**:
  - `APT_PACKAGES`: Comma-separated Debian packages (e.g. `openjdk-17-jre-headless,ffmpeg`).
  - `UV_TOOLS`: Standalone Python CLI tools / MCP servers (e.g. `serena,canvas-mcp-server`).
  - `PIP_PACKAGES`: Global Python packages via `uv pip install --system`.
  - `GITHUB_APPS`: GitHub release CLI binaries via Aqua (e.g. `skylot/jadx,iBotPeaches/Apktool`).
- ⚡ **Persistent Disk Caching**: APT archives, UV tools, Pip wheels, Aqua downloads, and NPM caches are rooted in `/data/cache/` for instant, cached boots.
- 💻 **Direct Container SSH Access**: In-container SSH daemon (`SSH_ENABLE=true`, port `2222`) that opens into the workspace root (`/workspace`) by default, and can drop you straight into an interactive `gjc` coding session. Supports keyless/passwordless (`SSH_NO_AUTH=true`), passwords, or SSH public keys.
- 🛡️ **Zero Host Docker Socket Dependency**: Never mounts `/var/run/docker.sock`.

---

## Quick Start

### 1. Using Docker Compose (Recommended)

1. Clone this repository:
   ```bash
   git clone https://github.com/websterwh/gajae-app-docker.git
   cd gajae-app-docker
   ```

2. Configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env to customize packages, SSH, or port mappings
   ```

3. Build and start the container:
   ```bash
   docker compose up -d --build
   ```

4. Access the Web UI:
   Navigate to **`http://localhost:3001`** in your browser.

5. (Optional) Connect via SSH directly to GJC CLI:
   If `SSH_ENABLE=true` and `SSH_PORT=2222`:
   ```bash
   ssh -p 2222 root@localhost
   ```

---

## Updating the App Fork

The container never applies runtime patches. Application changes belong in
[`websterwh/gajae-code-app`](https://github.com/websterwh/gajae-code-app), whose
`upstream` remote is `https://github.com/devswha/gajae-code-app.git`.

```bash
git fetch upstream
git merge upstream/main
git push origin main
```

Set `APP_REF` to the resulting commit and rebuild with
`docker compose up -d --build`. Pinning a commit, rather than `main`, makes a
running image traceable to the exact source it contains.

---

## Environment Variables Specification

### Core App & Network
| Variable | Default | Description |
|---|---|---|
| `HOST` | `0.0.0.0` | Bind IP inside container (`0.0.0.0` required for container port mapping). |
| `SERVER_PORT` | `3001` | Port the internal WebUI server listens on. |
| `GAJAE_ALLOW_UNAUTH_REMOTE` | `1` | Permits binding to `0.0.0.0` across network interfaces. |
| `ALLOWED_HOSTS` | `*` | Admitted hostnames/origins (`*` allows all, or enter comma-separated domains). |
| `DATABASE_PATH` | `/data/auth.db` | Path to persistent SQLite database. |
| `WORKSPACES_ROOT` | `/workspace` | Default directory root for GJC agent projects. |
| `GJC_WORKER_AGENT_DIR` | `/root/.gjc/agent` | Storage directory for agent sessions and custom skills. |
| `APP_REPOSITORY` | `https://github.com/websterwh/gajae-code-app.git` | Source repository cloned during the image build. Set as a Compose build argument. |
| `APP_REF` | `5dd9f7fbb4b64df183da491ec785ea35e22e983f` | Immutable source commit built into the image. Set as a Compose build argument. |

### Universal Package Provisioning
| Variable | Default | Description |
|---|---|---|
| `APT_PACKAGES` | *(empty)* | Comma-separated Debian packages to install via APT (`openjdk-17-jre-headless,ffmpeg`). |
| `UV_TOOLS` | *(empty)* | Comma-separated isolated Python CLI tools / MCPs via `uv tool install` (`serena`). |
| `PIP_PACKAGES` | *(empty)* | Comma-separated Python packages installed globally via `uv pip install --system`. |
| `GITHUB_APPS` | *(empty)* | Comma-separated GitHub release apps installed via Aqua (`skylot/jadx,iBotPeaches/Apktool`). |
| `AUTO_UPDATE_PACKAGES` | `true` | Automatically upgrade all installed packages on container boot. |
| `CHECK_PACKAGE_UPDATES` | `true` | Check and log available package updates. |
| `POST_COMMANDS` | *(empty)* | Custom shell commands executed after provisioning (e.g. `adb connect 192.168.1.79:5555`). |
### Direct SSH & GJC CLI Access
| Variable | Default | Description |
|---|---|---|
| `SSH_ENABLE` | `false` | Enable the in-container SSH daemon. |
| `SSH_PORT` | `2222` | Internal listening port for the container SSH daemon. |
| `SSH_ALLOW_PASSWORD`| `false` | Allow password authentication for SSH. |
| `SSH_PASSWORD` | *(empty)* | Root password for SSH if password authentication is enabled. |
| `SSH_PUBLIC_KEYS` | *(empty)* | Public key(s) or URL (https://...) to authorize for SSH. |
| `SSH_NO_AUTH` | `false` | Permit passwordless/keyless direct SSH login (for trusted private networks). |
| `SSH_DEFAULT_COMMAND`| *(empty)* | Optional command to run on SSH login (leave empty to land directly in standard bash shell). |
| `INSTALL_GJC_CLI` | `true` | Create standalone launcher at `/data/bin/gjc`. |

---

## Storage & Volume Layout

| Container Path | Host Path (Compose) | Purpose |
|---|---|---|
| `/data` | `./data` | Persistent SQLite database (`auth.db`), logs, caches (`apt`, `uv`, `pip`, `aqua`, `npm`), host SSH keys, and installed CLI binaries (`/data/bin`). |
| `/workspace` | `./workspace` | Projects directory where the coding agent inspects and edits code. |
| `/root/.gjc` | `./gjc-config` | Agent configurations, credentials, and custom skills. |

---

## License

MIT
