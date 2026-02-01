# Quickstart

This project provides a generic container runner for a Hytale Dedicated Server. You must supply the server binaries yourself.

## Build the image

```bash
./scripts/build.sh
```

You can override the tag:

```bash
IMAGE_NAME=hytale-dedicated:latest ./scripts/build.sh
```

## Create a new instance

```bash
./scripts/setup.sh
```

This creates a folder under `instances/` with a unique name (base name + timestamp).

## Add server files

Copy your server files into:

```
instances/<instance-name>/server/
```

If your server requires a custom launch command, edit:

```
instances/<instance-name>/.env
```

Set `HT_SERVER_CMD` to whatever command you normally use to start the server.

## Start the server

```bash
cd instances/<instance-name>
docker compose up -d
```

## Stop the server

```bash
docker compose down
```

## Logs

```bash
docker compose logs -f
```

## Notes for Windows users

The helper scripts are bash. Use Git Bash or WSL to run them. You can also copy the templates manually if preferred.
