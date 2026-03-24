#!/bin/bash
# detect-hostnames.sh — Auto-detect hostnames for the private hostname guard.
# Outputs a comma-separated list to stdout. Log messages go to stderr.
set -e

HOSTNAMES="localhost,DiskStation.local,RackStation.local"

# Add all non-loopback container IPs (works for host networking, macvlan, bridge)
DETECTED_IPS="$(hostname -I 2>/dev/null | xargs)"
if [ -n "${DETECTED_IPS}" ]; then
  for IP in ${DETECTED_IPS}; do
    HOSTNAMES="${HOSTNAMES},${IP}"
  done
  echo "[paperclip-synology] Auto-detected container IPs: ${DETECTED_IPS}" >&2
fi

# Extract hostname from PAPERCLIP_PUBLIC_URL if set
if [ -n "${PAPERCLIP_PUBLIC_URL}" ]; then
  PUBLIC_HOST="$(echo "${PAPERCLIP_PUBLIC_URL}" | sed -E 's|^https?://||; s|[:/].*||')"
  if [ -n "${PUBLIC_HOST}" ]; then
    HOSTNAMES="${HOSTNAMES},${PUBLIC_HOST}"
    echo "[paperclip-synology] Added public URL hostname: ${PUBLIC_HOST}" >&2
  fi
fi

echo "${HOSTNAMES}"
