#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTANCE_DIR=${1:-"$(pwd)"}
DO_BACKUP=1

if [[ "${2:-}" == "--no-backup" ]]; then
  DO_BACKUP=0
fi

if [[ ! -f "$INSTANCE_DIR/docker-compose.yml" ]]; then
  echo "docker-compose.yml not found in $INSTANCE_DIR" >&2
  exit 1
fi

if [[ $DO_BACKUP -eq 1 ]]; then
  "$ROOT_DIR/scripts/backup.sh" "$INSTANCE_DIR"
fi

(
  cd "$INSTANCE_DIR"
  docker compose down
)

"$ROOT_DIR/scripts/download.sh" "$INSTANCE_DIR" --clean

(
  cd "$INSTANCE_DIR"
  docker compose up -d
)

echo "Update complete."
