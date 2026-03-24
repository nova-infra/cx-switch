#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

pkill -x CXSwitch 2>/dev/null || true
swift build
APP_EXEC="$(swift build --show-bin-path)/CXSwitch"
exec "$APP_EXEC"
