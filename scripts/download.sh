#!/usr/bin/env bash
set -euo pipefail

INSTANCE_DIR=${1:-"$(pwd)"}
ENV_FILE="$INSTANCE_DIR/.env"
SERVER_DIR="$INSTANCE_DIR/server"
CLEAN=0
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
DOWNLOADER_DIR="$ROOT_DIR/tools/hytale-downloader"
DOWNLOADER_BIN="$DOWNLOADER_DIR/hytale-downloader"

"$ROOT_DIR/scripts/check-requirements.sh" --prompt

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

mkdir -p "$SERVER_DIR"

TMP_DIR=$(mktemp -d)
TMP_FILE="$TMP_DIR/download"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

is_truthy() {
  case "${1,,}" in
    1|true|yes|y) return 0 ;;
    *) return 1 ;;
  esac
}

if [[ -n "${HT_SERVER_URL:-}" ]]; then
  URL_NO_QUERY="${HT_SERVER_URL%%\?*}"
  BASENAME=$(basename "$URL_NO_QUERY")

  if [[ -n "$BASENAME" && "$BASENAME" != "/" ]]; then
    TMP_FILE="$TMP_DIR/$BASENAME"
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -L --fail --progress-bar -o "$TMP_FILE" "$HT_SERVER_URL"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$TMP_FILE" "$HT_SERVER_URL"
  else
    echo "Need curl or wget to download server files." >&2
    exit 1
  fi

  if [[ -n "${HT_SERVER_SHA256:-}" ]]; then
    echo "${HT_SERVER_SHA256}  $TMP_FILE" | sha256sum -c -
  fi
else
  if ! is_truthy "${HT_USE_DOWNLOADER:-1}"; then
    echo "HT_SERVER_URL is empty and HT_USE_DOWNLOADER is disabled in $ENV_FILE" >&2
    exit 1
  fi

  if [[ ! -x "$DOWNLOADER_BIN" ]]; then
    "$ROOT_DIR/scripts/get-downloader.sh"
  fi

  if [[ ! -x "$DOWNLOADER_BIN" ]]; then
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case "$ARCH" in
      x86_64|amd64) ARCH="amd64" ;;
      arm64|aarch64) ARCH="arm64" ;;
    esac
    if [[ "$OS" == "linux" ]]; then
      CANDIDATE=$(find "$DOWNLOADER_DIR" -type f -iname "hytale-downloader*linux*${ARCH}*" | head -n 1 || true)
    elif [[ "$OS" == "darwin" ]]; then
      CANDIDATE=$(find "$DOWNLOADER_DIR" -type f -iname "hytale-downloader*mac*${ARCH}*" -o -iname "hytale-downloader*darwin*${ARCH}*" | head -n 1 || true)
    else
      CANDIDATE=$(find "$DOWNLOADER_DIR" -type f -iname "hytale-downloader*windows*${ARCH}*.exe" | head -n 1 || true)
    fi
    if [[ -n "$CANDIDATE" ]]; then
      chmod +x "$CANDIDATE" 2>/dev/null || true
      DOWNLOADER_BIN="$CANDIDATE"
    fi
  fi

  if [[ ! -x "$DOWNLOADER_BIN" ]]; then
    echo "Hytale downloader not available. Check $DOWNLOADER_DIR" >&2
    exit 1
  fi

  if [[ "$(uname -s | tr '[:upper:]' '[:lower:]')" == "linux" ]] && [[ "$DOWNLOADER_BIN" == *.exe ]]; then
    echo "Found Windows downloader on Linux: $DOWNLOADER_BIN" >&2
    echo "Re-run: $ROOT_DIR/scripts/get-downloader.sh --update (ensure Linux binary exists in the archive)" >&2
    exit 1
  fi

  TMP_FILE="$TMP_DIR/game.zip"
  if [[ -n "${HT_DOWNLOADER_DOWNLOAD_PATH:-}" ]]; then
    TMP_FILE="${HT_DOWNLOADER_DOWNLOAD_PATH}"
    mkdir -p "$(dirname "$TMP_FILE")"
  fi
  DOWNLOADER_ARGS=()
  INFO_ONLY=0
  if is_truthy "${HT_DOWNLOADER_PRINT_VERSION:-0}"; then
    DOWNLOADER_ARGS+=("-print-version")
    INFO_ONLY=1
  fi
  if is_truthy "${HT_DOWNLOADER_CHECK_UPDATE:-0}"; then
    DOWNLOADER_ARGS+=("-check-update")
    INFO_ONLY=1
  fi
  if is_truthy "${HT_DOWNLOADER_VERSION:-0}"; then
    DOWNLOADER_ARGS+=("-version")
    INFO_ONLY=1
  fi
  if [[ -n "${HT_DOWNLOADER_PATCHLINE:-}" ]]; then
    DOWNLOADER_ARGS+=("-patchline" "$HT_DOWNLOADER_PATCHLINE")
  fi
  if is_truthy "${HT_DOWNLOADER_SKIP_UPDATE_CHECK:-0}"; then
    DOWNLOADER_ARGS+=("-skip-update-check")
  fi
  if [[ -n "${HT_DOWNLOADER_ARGS:-}" ]]; then
    # shellcheck disable=SC2206
    DOWNLOADER_ARGS+=(${HT_DOWNLOADER_ARGS})
  fi
  if [[ $INFO_ONLY -eq 1 ]]; then
    "$DOWNLOADER_BIN" "${DOWNLOADER_ARGS[@]}"
    exit 0
  fi

  "$DOWNLOADER_BIN" "${DOWNLOADER_ARGS[@]}" -download-path "$TMP_FILE"
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
