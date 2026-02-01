#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME=${IMAGE_NAME:-hytale-dedicated:latest}

docker build -t "$IMAGE_NAME" .
