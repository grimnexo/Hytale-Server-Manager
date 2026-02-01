#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR=${1:-"$(pwd)"}

if [[ -d "$INSTANCE_DIR" ]]; then
  ENV_FILE="$INSTANCE_DIR/.env"
else
  echo "Instance directory not found: $INSTANCE_DIR" >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

CONTAINER_NAME=${HT_CONTAINER_NAME:-$(basename "$INSTANCE_DIR")}

if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "Container not found: $CONTAINER_NAME" >&2
  exit 1
fi

if docker exec -T "$CONTAINER_NAME" bash -lc 'printf "/auth persistence Encrypted\n" > /proc/1/fd/0'; then
  echo "Sent persistence command to $CONTAINER_NAME"
  exit 0
fi

echo "Failed to send persistence command automatically." >&2
echo "Attach and run manually:" >&2
echo "  /auth persistence Encrypted" >&2
exit 1
