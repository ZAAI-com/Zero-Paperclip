#!/bin/bash
# entrypoint.sh — Wrapper entrypoint for paperclip-synology.
# Manages BETTER_AUTH_SECRET (auto-generate + persist) and sets
# Synology-friendly defaults before exec-ing the Paperclip server.
set -e

PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip-workspace/paperclip-home}"
mkdir -p "${HOME}"
mkdir -p "${PAPERCLIP_HOME}"
SECRET_FILE="${PAPERCLIP_HOME}/.auth_secret"

# --- BETTER_AUTH_SECRET management ---
if [ -n "${BETTER_AUTH_SECRET}" ]; then
  # User supplied the secret via environment variable — use it as-is.
  :
elif [ -f "${SECRET_FILE}" ]; then
  # Read a previously persisted secret from disk.
  BETTER_AUTH_SECRET="$(cat "${SECRET_FILE}")"
  export BETTER_AUTH_SECRET
  echo "[paperclip-synology] Using persisted auth secret."
else
  # First run — generate a new secret and persist it.
  BETTER_AUTH_SECRET="$(openssl rand -hex 32)"
  echo "${BETTER_AUTH_SECRET}" > "${SECRET_FILE}"
  chmod 600 "${SECRET_FILE}"
  export BETTER_AUTH_SECRET
  echo "[paperclip-synology] Generated and persisted new auth secret."
fi

# --- Synology-friendly defaults (only set if not already defined) ---
export SERVE_UI="${SERVE_UI:-true}"
export PORT="${PORT:-3100}"

# --- Generate config.json if missing (replaces interactive `onboard` command) ---
INSTANCE_DIR="${PAPERCLIP_HOME}/instances/${PAPERCLIP_INSTANCE_ID:-default}"
CONFIG_FILE="${PAPERCLIP_CONFIG:-${INSTANCE_DIR}/config.json}"
if [ ! -f "${CONFIG_FILE}" ]; then
  mkdir -p "$(dirname "${CONFIG_FILE}")"
  cat > "${CONFIG_FILE}" <<CONF
{
  "\$meta": { "version": 1, "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "source": "onboard" },
  "database": { "mode": "embedded-postgres" },
  "logging": { "mode": "file" },
  "server": { "deploymentMode": "authenticated", "exposure": "private", "host": "0.0.0.0", "port": ${PORT} },
  "auth": { "baseUrlMode": "auto" }
}
CONF
  chmod 600 "${CONFIG_FILE}"
  echo "[paperclip-synology] Generated config at ${CONFIG_FILE}"
fi

# --- Auto-bootstrap admin on first run ---
# Runs in the background: waits for the server to be healthy, then creates
# the first admin invite URL. The URL is saved to disk and logged.
BOOTSTRAP_MARKER="${PAPERCLIP_HOME}/.bootstrapped"
if [ ! -f "${BOOTSTRAP_MARKER}" ]; then
  (
    echo "[paperclip-synology] Waiting for server to become healthy..."
    until curl -sf "http://localhost:${PORT}/api/health" > /dev/null 2>&1; do
      sleep 2
    done
    echo "[paperclip-synology] Bootstrapping admin..."
    BOOTSTRAP_OUTPUT="$(paperclipai auth bootstrap-ceo 2>&1)" || true
    echo "${BOOTSTRAP_OUTPUT}" > "${PAPERCLIP_HOME}/.bootstrap-url"
    touch "${BOOTSTRAP_MARKER}"
    echo "[paperclip-synology] ${BOOTSTRAP_OUTPUT}"
    echo "[paperclip-synology] Invite URL saved to ${PAPERCLIP_HOME}/.bootstrap-url"
  ) &
fi

# --- Start the Paperclip server ---
exec paperclipai run
