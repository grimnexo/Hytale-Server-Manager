# Mods

Because Hytale modding is evolving, this repo keeps mod handling flexible. The container exposes a `/opt/hytale/mods` folder for your mods, and the instance template maps it to:

```
instances/<instance-name>/mods/
```

## Basic workflow

1) Stop the server:

```bash
cd instances/<instance-name>
docker compose down
```

2) Add or update mod files in `instances/<instance-name>/mods/`.

3) Update your server configuration to load those mods (varies by mod loader / server version).

4) Start the server:

```bash
docker compose up -d
```

## Tips

- Keep mod archives and extracted folders under `mods/` as required by your loader.
- If your server expects mods in a different folder, update `HT_SERVER_CMD` or your server config to point at `/opt/hytale/mods`.
- If you want to bundle mods inside the image instead of mounting them, you can modify the Dockerfile and remove the `mods` volume.
