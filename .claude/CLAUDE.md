# Zero-Paperclip

Zero-config Docker image wrapper for [Paperclip](https://github.com/paperclipai/paperclip), optimized for Synology NAS deployments. Installs Paperclip from npm (`paperclipai@latest`), auto-generates auth secrets, and sets Synology-friendly defaults.

- **Docker Hub:** `zaaicom/zero-paperclip`
- **License:** MIT (ZAAI)
- **No application source code** — purely configuration and infrastructure

## Repository Structure

```
Dockerfile                              # Multi-arch Docker image (node:lts-trixie-slim base)
scripts/entrypoint.sh                   # Auth secrets management, config generation, server start
scripts/detect-hostnames.sh             # Auto-detect container IPs for private hostname guard
.github/workflows/Publish-DockerHub.yml # CI/CD: multi-arch build, Docker Hub publish
docs/README.md                          # User-facing documentation
VERSION                                 # Bundle version (bump for wrapper changes)
LICENSE                                 # MIT license
.gitignore                              # Excludes node_modules, .env, logs, .DS_Store
.dockerignore                           # Excludes .git, .github, .context, .claude, docs, LICENSE, *.md from build context
```

## Build and Test

```bash
# Build locally (single-arch)
docker build -t zero-paperclip:test .

# Run locally
docker run -p 3100:3100 -v paperclip-data:/paperclip-workspace zero-paperclip:test

# Check first-run output (admin invite URL appears in logs)
docker logs <container-id>

# Verify the server is running
curl http://localhost:3100
```

No unit tests, linters, or formatters are configured. Verification is done by building and running the Docker image.

## Coding Conventions

### Bash (entrypoint.sh)
- `set -e` at the top of every script
- UPPERCASE for all variable names: `PAPERCLIP_HOME`, `SECRET_FILE`, `CONFIG_FILE`
- Always double-quote variable expansions: `"${VAR}"`
- Log prefix: `echo "[zero-paperclip] ..."` for all user-facing messages
- Use `trap`/`wait` for the final server process (forward signals to the background child for graceful shutdown)

### Dockerfile
- Descriptive comment at the top explaining the image purpose
- Inline comments explaining non-obvious decisions
- Separate `RUN` per global npm install for Docker layer caching
- Non-root execution: entrypoint runs as root for volume setup, then drops to `node` via `gosu`
- Build args `BUNDLE_VERSION` and `PAPERCLIP_VERSION` for image labeling

### Configuration (config.json)
- Minimal JSON with hardcoded values for authenticated/private deployment
- Secrets persisted to disk with `chmod 600`
- Environment variable defaults set in both Dockerfile (`ENV`) and entrypoint (`${VAR:-default}`)

## Architecture Decisions

1. **npm package, not source build:** Installs `paperclipai@latest` from npm. Faster builds, tracks stable releases.
2. **Embedded PostgreSQL:** Default database mode. Users can override with `DATABASE_URL` for external Postgres.
3. **Authenticated + private deployment:** Always runs in `authenticated` mode with `private` exposure. `local_trusted` binds to 127.0.0.1 (unreachable from outside container). `public` requires strict origin validation unsuitable for NAS LAN setups.
4. **Auto-generated auth secrets:** `BETTER_AUTH_SECRET` and `PAPERCLIP_AGENT_JWT_SECRET` each generated on first run via `openssl rand -hex 32`, persisted to disk (`.auth_secret` and `.agent_jwt_secret` respectively). Survive container restarts.
5. **Composite versioning:** Docker tags follow `<bundle-version>-<paperclip-version>` (e.g., `1.0.0-1.2.3`). `VERSION` file tracks the wrapper; Paperclip version queried from npm at CI build time.
6. **Weekly CI rebuilds:** GitHub Actions runs every Wednesday to pick up new upstream Paperclip releases.
7. **CLI tools bundled:** Image includes git, GitHub CLI (`gh`), Claude Code, Codex, OpenCode, Gemini CLI, GitHub Copilot CLI, and Cursor Agent CLI for Paperclip's coding agent features.
8. **Auth base URL auto-detection:** Config uses `baseUrlMode: auto` so Paperclip resolves the auth base URL dynamically, avoiding hard-coded hostnames that break across different NAS network setups.

## Environment Variables

| Variable | Default | Set In | Description |
|---|---|---|---|
| `BETTER_AUTH_SECRET` | Auto-generated | entrypoint.sh | Auth secret for sessions |
| `PAPERCLIP_AGENT_JWT_SECRET` | Auto-generated | entrypoint.sh | JWT secret for coding agent sessions |
| `DATABASE_URL` | Embedded Postgres | User override | External Postgres connection string |
| `PAPERCLIP_PUBLIC_URL` | Auto-detected | User override | NAS address for network access |
| `NODE_ENV` | `production` | Dockerfile | Node.js environment mode |
| `TZ` | `Europe/Berlin` | Dockerfile | Container timezone |
| `HOME` | `/paperclip-workspace/user-home` | Dockerfile | User home directory (inside volume for persistence) |
| `HOST` | `0.0.0.0` | Dockerfile | Server bind address |
| `PORT` | `3100` | Dockerfile + entrypoint | HTTP server port |
| `SERVE_UI` | `true` | Dockerfile + entrypoint | Serve the web UI |
| `PAPERCLIP_HOME` | `/paperclip-workspace/paperclip-home` | Dockerfile | Data directory |
| `PAPERCLIP_INSTANCE_ID` | `default` | Dockerfile | Instance identifier |
| `PAPERCLIP_CONFIG` | `.../instances/default/config.json` | Dockerfile | Config file path |
| `PAPERCLIP_ALLOWED_HOSTNAMES` | Auto-detected | detect-hostnames.sh | Additional comma-separated hostnames; merged with auto-detected IPs from `hostname -I` |

## Common Tasks

### Bump the wrapper version
Edit `VERSION` file (semver). Bump when changing Dockerfile, entrypoint, CI, or CLI tools.

### Add a new CLI tool
Add a `RUN npm install --global --omit=dev <package>@latest` line in the Dockerfile before the `COPY scripts/entrypoint.sh` line. Keep each tool on its own `RUN` line for layer caching. Note: not all packages support `@latest` (e.g., `@google/gemini-cli` omits it) — check the package's recommended install command.

### Change deployment defaults
Modify the generated config template in `scripts/entrypoint.sh` (the heredoc starting at `cat > "${CONFIG_FILE}"`).

### Update CI workflow
Edit `.github/workflows/Publish-DockerHub.yml`. Required secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.
