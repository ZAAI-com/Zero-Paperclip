#!/bin/bash
# entrypoint.sh — Wrapper entrypoint for zero-paperclip.
# Manages BETTER_AUTH_SECRET and PAPERCLIP_AGENT_JWT_SECRET (auto-generate + persist)
# and sets Synology-friendly defaults before exec-ing the Paperclip server.
set -e

PAPERCLIP_HOME="${PAPERCLIP_HOME:-/paperclip-workspace/paperclip-home}"
PAPERCLIP_WORKING_DIR="/paperclip-workspace/paperclip-working"
mkdir -p "${HOME}"
mkdir -p "${PAPERCLIP_HOME}"
mkdir -p "${PAPERCLIP_WORKING_DIR}"

# --- Symlink ~/.paperclip to the persistent volume ---
# Paperclip resolves ~/.paperclip via os.userInfo().homedir (/home/node from /etc/passwd)
# rather than $HOME. Without this, embedded Postgres data is ephemeral.
if [ -d /home/node/.paperclip ] && [ ! -L /home/node/.paperclip ]; then
  if [ "$(ls -A /home/node/.paperclip 2>/dev/null)" ] && [ ! "$(ls -A "${PAPERCLIP_HOME}" 2>/dev/null)" ]; then
    echo "[zero-paperclip] Migrating existing ~/.paperclip contents to persistent volume at ${PAPERCLIP_HOME}"
    mv /home/node/.paperclip/* "${PAPERCLIP_HOME}/" 2>/dev/null || true
    mv /home/node/.paperclip/.[!.]* "${PAPERCLIP_HOME}/" 2>/dev/null || true
    mv /home/node/.paperclip/..?* "${PAPERCLIP_HOME}/" 2>/dev/null || true
  else
    echo "[zero-paperclip] Removing ephemeral ~/.paperclip directory before linking to persistent volume"
  fi
  rm -rf /home/node/.paperclip
fi
ln -sfn "${PAPERCLIP_HOME}" /home/node/.paperclip

# --- Symlink CLI tool config directories to the persistent volume ---
# Same issue as .paperclip above: Node.js CLI tools may resolve ~ via
# os.userInfo().homedir (/home/node) instead of $HOME. Without symlinks,
# auth tokens are written to the ephemeral container layer and lost on recreate.
for DIR_NAME in .claude .codex .cursor .config .local; do
  PERSISTENT_DIR="${HOME}/${DIR_NAME}"
  PASSWD_DIR="/home/node/${DIR_NAME}"
  mkdir -p "${PERSISTENT_DIR}"
  if [ -e "${PASSWD_DIR}" ] && [ ! -L "${PASSWD_DIR}" ]; then
    if [ -d "${PASSWD_DIR}" ]; then
      # Migrate any existing contents before replacing with symlink
      if [ -n "$(ls -A "${PASSWD_DIR}" 2>/dev/null)" ]; then
        cp -a "${PASSWD_DIR}/." "${PERSISTENT_DIR}/"
      fi
      rm -rf "${PASSWD_DIR}"
    else
      # Non-directory path (regular file, etc.) — remove before creating symlink
      rm -f "${PASSWD_DIR}"
    fi
  fi
  ln -sfn "${PERSISTENT_DIR}" "${PASSWD_DIR}"
done

SECRET_FILE="${PAPERCLIP_HOME}/.auth_secret"

# --- BETTER_AUTH_SECRET management ---
if [ -n "${BETTER_AUTH_SECRET}" ]; then
  # User supplied the secret via environment variable — use it as-is.
  :
elif [ -f "${SECRET_FILE}" ]; then
  # Read a previously persisted secret from disk.
  BETTER_AUTH_SECRET="$(cat "${SECRET_FILE}")"
  if [ -z "${BETTER_AUTH_SECRET}" ]; then
    echo "[zero-paperclip] Warning: Persisted auth secret is empty, regenerating..."
    BETTER_AUTH_SECRET="$(openssl rand -hex 32)"
    (umask 077; echo "${BETTER_AUTH_SECRET}" > "${SECRET_FILE}")
  fi
  export BETTER_AUTH_SECRET
  echo "[zero-paperclip] Using persisted auth secret."
else
  # First run — generate a new secret and persist it.
  BETTER_AUTH_SECRET="$(openssl rand -hex 32)"
  (umask 077; echo "${BETTER_AUTH_SECRET}" > "${SECRET_FILE}")
  export BETTER_AUTH_SECRET
  echo "[zero-paperclip] Generated and persisted new auth secret."
fi

# --- PAPERCLIP_AGENT_JWT_SECRET management ---
AGENT_JWT_FILE="${PAPERCLIP_HOME}/.agent_jwt_secret"
if [ -n "${PAPERCLIP_AGENT_JWT_SECRET}" ]; then
  :
elif [ -f "${AGENT_JWT_FILE}" ]; then
  PAPERCLIP_AGENT_JWT_SECRET="$(cat "${AGENT_JWT_FILE}")"
  if [ -z "${PAPERCLIP_AGENT_JWT_SECRET}" ]; then
    echo "[zero-paperclip] Warning: Persisted agent JWT secret is empty, regenerating..."
    PAPERCLIP_AGENT_JWT_SECRET="$(openssl rand -hex 32)"
    (umask 077; echo "${PAPERCLIP_AGENT_JWT_SECRET}" > "${AGENT_JWT_FILE}")
  fi
  export PAPERCLIP_AGENT_JWT_SECRET
  echo "[zero-paperclip] Using persisted agent JWT secret."
else
  PAPERCLIP_AGENT_JWT_SECRET="$(openssl rand -hex 32)"
  (umask 077; echo "${PAPERCLIP_AGENT_JWT_SECRET}" > "${AGENT_JWT_FILE}")
  export PAPERCLIP_AGENT_JWT_SECRET
  echo "[zero-paperclip] Generated and persisted new agent JWT secret."
fi

# --- Synology-friendly defaults (only set if not already defined) ---
export SERVE_UI="${SERVE_UI:-true}"
export PORT="${PORT:-3100}"
if ! echo "${PORT}" | grep -qE '^[0-9]+$'; then
  echo "[zero-paperclip] Warning: PORT '${PORT}' is not a valid integer, falling back to 3100."
  PORT=3100
  export PORT
fi

# --- PAPERCLIP_PUBLIC_URL default ---
# Paperclip uses this to determine cookie security: URLs starting with http:// disable
# the Secure flag, allowing sessions to work over plain HTTP (typical for NAS LAN access).
# Without this, cookies default to Secure, which browsers refuse to send over HTTP → 401.
if [ -z "${PAPERCLIP_PUBLIC_URL}" ]; then
  export PAPERCLIP_PUBLIC_URL="http://localhost:${PORT}"
  echo "[zero-paperclip] PAPERCLIP_PUBLIC_URL defaulting to: ${PAPERCLIP_PUBLIC_URL}"
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
  echo "[zero-paperclip] Generated config at ${CONFIG_FILE}"
fi

echo "[zero-paperclip] Working directory: ${PAPERCLIP_WORKING_DIR}"

# --- Fix volume ownership (required for Docker-mounted volumes on Synology) ---
chown node:node /paperclip-workspace
chown -R node:node "${HOME}" "${PAPERCLIP_HOME}" "${PAPERCLIP_WORKING_DIR}"
chown -h node:node /home/node/.paperclip
for DIR_NAME in .claude .codex .cursor .config .local; do
  chown -h node:node "/home/node/${DIR_NAME}"
done

# --- Register allowed hostnames (background, after server is ready) ---
# Hostname registration requires the database, which is started by `paperclipai run`.
# A background subshell waits for the server to be ready, then registers hostnames.
# Runs on every start so users can add hostnames without recreating the container.
# PAPERCLIP_ALLOWED_HOSTNAMES is a comma-separated list (e.g., "localhost,10.0.0.10,nas.local").
# Always auto-detect hostnames, then merge with any user-provided ones
DETECTED_HOSTNAMES="$(/usr/local/bin/detect-hostnames.sh)"
if [ -n "${PAPERCLIP_ALLOWED_HOSTNAMES}" ]; then
  echo "[zero-paperclip] Merging user-provided hostnames: ${PAPERCLIP_ALLOWED_HOSTNAMES}"
  PAPERCLIP_ALLOWED_HOSTNAMES="${DETECTED_HOSTNAMES},${PAPERCLIP_ALLOWED_HOSTNAMES}"
else
  PAPERCLIP_ALLOWED_HOSTNAMES="${DETECTED_HOSTNAMES}"
fi
echo "[zero-paperclip] Final allowed hostnames: ${PAPERCLIP_ALLOWED_HOSTNAMES}"
(
  MAX_ATTEMPTS=90
  POLL_INTERVAL=2
  ATTEMPT=0

  echo "[zero-paperclip] Waiting for server to be ready before registering hostnames..."

  while [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; do
    if curl -sf -o /dev/null "http://localhost:${PORT}" 2>/dev/null; then
      echo "[zero-paperclip] Server is ready. Registering allowed hostnames: ${PAPERCLIP_ALLOWED_HOSTNAMES}"
      IFS=',' read -ra HOSTNAMES <<< "${PAPERCLIP_ALLOWED_HOSTNAMES}"
      for RAW_HOST in "${HOSTNAMES[@]}"; do
        ALLOWED_HOST="$(echo "${RAW_HOST}" | xargs)"
        if [ -n "${ALLOWED_HOST}" ]; then
          if gosu node paperclipai allowed-hostname "${ALLOWED_HOST}"; then
            echo "[zero-paperclip] Registered allowed hostname: ${ALLOWED_HOST}"
          else
            echo "[zero-paperclip] Warning: Failed to register hostname: ${ALLOWED_HOST}"
          fi
        fi
      done
      exit 0
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep "${POLL_INTERVAL}"
  done

  echo "[zero-paperclip] Warning: Server did not become ready within $((MAX_ATTEMPTS * POLL_INTERVAL))s. Hostname registration skipped."
) &

# --- Start the Paperclip server ---
# paperclipai run handles bootstrap CEO invite generation automatically.
# gosu drops from root to node user. We use trap+wait instead of exec so we can
# log shutdown signals for diagnostics (e.g., unexpected SIGTERM on Synology).
cleanup() {
  echo "[zero-paperclip] Received shutdown signal."
  if [ -n "${PAPERCLIP_PID:-}" ]; then
    if kill -0 "${PAPERCLIP_PID}" 2>/dev/null; then
      echo "[zero-paperclip] Forwarding SIGTERM to Paperclip (PID ${PAPERCLIP_PID})..."
      kill -TERM "${PAPERCLIP_PID}" 2>/dev/null || true
    fi
    wait "${PAPERCLIP_PID}" && EXIT_CODE=$? || EXIT_CODE=$?
  else
    EXIT_CODE=0
  fi
  echo "[zero-paperclip] Paperclip exited with code ${EXIT_CODE}"
  exit ${EXIT_CODE}
}

gosu node paperclipai run &
PAPERCLIP_PID=$!
trap cleanup SIGTERM SIGINT
wait "${PAPERCLIP_PID}" && EXIT_CODE=$? || EXIT_CODE=$?
echo "[zero-paperclip] Paperclip process exited with code ${EXIT_CODE}"
exit ${EXIT_CODE}
