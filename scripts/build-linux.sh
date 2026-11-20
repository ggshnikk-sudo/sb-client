#!/usr/bin/env bash
# Сборка десктопной версии на Linux: ставит системные зависимости (sudo/apt)
# и собирает deb + AppImage в dist/.
#
#   bash scripts/build-linux.sh [--clean] [--bundles deb,appimage]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build.sh" --desktop --install-deps "$@"
