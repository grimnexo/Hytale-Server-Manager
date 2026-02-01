#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
  cat <<EOF
Hytale Server Manager (wrapper)

Usage: ./hsm.sh <command> [args...]

Commands:
  manager <args>    Run scripts/manager.sh (default)
  gui              Launch instance GUI (PyQt6)
  mod-gui          Launch mod tools GUI (PyQt6)
  install-deps     Install local dependencies (Debian/Ubuntu)
  setup            Run scripts/setup.sh
  build            Run scripts/build.sh
  download <inst>  Run scripts/download.sh <instance>
  auth <inst>      Run scripts/auth.sh <instance>
  help             Show this help
EOF
}

cmd=${1:-manager}
shift || true

case "$cmd" in
  manager)
    "$ROOT_DIR/scripts/manager.sh" "$@"
    ;;
  gui)
    python3 "$ROOT_DIR/gui/app.py"
    ;;
  mod-gui)
    python3 "$ROOT_DIR/mod_tools/app.py"
    ;;
  install-deps)
    "$ROOT_DIR/scripts/install-deps.sh"
    ;;
  setup)
    "$ROOT_DIR/scripts/setup.sh"
    ;;
  build)
    "$ROOT_DIR/scripts/build.sh"
    ;;
  download)
    "$ROOT_DIR/scripts/download.sh" "$@"
    ;;
  auth)
    "$ROOT_DIR/scripts/auth.sh" "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage
    exit 1
    ;;
esac
