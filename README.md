# Hytale Dedicated Server (Containerized)

This repo provides a lightweight Docker image and helper scripts to run a Hytale Dedicated Server inside a container.

Important: Hytale Dedicated Server binaries are not included. You must supply the server files yourself (see Quickstart).

## Quickstart

1) Build the image:

```bash
./scripts/build.sh
```

2) Create a new instance:

```bash
./scripts/setup.sh
```

3) Put your dedicated server files into the instance folder (example):

```
instances/<instance-name>/server/
```

4) Start the instance:

```bash
cd instances/<instance-name>
docker compose up -d
```

More detail: `docs/quickstart.md`

## Mods

See `docs/mods.md`

## Notes

- This image is a generic runner. It expects a server executable and command to be provided via `HT_SERVER_CMD`.
- Use unique instance names to run multiple servers at once.
