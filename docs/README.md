# zaaicom/zero-paperclip

**Zero-config [Paperclip](https://github.com/paperclipai/paperclip) Docker image for Synology NAS**

## What this is

A wrapper around Paperclip that auto-generates auth secrets and sets Synology-friendly defaults. No environment variables needed — just pull, create, and start.

## Quick Start (Synology Container Manager)

1. **Pull** `zaaicom/zero-paperclip:latest` from the Registry
2. **Create container** — set port `3100:3100` and mount volume `/volume1/docker/paperclip-workspace` → `/paperclip-workspace`
3. **Start** the container
4. **First run only** — check `docker logs` for the admin invite URL (or find it at `/volume1/docker/paperclip-workspace/paperclip-home/.bootstrap-url`)
5. Open `http://<NAS_IP>:3100` and use the invite URL to create your admin account

## Agent Working Directory

When setting up your first company/project in the Paperclip UI, you'll be prompted for a working directory where agents keep their memories and work on code. Enter:

    /paperclip-workspace/paperclip-working

This directory is pre-created inside the persistent volume and ready to use. On your Synology NAS filesystem, it maps to `/volume1/docker/paperclip-workspace/paperclip-working` (or wherever you mounted the volume).

## Deployment Mode

This image runs in **authenticated** mode with **private** exposure. An admin account is bootstrapped automatically on first run — check `docker logs` for the invite URL.

Paperclip supports two deployment modes and two exposure levels:

| Setting | Value | Description | Alternative | Why not supported |
|---|---|---|---|---|
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` | Requires login, admin bootstrapped on first run | `local_trusted` — no auth | Binds to `127.0.0.1` only, unreachable from outside the container |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `private` | LAN/VPN, lenient origin checks | `public` — strict origin/hostname validation | Synology NAS typically runs on a home or office network |

## Allowed Hostnames

Paperclip's private deployment mode validates the `Host` header of every request against an allowlist. On every start, the container auto-detects hostnames from multiple sources:

- `localhost`, `DiskStation.local`, `RackStation.local` (static defaults)
- Container IPs via `hostname -I`
- Docker host IP via `host.docker.internal` (if resolvable)
- Hostname extracted from `PAPERCLIP_PUBLIC_URL` (if set)

**Important:** With Docker bridge networking (Synology's default), `hostname -I` returns the container's internal IP (e.g. `172.17.0.3`), not your NAS LAN IP. To access Paperclip from other devices, set your NAS IP via one of these methods:

**Option 1** — Set `PAPERCLIP_PUBLIC_URL` (recommended, also fixes HTTP cookie issues):

    PAPERCLIP_PUBLIC_URL=http://192.168.1.50:3100

**Option 2** — Set `PAPERCLIP_ALLOWED_HOSTNAMES` (merged with auto-detected):

    PAPERCLIP_ALLOWED_HOSTNAMES=192.168.1.50,nas.local

Both are applied on every container start — update the variable and restart to add new hostnames.

## Bundled CLI Tools

This image includes the following coding agent CLI tools, ready to use with Paperclip's agent features:

- **Claude Code** (`@anthropic-ai/claude-code`)
- **Codex** (`@openai/codex`)
- **OpenCode** (`opencode-ai`)
- **Gemini CLI** (`@google/gemini-cli`)
- **GitHub Copilot CLI** (`@github/copilot`)
- **Cursor Agent CLI** (installed via `cursor.com/install`, available as `agent`)

No additional setup is required. Paperclip uses these tools automatically when running coding agent tasks. Each tool requires its own API key, configured through the Paperclip UI.

## Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PAPERCLIP_ALLOWED_HOSTNAMES` | Auto-detected | Additional hostnames for private mode (merged with auto-detected IPs). Comma-separated, e.g. `192.168.1.50,nas.local` |
| `PAPERCLIP_PUBLIC_URL` | `http://localhost:3100` | Your NAS address for network access. **Set this to your NAS LAN IP** (e.g. `http://192.168.1.50:3100`) if accessing from other devices |
| `BETTER_AUTH_SECRET` | Auto-generated and persisted | Override the auto-generated session auth secret |
| `PAPERCLIP_AGENT_JWT_SECRET` | Auto-generated and persisted | Override the auto-generated JWT secret for coding agents |
| `DATABASE_URL` | Embedded database | Connect to an external Postgres instead of embedded |
| `PORT` | `3100` | HTTP server port |
| `SERVE_UI` | `true` | Set to `false` to run in API-only mode without the web UI |

## Directory Structure

| Container Path | Synology Host Path | Description |
|---|---|---|
| `/paperclip-workspace` | `/volume1/docker/paperclip-workspace` | Volume root — all persistent data lives here |
| `/paperclip-workspace/user-home` | `/volume1/docker/paperclip-workspace/user-home` | `HOME` directory for the `node` user |
| `/paperclip-workspace/paperclip-home` | `/volume1/docker/paperclip-workspace/paperclip-home` | Paperclip data: database, config, secrets |
| `/paperclip-workspace/paperclip-home/instances/default/config.json` | `/volume1/docker/paperclip-workspace/paperclip-home/instances/default/config.json` | Auto-generated server config |
| `/paperclip-workspace/paperclip-home/.auth_secret` | `/volume1/docker/paperclip-workspace/paperclip-home/.auth_secret` | Persisted auth secret |
| `/paperclip-workspace/paperclip-home/.agent_jwt_secret` | `/volume1/docker/paperclip-workspace/paperclip-home/.agent_jwt_secret` | Persisted agent JWT secret |
| `/paperclip-workspace/paperclip-working` | `/volume1/docker/paperclip-workspace/paperclip-working` | Agent working directory (set this in the Paperclip UI) |

Host paths assume the default volume mount `/volume1/docker/paperclip-workspace` → `/paperclip-workspace`.

## How Updates Work

This image is rebuilt weekly from the latest Paperclip npm release. To update:

1. Re-pull `zaaicom/zero-paperclip:latest`
2. **Reset** the container in Container Manager

Your data in `/paperclip-workspace` is preserved across updates.

## Accessing the Container Shell

The entrypoint runs as root (to fix volume permissions), then drops to the `node` user to run Paperclip via `gosu`. To get a shell as the same user Paperclip runs under:

```bash
docker exec -u node -it <container-name-or-id> bash
```

From there you can run `paperclipai` CLI commands directly (e.g. `paperclipai allowed-hostname <host>`).

If you're already inside the container as root, switch with:

```bash
gosu node bash
```

## Troubleshooting

### "Hostname 'x.x.x.x' is not allowed"

Your NAS LAN IP is not in Paperclip's hostname allowlist. Check container logs for the line starting with `Final allowed hostnames:` to see what was detected.

**Fix:** Set `PAPERCLIP_PUBLIC_URL=http://<your-NAS-IP>:3100` in the container's environment variables and restart.

### Container stops unexpectedly (database shutdown errors)

If you see `the database system is shutting down` in logs, something sent a stop signal to the container. Check:

1. **Memory limit** — In Container Manager > Container > Settings > Resources, ensure at least **2 GB RAM**. "Unlimited" is recommended.
2. **OOM kill** — Run `docker inspect <container-id> | grep OOMKilled` on the NAS via SSH.
3. **Synology Resource Monitor** — Check for high memory usage around the time of the crash.

## License

MIT
