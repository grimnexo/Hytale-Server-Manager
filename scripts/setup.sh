#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEMPLATE_DIR="$ROOT_DIR/templates"
INSTANCE_ROOT="$ROOT_DIR/instances"

read -r -p "Instance base name (default: hytale): " BASE_NAME
BASE_NAME=${BASE_NAME:-hytale}

read -r -p "Host port (default: 25565): " HOST_PORT
HOST_PORT=${HOST_PORT:-25565}

read -r -p "Server download URL (optional): " SERVER_URL
read -r -p "Server SHA256 checksum (optional): " SERVER_SHA256

TS=$(date +%Y%m%d-%H%M%S)
INSTANCE_NAME="${BASE_NAME}-${TS}"
INSTANCE_DIR="$INSTANCE_ROOT/$INSTANCE_NAME"

mkdir -p "$INSTANCE_DIR"/server "$INSTANCE_DIR"/mods "$INSTANCE_DIR"/data "$INSTANCE_DIR"/logs

sed \
  -e "s/__INSTANCE_NAME__/${INSTANCE_NAME}/g" \
  -e "s/__HOST_PORT__/${HOST_PORT}/g" \
  -e "s#__SERVER_URL__#${SERVER_URL}#g" \
  -e "s/__SERVER_SHA256__/${SERVER_SHA256}/g" \
  "$TEMPLATE_DIR/instance.env" > "$INSTANCE_DIR/.env"

cp "$TEMPLATE_DIR/instance-compose.yml" "$INSTANCE_DIR/docker-compose.yml"

if [[ -n "${SERVER_URL}" ]]; then
  read -r -p "Download server files now? (Y/n): " DO_DOWNLOAD
  DO_DOWNLOAD=${DO_DOWNLOAD:-Y}
  if [[ "${DO_DOWNLOAD}" =~ ^[Yy]$ ]]; then
    "$ROOT_DIR/scripts/download.sh" "$INSTANCE_DIR"
  fi
fi

cat <<EOF
Created instance: $INSTANCE_NAME
Path: $INSTANCE_DIR

Next steps:
1) Put server files into: $INSTANCE_DIR/server
2) Start: cd "$INSTANCE_DIR" && docker compose up -d
EOF
