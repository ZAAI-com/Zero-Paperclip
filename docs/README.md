# zaaicom/paperclip-synology

**Zero-config [Paperclip](https://github.com/paperclipai/paperclip) Docker image for Synology NAS**

## What this is

A wrapper around Paperclip that auto-generates auth secrets and sets Synology-friendly defaults. No environment variables needed — just pull, create, and start.

## Quick Start (Synology Container Manager)

1. **Pull** `zaaicom/paperclip-synology:latest` from the Registry
2. **Create container** — set port `3100:3100` and mount volume `/volume1/docker/paperclip` → `/paperclip-workspace`
3. **Start** the container and open `http://<NAS_IP>:3100`

## Optional Environment Variables

| Variable | Default | Description |
|---|---|---|
| `PAPERCLIP_DEPLOYMENT_MODE` | `authenticated` | `authenticated` requires login (admin bootstrapped automatically on first run). `local` disables auth entirely — anyone with access can use it |
| `PAPERCLIP_DEPLOYMENT_EXPOSURE` | `private` | `private` for LAN/VPN (lenient origin checks). `public` for internet-facing (enforces origin validation, hostname allowlist, and requires `PAPERCLIP_PUBLIC_URL`) |
| `PAPERCLIP_PUBLIC_URL` | Auto-detected | Your NAS address, e.g. `http://192.168.1.50:3100`. Required when exposure is `public`. In `private` mode it is auto-detected |
| `BETTER_AUTH_SECRET` | Auto-generated and persisted | Override the auto-generated auth secret |
| `DATABASE_URL` | Embedded database | Connect to an external Postgres instead of embedded |

## How Updates Work

This image is rebuilt weekly from the latest Paperclip source. To update:

1. Re-pull `zaaicom/paperclip-synology:latest`
2. **Reset** the container in Container Manager

Your data in `/paperclip-workspace` is preserved across updates.

## License

MIT
