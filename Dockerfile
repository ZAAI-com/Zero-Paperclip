# Dockerfile — zaaicom/paperclip-synology
# Builds Paperclip from source and wraps it with a zero-config entrypoint
# that auto-generates auth secrets for Synology NAS deployments.

# ── Stage 1: Build Paperclip from source ─────────────────────────────
FROM node:lts-trixie-slim AS upstream-build

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git openssl \
  && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /build
RUN git clone --depth 1 https://github.com/paperclipai/paperclip.git .

# Install dependencies
RUN pnpm install --frozen-lockfile

# Build UI and server (... suffix builds all workspace dependencies first)
RUN pnpm --filter @paperclipai/ui... build
RUN pnpm --filter @paperclipai/server... build
RUN test -f server/dist/index.js || (echo "ERROR: server build output missing" && exit 1)

# ── Stage 2: Production image ────────────────────────────────────────
FROM node:lts-trixie-slim AS production

# openssl is required at runtime for secret generation in entrypoint.sh
# locales is required for embedded PostgreSQL (needs en_US.UTF-8)
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl git openssl locales tzdata \
  && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
  && locale-gen \
  && rm -rf /var/lib/apt/lists/*
RUN corepack enable

WORKDIR /app
COPY --from=upstream-build /build /app

# Prepare workspace directories
RUN mkdir -p /paperclip-workspace/user-home /paperclip-workspace/paperclip-home \
  && chown -R node:node /paperclip-workspace

# Install global CLI tools
RUN npm install --global --omit=dev @anthropic-ai/claude-code@latest
RUN npm install --global --omit=dev @openai/codex@latest
RUN npm install --global --omit=dev opencode-ai
RUN npm install --global --omit=dev @google/gemini-cli
RUN curl https://cursor.com/install -fsS | bash

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
