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
export PAPERCLIP_DEPLOYMENT_MODE="${PAPERCLIP_DEPLOYMENT_MODE:-authenticated}"
export PAPERCLIP_DEPLOYMENT_EXPOSURE="${PAPERCLIP_DEPLOYMENT_EXPOSURE:-private}"
export SERVE_UI="${SERVE_UI:-true}"
export PORT="${PORT:-3100}"

# --- Start the Paperclip server ---
exec node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js
