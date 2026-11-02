#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-devswha/gajae-code-app}"
VERSION="${2:-latest}"
TARGET_DIR="${3:-/app}"

mkdir -p "${TARGET_DIR}"
VERSION_FILE="${TARGET_DIR}/.installed_version"
CURRENT_VERSION=""
if [ -f "${VERSION_FILE}" ]; then
    CURRENT_VERSION="$(tr -d ' \r\n' < "${VERSION_FILE}")"
fi

echo "==> Checking for updates (Repo: ${REPO}, Target: ${VERSION}, Current: ${CURRENT_VERSION:-none})..."

# Check if a local archive was provided
LOCAL_ARCHIVE=$(find /tmp/local-archive -name "gajae-app-server-*.tar.gz" 2>/dev/null | head -n 1 || true)

if [ -n "${LOCAL_ARCHIVE}" ] && [ -f "${LOCAL_ARCHIVE}" ]; then
    echo "==> Using local pre-built archive: ${LOCAL_ARCHIVE}"
    tar -xzf "${LOCAL_ARCHIVE}" -C "${TARGET_DIR}"
    echo "local" > "${VERSION_FILE}"
else
    # Resolve release information from GitHub API
    RELEASE_JSON=""
    if [ "${VERSION}" = "latest" ]; then
        API_URL="https://api.github.com/repos/${REPO}/releases"
        echo "==> Looking up latest release from ${API_URL}..."
        RELEASE_JSON="$(curl -fsSL -H "User-Agent: Gajae-Updater" "${API_URL}" 2>/dev/null | jq '.[0]' 2>/dev/null || true)"
    else
        API_URL="https://api.github.com/repos/${REPO}/releases/tags/${VERSION}"
        echo "==> Looking up release ${VERSION} from ${API_URL}..."
        RELEASE_JSON="$(curl -fsSL -H "User-Agent: Gajae-Updater" "${API_URL}" 2>/dev/null || true)"
    fi

    TAG_NAME="$(echo "${RELEASE_JSON}" | jq -r '.tag_name // empty' 2>/dev/null || true)"

    # If network/API failed or rate limited
    if [ -z "${TAG_NAME}" ] || [ "${TAG_NAME}" = "null" ]; then
        if [ -f "${TARGET_DIR}/dist-server/server/cli.js" ]; then
            echo "==> [WARN] Could not reach GitHub API or query release. Keeping existing version (${CURRENT_VERSION:-unknown})."
            exit 0
        else
            echo "ERROR: Failed to resolve release from GitHub API for ${REPO} and no existing installation found." >&2
            exit 1
        fi
    fi

    # Check if already running the target version
    if [ -n "${CURRENT_VERSION}" ] && [ "${CURRENT_VERSION}" = "${TAG_NAME}" ] && [ -f "${TARGET_DIR}/dist-server/server/cli.js" ]; then
        echo "==> Gajae Code App is already up to date (${CURRENT_VERSION})."
        exit 0
    fi

    echo "==> New version available: ${TAG_NAME} (current: ${CURRENT_VERSION:-none}). Updating..."

    TARBALL_URL="$(echo "${RELEASE_JSON}" | jq -r '.assets[] | select(.name | endswith("-linux-x64-node22.tar.gz")) | .browser_download_url' | head -n 1)"
    CHECKSUM_URL="$(echo "${RELEASE_JSON}" | jq -r '.assets[] | select(.name | endswith("-linux-x64-node22.tar.gz.sha256")) | .browser_download_url' | head -n 1)"

    if [ -z "${TARBALL_URL}" ] || [ "${TARBALL_URL}" = "null" ]; then
        echo "ERROR: Could not find server tarball asset in release ${TAG_NAME}" >&2
        exit 1
    fi

    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "${TMP_DIR}"' EXIT

    ARCHIVE_FILE="${TMP_DIR}/server.tar.gz"
    CHECKSUM_FILE="${TMP_DIR}/server.tar.gz.sha256"
    echo "==> Downloading ${TAG_NAME} from ${TARBALL_URL}..."
    python3 -c "
import urllib.request, sys
url, out = sys.argv[1], sys.argv[2]
req = urllib.request.Request(url, headers={'User-Agent': 'Gajae-Updater'})
with urllib.request.urlopen(req) as resp, open(out, 'wb') as f:
    total = int(resp.headers.get('Content-Length', 0))
    done, last = 0, -25
    while True:
        chunk = resp.read(131072)
        if not chunk: break
        f.write(chunk)
        done += len(chunk)
        if total:
            pct = int(done * 100 / total)
            if pct >= last + 25 or pct == 100:
                print(f'==> [Download] {pct}% ({done // 1048576}MB / {total // 1048576}MB)', flush=True)
                last = pct
" "${TARBALL_URL}" "${ARCHIVE_FILE}"
    if [ -n "${CHECKSUM_URL}" ] && [ "${CHECKSUM_URL}" != "null" ]; then
        echo "==> Verifying SHA256 checksum..."
        curl -fsSL -o "${CHECKSUM_FILE}" "${CHECKSUM_URL}"
        EXPECTED_HASH="$(awk '{print $1}' "${CHECKSUM_FILE}")"
        (cd "${TMP_DIR}" && echo "${EXPECTED_HASH}  server.tar.gz" | sha256sum -c --status)
    fi
    echo "==> Extracting to ${TARGET_DIR}..."
    tar -xzf "${ARCHIVE_FILE}" -C "${TARGET_DIR}"
    echo "${TAG_NAME}" > "${VERSION_FILE}"

    # Symlink bun if bundled in dist-native
    if [ -f "${TARGET_DIR}/dist-native/bun" ]; then
        ln -sf "${TARGET_DIR}/dist-native/bun" /usr/local/bin/bun
        chmod +x "${TARGET_DIR}/dist-native/bun" 2>/dev/null || true
    fi

    echo "==> Successfully updated Gajae Code App to ${TAG_NAME}."
fi
