# zaaicom/paperclip-synology

**Zero-config [Paperclip](https://github.com/paperclipai/paperclip) Docker image for Synology NAS**

## What this is

A wrapper around Paperclip that auto-generates auth secrets and sets Synology-friendly defaults. No environment variables needed — just pull, create, and start.

## Quick Start (Synology Container Manager)

1. **Pull** `zaaicom/paperclip-synology:latest` from the Registry
2. **Create container** — set port `3100:3100` and mount volume `/volume1/docker/paperclip` → `/paperclip-workspace`
3. **Start** the container and open `http://<NAS_IP>:3100`

## Optional Environment Variables

| Variable | Description | Default |
|---|---|---|
| `BETTER_AUTH_SECRET` | Override the auto-generated auth secret | Auto-generated and persisted |
| `PAPERCLIP_PUBLIC_URL` | Set to your NAS IP/domain for external access | `http://localhost:3100` |
| `DATABASE_URL` | Connect to an external Postgres instead of embedded | Embedded database |

## How Updates Work

This image is rebuilt weekly from the latest Paperclip source. To update:

1. Re-pull `zaaicom/paperclip-synology:latest`
2. **Reset** the container in Container Manager

Your data in `/paperclip-workspace` is preserved across updates.

## License

MIT
