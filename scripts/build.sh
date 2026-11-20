#!/usr/bin/env bash
# Главный bash-скрипт сборки SB Client для Unix (Linux / macOS).
#
#   bash scripts/build.sh                       # desktop + android
#   bash scripts/build.sh --desktop             # только deb/AppImage или dmg/app
#   bash scripts/build.sh --android             # APK (debug без секретов, release с ними)
#   bash scripts/build.sh --check               # быстрая проверка без сборки
#   bash scripts/build-linux.sh                 # Linux: поставить зависимости и собрать desktop
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

DO_DESKTOP=0
DO_ANDROID=0
CI_MODE=0
CLEAN=0
CHECK_ONLY=0
NO_BUNDLE=0
BUNDLES=""
TARGETS=""

desktop_args=()
android_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --desktop)   DO_DESKTOP=1 ;;
    --android)   DO_ANDROID=1 ;;
    --all)       DO_DESKTOP=1; DO_ANDROID=1 ;;
    --check)     CHECK_ONLY=1 ;;
    --ci)        CI_MODE=1; desktop_args+=(--ci); android_args+=(--ci) ;;
    --clean)     CLEAN=1; desktop_args+=(--clean); android_args+=(--clean) ;;
    --no-bundle) NO_BUNDLE=1; desktop_args+=(--no-bundle) ;;
    --install-deps) desktop_args+=(--install-deps) ;;
    --bundles)   BUNDLES="${2:?--bundles требует список}"; shift
                 desktop_args+=(--bundles "$BUNDLES") ;;
    --targets)   TARGETS="${2:?--targets требует список}"; shift
                 android_args+=(--targets "$TARGETS") ;;
    --signed)    android_args+=(--signed) ;;
    --debug)     android_args+=(--debug) ;;
    --skip-sign) android_args+=(--skip-sign) ;;
    -h|--help)   sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Неизвестный аргумент: $1" ;;
  esac
  shift
done

if [ "$CHECK_ONLY" -eq 0 ] && [ "$DO_DESKTOP" -eq 0 ] && [ "$DO_ANDROID" -eq 0 ]; then
  DO_DESKTOP=1
  DO_ANDROID=1
fi

need_cmd node
need_cmd npm
need_cmd npx
need_cmd cargo

if [ ! -x "$SB_ROOT/node_modules/.bin/tauri" ] || [ "$CI_MODE" -eq 1 ]; then
  log "npm ci ..."
  (cd "$SB_ROOT" && npm ci --no-audit --no-fund)
else
  log "npm-зависимости уже установлены."
fi

log "Проверяем исходники..."
bash "$SB_ROOT/scripts/fix-sources.sh" --check

if [ "$CHECK_ONLY" -eq 1 ]; then
  (cd "$SB_ROOT" && cargo check --manifest-path src-tauri/Cargo.toml --locked)
  ok "Проверка завершена."
  exit 0
fi

if [ "$DO_DESKTOP" -eq 1 ]; then
  step 1 2 "Десктоп: $(os_name)"
  bash "$SB_ROOT/scripts/build-desktop.sh" "${desktop_args[@]}"
fi

if [ "$DO_ANDROID" -eq 1 ]; then
  step 2 2 "Android APK"
  bash "$SB_ROOT/scripts/build-android.sh" "${android_args[@]}"
fi

log "Итог сборки:"
list_dist
ok "Готово."
