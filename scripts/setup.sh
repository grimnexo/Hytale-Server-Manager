#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE_DIR="$ROOT_DIR/templates"
INSTANCE_ROOT="$ROOT_DIR/instances"

"$ROOT_DIR/scripts/check-requirements.sh" --prompt

read -r -p "Instance name (default: hytale): " INSTANCE_NAME
INSTANCE_NAME=${INSTANCE_NAME:-hytale}

read -r -p "Host port (default: 5520): " HOST_PORT
HOST_PORT=${HOST_PORT:-5520}

read -r -p "World name (default: default): " WORLD_NAME
WORLD_NAME=${WORLD_NAME:-default}

read -r -p "Server name (default: Hytale Server): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-Hytale Server}

read -r -p "MOTD (optional): " SERVER_MOTD

read -r -p "Password (optional): " SERVER_PASSWORD

read -r -p "Max players (default: 10): " MAX_PLAYERS
MAX_PLAYERS=${MAX_PLAYERS:-10}

INSTANCE_DIR="$INSTANCE_ROOT/$INSTANCE_NAME"

if [[ -d "${INSTANCE_DIR}" ]]; then
  read -r -p "Instance already exists. Overwrite it? (y/N): " OVERWRITE_FILES
  OVERWRITE_FILES=${OVERWRITE_FILES:-N}
  if [[ ! "${OVERWRITE_FILES}" =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
  fi
  rm -rf "${INSTANCE_DIR}"
fi

mkdir -p "$INSTANCE_DIR"/server "$INSTANCE_DIR"/mods "$INSTANCE_DIR"/data "$INSTANCE_DIR"/logs
if [[ ! -f "$INSTANCE_DIR/data/machine-id" ]]; then
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' > "$INSTANCE_DIR/data/machine-id"
  else
    cat /proc/sys/kernel/random/uuid | tr -d '-' | tr '[:upper:]' '[:lower:]' > "$INSTANCE_DIR/data/machine-id"
  fi
fi

sed \
  -e "s/__INSTANCE_NAME__/${INSTANCE_NAME}/g" \
  -e "s/__HOST_PORT__/${HOST_PORT}/g" \
  -e "s#__SERVER_URL__##g" \
  -e "s/__SERVER_SHA256__//g" \
  -e "s/__WORLD_NAME__/${WORLD_NAME}/g" \
  -e "s/__SERVICE_NAME__/${INSTANCE_NAME}/g" \
  "$TEMPLATE_DIR/instance.env" > "$INSTANCE_DIR/.env"

sed \
  -e "s/__SERVICE_NAME__/${INSTANCE_NAME}/g" \
  "$TEMPLATE_DIR/instance-compose.yml" > "$INSTANCE_DIR/docker-compose.yml"

"$ROOT_DIR/scripts/download.sh" "$INSTANCE_DIR"

CURRENT_CMD=$(grep -E '^HT_SERVER_CMD=' "$INSTANCE_DIR/.env" | cut -d= -f2- | tr -d '\r')
if [[ -z "$CURRENT_CMD" ]]; then
  if [[ -f "$INSTANCE_DIR/server/start.sh" ]]; then
    sed -i -E "s|^HT_SERVER_CMD=.*|HT_SERVER_CMD=./server/start.sh|" "$INSTANCE_DIR/.env"
  elif [[ -f "$INSTANCE_DIR/server/HytaleServer" ]]; then
    sed -i -E "s|^HT_SERVER_CMD=.*|HT_SERVER_CMD=./server/HytaleServer|" "$INSTANCE_DIR/.env"
  elif [[ -f "$INSTANCE_DIR/server/HytaleServer.sh" ]]; then
    sed -i -E "s|^HT_SERVER_CMD=.*|HT_SERVER_CMD=./server/HytaleServer.sh|" "$INSTANCE_DIR/.env"
  fi
fi

CONFIG_PATH="$INSTANCE_DIR/server/Server/config.json"
if [[ -f "$CONFIG_PATH" ]]; then
  python3 - "$CONFIG_PATH" "$SERVER_NAME" "$SERVER_MOTD" "$SERVER_PASSWORD" "$MAX_PLAYERS" <<'PY'
import json
import sys

path, name, motd, password, max_players = sys.argv[1:6]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

data["ServerName"] = name
data["MOTD"] = motd or ""
data["Password"] = password or ""
try:
    data["MaxPlayers"] = int(max_players)
except ValueError:
    pass

with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY
fi

cat <<EOF
Created instance: $INSTANCE_NAME
Path: $INSTANCE_DIR

Next steps:
1) Start with auth handling: cd "$ROOT_DIR" && ./hsm.sh manager start "$INSTANCE_NAME"
EOF
