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
# locales is required for embedded PostgreSQL (needs en_US.UTF-8)
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl openssl locales tzdata \
  && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*

# Install Paperclip from npm (stable release)
RUN PAPERCLIP_VERSION=${PAPERCLIP_VERSION:-$(npm view paperclipai version)} \
  && npm install --global --omit=dev paperclipai@${PAPERCLIP_VERSION}

# Prepare workspace directories
RUN mkdir -p /paperclip-workspace/user-home /paperclip-workspace/paperclip-home \
  && chown -R node:node /paperclip-workspace

# Install global CLI tools
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest
RUN npm install --global --omit=dev @openai/codex@latest
RUN npm install --global --omit=dev opencode-ai@latest
RUN npm install --global --omit=dev @google/gemini-cli
# Cursor CLI: only available for x86_64; install to a system-wide location accessible by the node user
RUN if [ "$(uname -m)" = "x86_64" ]; then \
      export HOME=/tmp \
      && curl https://cursor.com/install -fsS | bash \
      && if [ -f /tmp/.cursor/bin/cursor ]; then \
           cp /tmp/.cursor/bin/cursor /usr/local/bin/cursor \
           && chmod 755 /usr/local/bin/cursor; \
         fi \
      && rm -rf /tmp/.cursor; \
    fi

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
  PAPERCLIP_CONFIG=/paperclip-workspace/paperclip-home/instances/default/config.json

VOLUME ["/paperclip-workspace"]
EXPOSE 3100

USER node
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
