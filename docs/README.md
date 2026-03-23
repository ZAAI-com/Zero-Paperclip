# zaaicom/paperclip-synology

**Zero-config [Paperclip](https://github.com/paperclipai/paperclip) Docker image for Synology NAS**

## What this is

A wrapper around Paperclip that auto-generates auth secrets and sets Synology-friendly defaults. No environment variables needed — just pull, create, and start.

## Quick Start (Synology Container Manager)

1. **Pull** `zaaicom/paperclip-synology:latest` from the Registry
2. **Create container** — set port `3100:3100` and mount volume `/volume1/docker/paperclip` → `/paperclip-workspace`
3. **Start** the container
4. **First run only** — check `docker logs` for the admin invite URL (or find it at `/volume1/docker/paperclip/paperclip-home/.bootstrap-url`)
5. Open `http://<NAS_IP>:3100` and use the invite URL to create your admin account

## Agent Working Directory

When setting up your first company/project in the Paperclip UI, you'll be prompted for a working directory where agents keep their memories and work on code. Enter:

    /paperclip-workspace/paperclip-working

This directory is pre-created inside the persistent volume and ready to use. On your Synology NAS filesystem, it maps to `/volume1/docker/paperclip/working` (or wherever you mounted the volume).

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
