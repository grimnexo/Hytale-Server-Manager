# Quickstart

This project provides a generic container runner / interface for a Hytale Dedicated Server (or many).
Using the `./hsm.{sh|ps1} setup` command you can create a new instance.

This will prompt you for some inputs to configure the instance, and if you need to do more you'll need to manually edit the instance files.

> NOTE: If you have *not* run the setup before, you'll need to authorize your actual machine for downloading the base Hytale server image. This is normal. You will get a `.hytale-downloader.credentials.json` file in the project root with an access token - this is for the downloader to pull images as needed, although it might need to be reauthorized (by deleting the file) if it expires and doesn't auto-renew.

> You will *ALSO* need to authorize each instance, but a link is auto-generated and provided during setup for that as well (and instances are treated as their own machine, so you shouldn't need to reauth them often / if-ever - especially if they run non-stop).

After that, you can start it using `./hsm.{sh|ps1} manager start <instance-name>`.
This will prompt you for auth if required (as it is for every new server that gets spun up).

Click the link to authorize the server, then return and give it ~30 seconds.
Your server should now be up and running!

You'll get the IP locally, but if you need network forwarding / DNS masking that's on you.

(no-ip is great!)

## Build the image
This is not necessary for basic installs - it's related to the modding programs that are being developed alongside this.

When you need to build the docker image for the project, you can run:

```bash
./hsm.sh build
```

You can override the tag for the base image (if you need to for some reason):

```bash
IMAGE_NAME=hytale-dedicated:latest ./scripts/build.sh
```

Hytale recommends using Adoptium, so that is what's automatically bundled with the images.

The image installs Adoptium Temurin Java (from the official Adoptium apt repo) so `java` is available inside the container.

Required: install local dependencies (Debian/Ubuntu):

> * This is automatically handled during `setup` if you are missing any dependencies.*

```bash
./hsm.sh install-deps
```

## Create a new instance (Usually, you'll start here)

```bash
./hsm.sh setup
```

This creates a folder under `instances/` with the instance name you choose, generates a per-instance `machine-id`, and fetches server files via the Hytale Downloader CLI.

Setup will prompt for server name, MOTD, password (optional), and max players. These values are written to `server/Server/config.json` before first start.

If your server requires a custom launch command, edit:

```
instances/<instance-name>/.env
```

Set `HT_SERVER_CMD` to whatever command you normally use to start the server.

If `HT_SERVER_CMD` is empty, setup will try to auto-detect `./server/start.sh`, `./server/HytaleServer`, or `./server/HytaleServer.sh`.

World name: `WORLD_NAME` is stored in the instance `.env` for now (used by tooling). If you want to apply it inside the server, set a custom `HT_SERVER_CMD` that passes the name to your server start script (if supported).

Default port: `5520` (adjust `HOST_PORT` if you need a different bind).

Instance names are used as the default service name (`HT_SERVICE_NAME`). Set `HT_CONTAINER_NAME` if you need a specific container name override.

## Hytale Downloader (Recommended)

Hytale provides an official downloader utility that can fetch or update server files. This repo will download it automatically the first time it is needed and cache it under `tools/hytale-downloader/`.

To use the downloader:

1) Leave `HT_SERVER_URL` empty in your instance `.env`.
2) Keep `HT_USE_DOWNLOADER=1` (default in the template).
3) Run `./hsm.sh manager update <instance>` when you want to fetch or update server files.

Optional `.env` controls:
- `HT_DOWNLOADER_PATCHLINE` to target a specific patchline.
- `HT_DOWNLOADER_ARGS` for extra CLI flags (space-separated).
- `HT_DOWNLOADER_SKIP_UPDATE_CHECK=1` to skip downloader update checks.
- `HT_DOWNLOADER_PRINT_VERSION=1` to print the game version without downloading.
- `HT_DOWNLOADER_CHECK_UPDATE=1` to check for downloader updates.
- `HT_DOWNLOADER_VERSION=1` to print downloader version.
- `HT_DOWNLOADER_DOWNLOAD_PATH=/path/to/game.zip` to control output file location.
Environment:
- `HT_AUTO_INSTALL_DEPS=1` to auto-install required CLI tools (apt-get only).
Auth automation:
- `expect` is required for fully automatic device-auth in the CLI manager.

Notes:
- The downloader uses OAuth authentication and may prompt you to log in the first time it runs.
- The downloader supports printing the game version, checking for downloader updates, and skipping update checks.

Common CLI options (reference):
- `-print-version` show game version without downloading
- `-version` show downloader version
- `-check-update` check for downloader updates
- `-download-path <file>` download to a specific file
- `-patchline <name>` download from a patchline (e.g., `pre-release`)
- `-skip-update-check` skip automatic update checks

To use those with this repo, set these `.env` fields:
- `HT_DOWNLOADER_PRINT_VERSION=1`
- `HT_DOWNLOADER_VERSION=1`
- `HT_DOWNLOADER_CHECK_UPDATE=1`
- `HT_DOWNLOADER_DOWNLOAD_PATH=/path/to/game.zip`
- `HT_DOWNLOADER_SKIP_UPDATE_CHECK=1`

Reference:
- https://support.hytale.com/hc/en-us/articles/45326769420827-Hytale-Server-Manual#server-setup

## Start the server

```bash
./hsm.sh manager start <instance>
```

You can also use the project CLI from the repo root:

```bash
./hsm.sh manager list
./hsm.sh manager setup
./hsm.sh manager start <instance>   # auto-triggers device auth if missing
./hsm.sh manager stop <instance>
./hsm.sh manager restart <instance>
./hsm.sh manager update <instance> [--no-backup]
./hsm.sh manager backup <instance>
./hsm.sh manager remove <instance> [--yes]
./hsm.sh manager status   # includes last auth + expected expiry (if available)
```

## Authenticate the server (OAuth device login)

On first launch, authentication is handled by the manager. Run:

```bash
./hsm.sh manager start <instance>
```

If auth is required, the manager will print a one-click verification link, wait for success, then set encrypted persistence automatically.

If you created an instance before this change, ensure `stdin_open: true` is set in its `docker-compose.yml` (so console input is accepted).

Note: each containerized instance requires its own authentication session.

If you see "Failed to get Hardware UUID" in logs or encrypted persistence doesn't stick, ensure the per-instance machine-id is mounted and valid (32 lowercase hex chars). The template mounts `./data/machine-id` to `/etc/machine-id` automatically for new instances. You can repair an instance with:

```bash
./scripts/fix-machine-id.sh instances/<instance-name>
```

Helpful links (log in before starting the device flow):
- https://accounts.hytale.com/
- https://accounts.hytale.com/registration

If you hit a 403 at the device auth step, try:
- Confirm your account can access Hytale services.
- Use a network without strict corporate filtering.

## Stop the server

```bash
./hsm.sh manager stop <instance>
```

## Logs

```bash
./hsm.sh manager logs <instance>
```

## Notes for Windows users

The helper scripts are bash. Use Git Bash or WSL to run them. You can also copy the templates manually if preferred.
