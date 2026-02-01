#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR=${1:-"$(pwd)"}
ENV_FILE="$INSTANCE_DIR/.env"
SERVER_DIR="$INSTANCE_DIR/server"
CLEAN=0

if [[ "${2:-}" == "--clean" ]]; then
  CLEAN=1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

if [[ -z "${HT_SERVER_URL:-}" ]]; then
  echo "HT_SERVER_URL is empty in $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$SERVER_DIR"

TMP_DIR=$(mktemp -d)
TMP_FILE="$TMP_DIR/download"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

URL_NO_QUERY="${HT_SERVER_URL%%\?*}"
BASENAME=$(basename "$URL_NO_QUERY")

if [[ -n "$BASENAME" && "$BASENAME" != "/" ]]; then
  TMP_FILE="$TMP_DIR/$BASENAME"
fi

if command -v curl >/dev/null 2>&1; then
  curl -L --fail -o "$TMP_FILE" "$HT_SERVER_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TMP_FILE" "$HT_SERVER_URL"
else
  echo "Need curl or wget to download server files." >&2
  exit 1
fi

if [[ -n "${HT_SERVER_SHA256:-}" ]]; then
  echo "${HT_SERVER_SHA256}  $TMP_FILE" | sha256sum -c -
fi

EXTRACT_DIR="$TMP_DIR/extract"
mkdir -p "$EXTRACT_DIR"

case "$TMP_FILE" in
  *.zip)
    unzip -q "$TMP_FILE" -d "$EXTRACT_DIR"
    ;;
  *.tar.gz|*.tgz)
    tar -xzf "$TMP_FILE" -C "$EXTRACT_DIR"
    ;;
  *.tar.xz|*.txz)
    tar -xJf "$TMP_FILE" -C "$EXTRACT_DIR"
    ;;
  *.tar)
    tar -xf "$TMP_FILE" -C "$EXTRACT_DIR"
    ;;
  *)
    echo "Unknown archive type. Placing file into server folder: $TMP_FILE" >&2
    cp -a "$TMP_FILE" "$SERVER_DIR/"
    exit 0
    ;;
 esac

if [[ $CLEAN -eq 1 ]]; then
  rm -rf "$SERVER_DIR"/*
fi

# If archive has a single top-level folder, copy its contents
TOP_LEVEL_COUNT=$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')
if [[ "$TOP_LEVEL_COUNT" -eq 1 ]] && [[ -d "$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1)" ]]; then
  EXTRACT_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1)"
fi

cp -a "$EXTRACT_DIR"/. "$SERVER_DIR"/

echo "Server files downloaded to $SERVER_DIR"
