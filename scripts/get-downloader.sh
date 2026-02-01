#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
DEST_DIR="$ROOT_DIR/tools/hytale-downloader"

UPDATE=0
if [[ "${1:-}" == "--update" ]]; then
  UPDATE=1
fi

if [[ -x "$DEST_DIR/hytale-downloader" ]] && [[ $UPDATE -eq 0 ]]; then
  echo "Hytale downloader already present at $DEST_DIR"
  exit 0
fi

mkdir -p "$DEST_DIR"

TMP_DIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ZIP_PATH="$TMP_DIR/hytale-downloader.zip"

if command -v curl >/dev/null 2>&1; then
  curl -L --fail --silent --show-error -o "$ZIP_PATH" "$DOWNLOADER_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$ZIP_PATH" "$DOWNLOADER_URL"
else
  echo "Need curl or wget to download the Hytale downloader." >&2
  exit 1
fi

unzip -q "$ZIP_PATH" -d "$TMP_DIR/extract"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
esac

BIN_PATH=""
if [[ "$OS" == "linux" ]]; then
  BIN_PATH=$(find "$TMP_DIR/extract" -type f -iname "hytale-downloader*linux*${ARCH}*" | head -n 1 || true)
elif [[ "$OS" == "darwin" ]]; then
  BIN_PATH=$(find "$TMP_DIR/extract" -type f -iname "hytale-downloader*mac*${ARCH}*" -o -iname "hytale-downloader*darwin*${ARCH}*" | head -n 1 || true)
else
  BIN_PATH=$(find "$TMP_DIR/extract" -type f -iname "hytale-downloader*windows*${ARCH}*.exe" | head -n 1 || true)
fi

if [[ -z "$BIN_PATH" ]]; then
  BIN_PATH=$(find "$TMP_DIR/extract" -type f \( -iname "hytale-downloader" -o -iname "hytale-downloader.exe" -o -iname "hytale-downloader*" \) | head -n 1 || true)
fi

if [[ -z "$BIN_PATH" ]]; then
  FILE_COUNT=$(find "$TMP_DIR/extract" -type f | wc -l | tr -d ' ')
  if [[ "$FILE_COUNT" -eq 1 ]]; then
    BIN_PATH=$(find "$TMP_DIR/extract" -type f | head -n 1)
  fi
fi

if [[ -z "$BIN_PATH" ]]; then
  echo "Downloader binary not found in archive." >&2
  echo "Archive contents:" >&2
  find "$TMP_DIR/extract" -maxdepth 2 -type f >&2
  exit 1
fi

cp -a "$BIN_PATH" "$DEST_DIR/"
chmod +x "$DEST_DIR/hytale-downloader" 2>/dev/null || true

echo "Downloaded Hytale downloader to $DEST_DIR"
