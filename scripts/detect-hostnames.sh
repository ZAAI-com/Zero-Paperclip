#!/bin/bash
# detect-hostnames.sh — Auto-detect hostnames for the private hostname guard.
# Outputs a comma-separated list to stdout. Log messages go to stderr.
set -e

HOSTNAMES=""

# --- Helper: add a hostname if not already present ---
add_hostname() {
  local HOST="$1"
  case ",${HOSTNAMES}," in
    *",${HOST},"*) return 1 ;;  # already present
    *) HOSTNAMES="${HOSTNAMES:+${HOSTNAMES},}${HOST}"; return 0 ;;
  esac
}

# --- Static defaults ---
add_hostname "localhost"
add_hostname "0.0.0.0"
add_hostname "DiskStation.local"
add_hostname "RackStation.local"

# --- Container IPs via hostname -I ---
DETECTED_IPS="$(hostname -I 2>/dev/null | xargs)"
if [ -n "${DETECTED_IPS}" ]; then
  for IP in ${DETECTED_IPS}; do
    add_hostname "${IP}"
  done
  echo "[zero-paperclip] Auto-detected container IPs: ${DETECTED_IPS}" >&2
fi

# --- Docker host IP via host.docker.internal ---
# Resolves to the host's actual LAN IP when the container is created with
# --add-host=host.docker.internal:host-gateway (Docker 20.10+) or
# automatically on Docker Engine 25+.
if GETENT_RESULT="$(getent hosts host.docker.internal 2>/dev/null)"; then
  DOCKER_HOST_IP="$(echo "${GETENT_RESULT}" | awk '{print $1}')"
  if [ -n "${DOCKER_HOST_IP}" ]; then
    add_hostname "${DOCKER_HOST_IP}"
    add_hostname "host.docker.internal"
    echo "[zero-paperclip] Resolved host.docker.internal → ${DOCKER_HOST_IP}" >&2
  fi
else
  echo "[zero-paperclip] host.docker.internal not resolvable (expected on bridge networking without --add-host)" >&2
fi

# --- Extract hostname from PAPERCLIP_PUBLIC_URL if set ---
if [ -n "${PAPERCLIP_PUBLIC_URL}" ]; then
  PUBLIC_HOST="$(echo "${PAPERCLIP_PUBLIC_URL}" | sed -E 's|^https?://||; s|[:/].*||')"
  if [ -n "${PUBLIC_HOST}" ]; then
    if add_hostname "${PUBLIC_HOST}"; then
      echo "[zero-paperclip] Added public URL hostname: ${PUBLIC_HOST}" >&2
    fi
  fi
fi

# --- Check if we likely lack the host's LAN IP ---
HAS_LAN_IP=false
IFS=',' read -ra HOST_ARRAY <<< "${HOSTNAMES}"
for H in "${HOST_ARRAY[@]}"; do
  case "${H}" in
    localhost|0.0.0.0|127.*|172.*|host.docker.internal|*.local) continue ;;
    *) HAS_LAN_IP=true; break ;;
  esac
done
if [ "${HAS_LAN_IP}" = false ]; then
  echo "[zero-paperclip] No LAN IP detected. If you access Paperclip from other devices," >&2
  echo "[zero-paperclip]   set PAPERCLIP_ALLOWED_HOSTNAMES=<your-NAS-IP> or PAPERCLIP_PUBLIC_URL=http://<your-NAS-IP>:${PORT:-3100}" >&2
fi

echo "${HOSTNAMES}"
