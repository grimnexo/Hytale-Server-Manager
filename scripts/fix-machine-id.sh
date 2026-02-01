#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR=${1:-"$(pwd)"}
FILE="$INSTANCE_DIR/data/machine-id"

if [[ ! -d "$INSTANCE_DIR" ]]; then
  echo "Instance directory not found: $INSTANCE_DIR" >&2
  exit 1
fi

mkdir -p "$INSTANCE_DIR/data"

current=""
if [[ -f "$FILE" ]]; then
  current=$(tr -d '\r\n' < "$FILE")
fi

if [[ "$current" =~ ^[0-9a-fA-F]{32}$ ]]; then
  echo "machine-id already valid."
  exit 0
fi

if command -v uuidgen >/dev/null 2>&1; then
  uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' > "$FILE"
else
  cat /proc/sys/kernel/random/uuid | tr -d '-' | tr '[:upper:]' '[:lower:]' > "$FILE"
fi

echo "Wrote new machine-id to $FILE"
