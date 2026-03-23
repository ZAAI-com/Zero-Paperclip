# paperclip-synology

Zero-config Docker image wrapper for [Paperclip](https://github.com/paperclipai/paperclip), optimized for Synology NAS deployments. Installs Paperclip from npm (`paperclipai@latest`), auto-generates auth secrets, and sets Synology-friendly defaults.

- **Docker Hub:** `zaaicom/paperclip-synology`
- **License:** MIT (ZAAI)
- **No application source code** — purely configuration and infrastructure

## Repository Structure

```
Dockerfile                              # Multi-arch Docker image (node:lts-trixie-slim base)
scripts/entrypoint.sh                   # Auth secret management, config generation, server start
.github/workflows/Publish-DockerHub.yml # CI/CD: multi-arch build, Docker Hub publish
docs/README.md                          # User-facing documentation
VERSION                                 # Bundle version (bump for wrapper changes)
.dockerignore                           # Excludes .git, .github, docs, *.md from build context
```

## Build and Test

```bash
# Build locally (single-arch)
docker build -t paperclip-synology:test .

# Run locally
docker run -p 3100:3100 -v paperclip-data:/paperclip-workspace paperclip-synology:test

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
- Log prefix: `echo "[paperclip-synology] ..."` for all user-facing messages
- Use `exec` for the final server process (replaces shell, proper signal handling)

### Dockerfile
- Descriptive comment at the top explaining the image purpose
- Inline comments explaining non-obvious decisions
- Separate `RUN` per global npm install for Docker layer caching
- Non-root execution: `USER node` at the end
- Build args `BUNDLE_VERSION` and `PAPERCLIP_VERSION` for image labeling

### Configuration (config.json)
- Minimal JSON with hardcoded values for authenticated/private deployment
- Secrets persisted to disk with `chmod 600`
- Environment variable defaults set in both Dockerfile (`ENV`) and entrypoint (`${VAR:-default}`)

## Architecture Decisions

1. **npm package, not source build:** Installs `paperclipai@latest` from npm. Faster builds, tracks stable releases.
2. **Embedded PostgreSQL:** Default database mode. Users can override with `DATABASE_URL` for external Postgres.
3. **Authenticated + private deployment:** Always runs in `authenticated` mode with `private` exposure. `local_trusted` binds to 127.0.0.1 (unreachable from outside container). `public` requires strict origin validation unsuitable for NAS LAN setups.
4. **Auto-generated auth secret:** `BETTER_AUTH_SECRET` generated on first run via `openssl rand -hex 32`, persisted to disk. Survives container restarts.
5. **Composite versioning:** Docker tags follow `<bundle-version>-<paperclip-version>` (e.g., `1.0.0-1.2.3`). `VERSION` file tracks the wrapper; Paperclip version queried from npm at CI build time.
6. **Weekly CI rebuilds:** GitHub Actions runs every Wednesday to pick up new upstream Paperclip releases.
7. **CLI tools bundled:** Image includes Claude Code, Codex, OpenCode, Gemini CLI, and Cursor Agent CLI for Paperclip's coding agent features.

## Environment Variables

| Variable | Default | Set In | Description |
|---|---|---|---|
| `BETTER_AUTH_SECRET` | Auto-generated | entrypoint.sh | Auth secret for sessions |
| `DATABASE_URL` | Embedded Postgres | User override | External Postgres connection string |
| `PAPERCLIP_PUBLIC_URL` | Auto-detected | User override | NAS address for network access |
| `PORT` | `3100` | Dockerfile + entrypoint | HTTP server port |
| `SERVE_UI` | `true` | Dockerfile + entrypoint | Serve the web UI |
| `PAPERCLIP_HOME` | `/paperclip-workspace/paperclip-home` | Dockerfile | Data directory |
| `PAPERCLIP_INSTANCE_ID` | `default` | Dockerfile | Instance identifier |
| `PAPERCLIP_CONFIG` | `.../instances/default/config.json` | Dockerfile | Config file path |

## Common Tasks

### Bump the wrapper version
Edit `VERSION` file (semver). Bump when changing Dockerfile, entrypoint, CI, or CLI tools.

### Add a new CLI tool
Add a `RUN npm install --global --omit=dev <package>@latest` line in the Dockerfile before the `COPY scripts/entrypoint.sh` line. Keep each tool on its own `RUN` line for layer caching.

### Change deployment defaults
Modify the generated config template in `scripts/entrypoint.sh` (the heredoc starting at `cat > "${CONFIG_FILE}"`).

### Update CI workflow
Edit `.github/workflows/Publish-DockerHub.yml`. Required secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`.
