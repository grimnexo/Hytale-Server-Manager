#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR=${1:-"$(pwd)"}
COMPOSE_FILE="$INSTANCE_DIR/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Missing $COMPOSE_FILE (run from an instance folder or pass the path)." >&2
  exit 1
fi

cat <<EOF
Attaching to the Hytale server console.
Run: /auth login device
Then follow the OAuth link/code.

Detach without stopping the container: Ctrl-p Ctrl-q
EOF

docker compose -f "$COMPOSE_FILE" attach hytale
