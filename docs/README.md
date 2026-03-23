# zaaicom/paperclip-synology

**Zero-config [Paperclip](https://github.com/paperclipai/paperclip) Docker image for Synology NAS**

## What this is

A wrapper around Paperclip that auto-generates auth secrets and sets Synology-friendly defaults. No environment variables needed — just pull, create, and start.

## Quick Start (Synology Container Manager)

1. **Pull** `zaaicom/paperclip-synology:latest` from the Registry
2. **Create container** — set port `3100:3100` and mount volume `/volume1/docker/paperclip` → `/paperclip-workspace`
3. **Start** the container and open `http://<NAS_IP>:3100`

## Deployment Mode

This image runs in **authenticated** mode with **private** exposure. An admin account is bootstrapped automatically on first run — check `docker logs` for the invite URL.

Paperclip supports two deployment modes and two exposure levels:

| Setting | Value | Description | Alternative | Why not supported |
|---|---|---|---|---|
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` | Requires login, admin bootstrapped on first run | `local_trusted` — no auth | Binds to `127.0.0.1` only, unreachable from outside the container |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `private` | LAN/VPN, lenient origin checks | `public` — strict origin/hostname validation | Synology NAS typically runs on a home or office network |

## Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PAPERCLIP_PUBLIC_URL` | Auto-detected | Your NAS address, e.g. `http://192.168.1.50:3100`. Set this if accessing from other devices on your network |
| `BETTER_AUTH_SECRET` | Auto-generated and persisted | Override the auto-generated auth secret |
| `DATABASE_URL` | Embedded database | Connect to an external Postgres instead of embedded |

## How Updates Work

This image is rebuilt weekly from the latest Paperclip source. To update:

1. Re-pull `zaaicom/paperclip-synology:latest`
2. **Reset** the container in Container Manager

Your data in `/paperclip-workspace` is preserved across updates.

## License

MIT
