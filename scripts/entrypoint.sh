#!/bin/bash
# entrypoint.sh — Wrapper entrypoint for paperclip-synology.
# Manages BETTER_AUTH_SECRET and PAPERCLIP_AGENT_JWT_SECRET (auto-generate + persist)
# and sets Synology-friendly defaults before exec-ing the Paperclip server.
set -e

PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip-workspace/paperclip-home}"
PAPERCLIP_WORKING_DIR="/paperclip-workspace/paperclip-working"
mkdir -p "${HOME}"
mkdir -p "${PAPERCLIP_HOME}"
mkdir -p "${PAPERCLIP_WORKING_DIR}"
SECRET_FILE="${PAPERCLIP_HOME}/.auth_secret"

# --- BETTER_AUTH_SECRET management ---
if [ -n "${BETTER_AUTH_SECRET}" ]; then
  # User supplied the secret via environment variable — use it as-is.
  :
elif [ -f "${SECRET_FILE}" ]; then
  # Read a previously persisted secret from disk.
  BETTER_AUTH_SECRET="$(cat "${SECRET_FILE}")"
  if [ -z "${BETTER_AUTH_SECRET}" ]; then
    echo "[paperclip-synology] Warning: Persisted auth secret is empty, regenerating..."
    BETTER_AUTH_SECRET="$(openssl rand -hex 32)"
    (umask 077; echo "${BETTER_AUTH_SECRET}" > "${SECRET_FILE}")
  fi
  export BETTER_AUTH_SECRET
  echo "[paperclip-synology] Using persisted auth secret."
else
  # First run — generate a new secret and persist it.
  BETTER_AUTH_SECRET="$(openssl rand -hex 32)"
  (umask 077; echo "${BETTER_AUTH_SECRET}" > "${SECRET_FILE}")
  export BETTER_AUTH_SECRET
  echo "[paperclip-synology] Generated and persisted new auth secret."
fi

# --- PAPERCLIP_AGENT_JWT_SECRET management ---
AGENT_JWT_FILE="${PAPERCLIP_HOME}/.agent_jwt_secret"
if [ -n "${PAPERCLIP_AGENT_JWT_SECRET}" ]; then
  :
elif [ -f "${AGENT_JWT_FILE}" ]; then
  PAPERCLIP_AGENT_JWT_SECRET="$(cat "${AGENT_JWT_FILE}")"
  if [ -z "${PAPERCLIP_AGENT_JWT_SECRET}" ]; then
    echo "[paperclip-synology] Warning: Persisted agent JWT secret is empty, regenerating..."
    PAPERCLIP_AGENT_JWT_SECRET="$(openssl rand -hex 32)"
    (umask 077; echo "${PAPERCLIP_AGENT_JWT_SECRET}" > "${AGENT_JWT_FILE}")
  fi
  export PAPERCLIP_AGENT_JWT_SECRET
  echo "[paperclip-synology] Using persisted agent JWT secret."
else
  PAPERCLIP_AGENT_JWT_SECRET="$(openssl rand -hex 32)"
  (umask 077; echo "${PAPERCLIP_AGENT_JWT_SECRET}" > "${AGENT_JWT_FILE}")
  export PAPERCLIP_AGENT_JWT_SECRET
  echo "[paperclip-synology] Generated and persisted new agent JWT secret."
fi

# --- Synology-friendly defaults (only set if not already defined) ---
export SERVE_UI="${SERVE_UI:-true}"
export PORT="${PORT:-3100}"
if ! echo "${PORT}" | grep -qE '^[0-9]+$'; then
  echo "[paperclip-synology] Warning: PORT '${PORT}' is not a valid integer, falling back to 3100."
  PORT=3100
  export PORT
fi

# --- PAPERCLIP_PUBLIC_URL default ---
# Paperclip uses this to determine cookie security: URLs starting with http:// disable
# the Secure flag, allowing sessions to work over plain HTTP (typical for NAS LAN access).
# Without this, cookies default to Secure, which browsers refuse to send over HTTP → 401.
if [ -z "${PAPERCLIP_PUBLIC_URL}" ]; then
  export PAPERCLIP_PUBLIC_URL="http://localhost:${PORT}"
  echo "[paperclip-synology] PAPERCLIP_PUBLIC_URL defaulting to: ${PAPERCLIP_PUBLIC_URL}"
fi

# --- Generate config.json if missing (replaces interactive `onboard` command) ---
INSTANCE_DIR="${PAPERCLIP_HOME}/instances/${PAPERCLIP_INSTANCE_ID:-default}"
CONFIG_FILE="${PAPERCLIP_CONFIG:-${INSTANCE_DIR}/config.json}"
export PAPERCLIP_CONFIG="${CONFIG_FILE}"
if [ ! -f "${CONFIG_FILE}" ]; then
  mkdir -p "$(dirname "${CONFIG_FILE}")"
  (umask 077; cat > "${CONFIG_FILE}" <<CONF
{
  "\$meta": { "version": 1, "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "source": "onboard" },
  "database": { "mode": "embedded-postgres" },
  "logging": { "mode": "file" },
  "server": { "deploymentMode": "authenticated", "exposure": "private", "host": "0.0.0.0", "port": ${PORT} },
  "auth": { "baseUrlMode": "auto" }
}
CONF
  )
  echo "[paperclip-synology] Generated config at ${CONFIG_FILE}"
fi

echo "[paperclip-synology] Working directory: ${PAPERCLIP_WORKING_DIR}"

# --- Fix volume ownership (required for Docker-mounted volumes on Synology) ---
chown -R node:node /paperclip-workspace "${HOME}" "${PAPERCLIP_HOME}" "${PAPERCLIP_WORKING_DIR}"

# --- Register allowed hostnames (background, after server is ready) ---
# Hostname registration requires the database, which is started by `paperclipai run`.
# A background subshell waits for the server to be ready, then registers hostnames.
# Runs on every start so users can add hostnames without recreating the container.
# PAPERCLIP_ALLOWED_HOSTNAMES is a comma-separated list (e.g., "localhost,10.0.0.10,nas.local").
if [ -z "${PAPERCLIP_ALLOWED_HOSTNAMES}" ]; then
  PAPERCLIP_ALLOWED_HOSTNAMES="$(/usr/local/bin/detect-hostnames.sh)"
fi
(
  MAX_ATTEMPTS=90
  POLL_INTERVAL=2
  ATTEMPT=0

  echo "[paperclip-synology] Waiting for server to be ready before registering hostnames..."

  while [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; do
    if curl -sf -o /dev/null "http://localhost:${PORT}" 2>/dev/null; then
      echo "[paperclip-synology] Server is ready. Registering allowed hostnames..."
      IFS=',' read -ra HOSTNAMES <<< "${PAPERCLIP_ALLOWED_HOSTNAMES}"
      for RAW_HOST in "${HOSTNAMES[@]}"; do
        ALLOWED_HOST="$(echo "${RAW_HOST}" | xargs)"
        if [ -n "${ALLOWED_HOST}" ]; then
          if gosu node paperclipai allowed-hostname "${ALLOWED_HOST}"; then
            echo "[paperclip-synology] Registered allowed hostname: ${ALLOWED_HOST}"
          else
            echo "[paperclip-synology] Warning: Failed to register hostname: ${ALLOWED_HOST}"
          fi
        fi
      done
      exit 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep "${POLL_INTERVAL}"
  done

  echo "[paperclip-synology] Warning: Server did not become ready within $((MAX_ATTEMPTS * POLL_INTERVAL))s. Hostname registration skipped."
) &

# --- Start the Paperclip server ---
# paperclipai run handles bootstrap CEO invite generation automatically.
# gosu drops from root to node user; exec replaces PID for proper signal handling.
exec gosu node paperclipai run
