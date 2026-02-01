# Hytale Dedicated Server (Containerized)

This repo provides a lightweight Docker image and helper scripts to run a Hytale Dedicated Server inside a container.

Important: Hytale Dedicated Server binaries are not included. You must supply the server files yourself (see Quickstart).

## Quickstart

1) Build the image (optional):

```bash
./hsm.sh build
```

Optional: install local dependencies (Debian/Ubuntu):

```bash
./hsm.sh install-deps
```

2) Create a new instance:

```bash
./hsm.sh setup
```

3) Start the instance:

```bash
./hsm.sh manager start <instance>
```

If the Docker image isn’t present locally, the manager will build it automatically before starting the instance.

Default server port is 5520 unless you override `HOST_PORT` in the instance `.env`.
Instance names are used as the default service name (`HT_SERVICE_NAME`). Set `HT_CONTAINER_NAME` if you need a specific container name override.

Setup also writes server settings (name, MOTD, password, max players) into `server/Server/config.json` before first start.

## CLI Manager

Use the project CLI to manage instances from the repo root:

```bash
./hsm.sh manager list
./hsm.sh manager setup
./hsm.sh manager start <instance>   # auto-triggers device auth if missing
./hsm.sh manager stop <instance>
./hsm.sh manager restart <instance>
./hsm.sh manager update <instance> [--no-backup]
./hsm.sh manager backup <instance>
./hsm.sh manager remove <instance> [--yes]
./hsm.sh manager status
```

Windows PowerShell wrapper:

```powershell
.\hsm.ps1 manager status
.\hsm.ps1 gui
```

More detail: `docs/quickstart.md`

## Mods

See `docs/mods.md`

## GUI (PyQt6)

A desktop GUI is available for managing local instances via Docker.

Setup:

```bash
python -m venv .venv
.venv\\Scripts\\activate
pip install -r gui/requirements.txt
```

Run:

```bash
./hsm.sh gui
```

Features:
- List instances from the `instances/` folder.
- Show container status from Docker.
- Start/stop/restart and view recent logs.
- Create new instance folders from the templates.

## Mod Tools (PyQt6)

A modder-focused GUI that scaffolds asset packs and plugin skeletons.

Setup:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r mod_tools/requirements.txt
```

Run:

```bash
./hsm.sh mod-gui
```

Docs:
- `docs/modding/overview.md`
- `docs/modding/asset-packs.md`
- `docs/modding/plugins.md`

## Notes

- This image is a generic runner. It expects a server executable and command to be provided via `HT_SERVER_CMD`.
- Setup will auto-detect `HT_SERVER_CMD` when possible (start.sh / HytaleServer / HytaleServer.sh).
- Use unique instance names to run multiple servers at once.
- The helper scripts can use the official Hytale Downloader utility to fetch/update server files. See `docs/quickstart.md`.
- Helper scripts will check for required CLI tools and can auto-install on Debian/Ubuntu with `HT_AUTO_INSTALL_DEPS=1`.
- The Docker image includes Adoptium Temurin Java for running the server.
- Default Java memory is set via `JAVA_TOOL_OPTIONS=-Xms10G -Xmx10G` inside the container. Override with `HT_JAVA_OPTS`.
- Container console access for `/auth` requires `stdin_open: true` (now in the template). See `docs/quickstart.md`.
- Each instance needs its own `/auth login device` flow; the manager handles this automatically.
- Automatic device-auth in the CLI manager requires `expect` on Linux.
- The compose template mounts a per-instance `data/machine-id` to keep encrypted auth persistence stable.
