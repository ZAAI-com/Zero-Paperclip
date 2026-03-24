# Dockerfile — zaaicom/paperclip-synology
# Installs Paperclip from npm and wraps it with a zero-config entrypoint
# that auto-generates auth secrets for Synology NAS deployments.

FROM node:lts-trixie-slim

ARG BUNDLE_VERSION
ARG PAPERCLIP_VERSION
LABEL org.opencontainers.image.version="${BUNDLE_VERSION}-${PAPERCLIP_VERSION}" \
      com.zaai.bundle-version="${BUNDLE_VERSION}" \
      com.zaai.paperclip-version="${PAPERCLIP_VERSION}"

# openssl is required at runtime for secret generation in entrypoint.sh
# gosu is required for dropping root to node user after volume setup
# locales is required for embedded PostgreSQL (needs en_US.UTF-8)
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl openssl gosu locales tzdata \
  && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*

# Install Paperclip from npm (stable release)
RUN PAPERCLIP_VERSION=${PAPERCLIP_VERSION:-$(npm view paperclipai version)} \
  && npm install --global --omit=dev paperclipai@${PAPERCLIP_VERSION}

# Prepare workspace directories
RUN mkdir -p /paperclip-workspace/user-home
RUN mkdir -p /paperclip-workspace/paperclip-home
RUN mkdir -p /paperclip-workspace/paperclip-working
RUN chown -R node:node /paperclip-workspace

# Install global CLI tools
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest
RUN npm install --global --omit=dev @openai/codex@latest
RUN npm install --global --omit=dev opencode-ai@latest
RUN npm install --global --omit=dev @google/gemini-cli
# Cursor Agent CLI: install via official script to /opt, symlink into PATH
# The installer creates a versioned directory with the binary + index.js + native modules;
# all files must stay together for the binary to work.
# Ref: https://cursor.com/docs/cli/installation
RUN export HOME=/tmp \
  && curl https://cursor.com/install -fsS | bash \
  && mv /tmp/.local/share/cursor-agent /opt/cursor-agent \
  && ln -s "$(ls -d /opt/cursor-agent/versions/*/cursor-agent)" /usr/local/bin/agent \
  && rm -rf /tmp/.local /tmp/.cursor

# Add our entrypoint wrapper
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
  && chown node:node /usr/local/bin/entrypoint.sh

ENV NODE_ENV=production \
  TZ=Europe/Berlin \
  HOME=/paperclip-workspace/user-home \
  HOST=0.0.0.0 \
  PORT=3100 \
  SERVE_UI=true \
  PAPERCLIP_HOME=/paperclip-workspace/paperclip-home \
  PAPERCLIP_INSTANCE_ID=default \
  PAPERCLIP_CONFIG=/paperclip-workspace/paperclip-home/instances/default/config.json \
  PAPERCLIP_ALLOWED_HOSTNAMES=localhost,DiskStation.local,RackStation.local,10.0.0.2,10.0.0.10,192.168.0.2,192.168.0.10,192.168.1.2,192.168.1.10,192.168.2.2,192.168.2.10,192.168.178.2,192.168.178.10

VOLUME ["/paperclip-workspace"]
EXPOSE 3100

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
