#!/usr/bin/env bash
set -euo pipefail

mkdir -p /opt/hytale/mods /opt/hytale/data /opt/hytale/logs

if [[ -n "${HT_JAVA_OPTS:-}" ]]; then
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} ${HT_JAVA_OPTS}"
else
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Xms10G -Xmx10G"
fi

if [[ ! -d /opt/hytale/server ]]; then
  echo "Missing /opt/hytale/server (mount your server files)." >&2
  exit 1
fi

if [[ -n "${HT_SERVER_CMD:-}" ]]; then
  echo "Starting with HT_SERVER_CMD: $HT_SERVER_CMD"
  exec bash -lc "$HT_SERVER_CMD"
fi

if [[ -x /opt/hytale/server/HytaleServer ]]; then
  echo "Starting /opt/hytale/server/HytaleServer"
  exec /opt/hytale/server/HytaleServer
fi

if [[ -x /opt/hytale/server/HytaleServer.sh ]]; then
  echo "Starting /opt/hytale/server/HytaleServer.sh"
  exec /opt/hytale/server/HytaleServer.sh
fi

echo "No executable server entrypoint found. Set HT_SERVER_CMD in .env." >&2
exit 1
