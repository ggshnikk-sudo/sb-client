#!/usr/bin/env bash
# Сборка десктопных бандлов для текущей Unix-ОС (Linux / macOS).
#
#   bash scripts/build-desktop.sh [--bundles deb,appimage] [--no-bundle] [--install-deps]
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUNDLES=""
NO_BUNDLE=0
CI_MODE=0
INSTALL_DEPS=0
CLEAN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundles)      BUNDLES="${2:?--bundles требует список}"; shift ;;
    --no-bundle)    NO_BUNDLE=1 ;;
    --ci)           CI_MODE=1 ;;
    --install-deps) INSTALL_DEPS=1 ;;
    --clean)        CLEAN=1 ;;
    -h|--help)      sed -n '2,5p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Неизвестный аргумент: $1" ;;
  esac
  shift
done

OS="$(os_name)"
[ "$OS" = windows ] && die "Для Windows используйте build.ps1 (PowerShell)"

if [ "$INSTALL_DEPS" -eq 1 ]; then
  if [ "$OS" = linux ]; then
    SUDO=""
    [ "$(id -u)" -eq 0 ] || SUDO="sudo"
    log "Устанавливаем системные зависимости (Linux)..."
    $SUDO apt-get update
    $SUDO apt-get install -y --no-install-recommends \
      build-essential curl wget file pkg-config \
      libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev \
      librsvg2-dev patchelf libxdo-dev libssl-dev
  else
    log "Проверяем Xcode Command Line Tools..."
    xcode-select -p >/dev/null || die "Сначала установите Xcode CLT: xcode-select --install"
  fi
fi

if [ ! -x "$SB_ROOT/node_modules/.bin/tauri" ]; then
  log "Устанавливаем npm-зависимости..."
  (cd "$SB_ROOT" && npm ci --no-audit --no-fund)
fi

if [ "$CLEAN" -eq 1 ]; then
  log "Очищаем target/release..."
  rm -rf "$SB_ROOT/src-tauri/target/release"
fi

case "$OS" in
  linux)  default_bundles="deb,appimage" ;;
  macos)  default_bundles="dmg,app" ;;
  *)      default_bundles="nsis,msi" ;;
esac
[ -n "$BUNDLES" ] || BUNDLES="$default_bundles"

args=(build)
if [ "$NO_BUNDLE" -eq 1 ]; then
  args+=(--no-bundle)
else
  args+=(--bundles "$BUNDLES")
fi
[ "$CI_MODE" -eq 1 ] && args+=(--ci)

log "Собираем десктоп ($OS): npx tauri ${args[*]}"
(cd "$SB_ROOT" && npx --no-install tauri "${args[@]}")

if [ "$NO_BUNDLE" -eq 0 ]; then
  collect_bundles || die "Не найдены готовые бандлы в $BUNDLE_DIR"
  write_ready
  list_dist
else
  ok "Smoke-сборка без бандлов завершена."
fi
