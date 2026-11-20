#!/usr/bin/env bash
# Сборка десктопной версии на macOS (проверяет Xcode CLT, делает dmg + app.zip).
#
#   bash scripts/build-macos.sh [--clean] [--bundles dmg,app]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/build.sh" --desktop --install-deps "$@"
