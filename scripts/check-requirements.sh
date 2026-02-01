#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

MISSING=()

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING+=("$1")
  fi
}

need_cmd unzip
need_cmd tar
need_cmd sha256sum
need_cmd expect
need_cmd uuidgen

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  MISSING+=("curl/wget")
fi

if [[ ${#MISSING[@]} -eq 0 ]]; then
  exit 0
fi

echo "Missing requirements: ${MISSING[*]}" >&2

AUTO_INSTALL=${HT_AUTO_INSTALL_DEPS:-0}
PROMPT=${1:-}

can_install=0
if command -v apt-get >/dev/null 2>&1; then
  can_install=1
fi

if [[ $AUTO_INSTALL -eq 1 ]] && [[ $can_install -eq 1 ]]; then
  install=1
elif [[ "$PROMPT" == "--prompt" ]] && [[ $can_install -eq 1 ]]; then
  read -r -p "Install missing requirements via apt-get? (Y/n): " RESP
  RESP=${RESP:-Y}
  if [[ "${RESP}" =~ ^[Yy]$ ]]; then
    install=1
  else
    install=0
  fi
else
  install=0
fi

if [[ $install -eq 1 ]]; then
  "$ROOT_DIR/scripts/install-deps.sh"
  exit 0
fi

echo "Install the missing tools and re-run. You can set HT_AUTO_INSTALL_DEPS=1 to auto-install." >&2
exit 1
