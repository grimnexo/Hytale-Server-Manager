#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTANCE_DIR=${1:-"$(pwd)"}

if [[ ! -d "$INSTANCE_DIR" ]]; then
  echo "Instance directory not found: $INSTANCE_DIR" >&2
  exit 1
fi

BACKUP_DIR="$ROOT_DIR/backups"
mkdir -p "$BACKUP_DIR"

INSTANCE_NAME=$(basename "$INSTANCE_DIR")
TS=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/${INSTANCE_NAME}-${TS}.tar.gz"

tar -czf "$BACKUP_FILE" -C "$INSTANCE_DIR" .

echo "Backup created: $BACKUP_FILE"
