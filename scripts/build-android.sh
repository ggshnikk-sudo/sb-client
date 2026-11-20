#!/usr/bin/env bash
# Сборка Android APK. Если доступны keystore + SB_KEYSTORE_PASSWORD — делается
# release-сборка и подпись; иначе — debug APK (без секретов, для smoketest/CI).
#
#   export SB_KEYSTORE_PASSWORD='...'   # из GitHub Secrets
#   bash scripts/build-android.sh [--targets aarch64,armv7] [--signed|--debug] [--ci]
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

TARGETS="aarch64,armv7"
FORCE_SIGNED=0
FORCE_DEBUG=0
CI_MODE=0
CLEAN=0
SKIP_SIGN=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --targets)   TARGETS="${2:?--targets требует список}"; shift ;;
    --signed)    FORCE_SIGNED=1 ;;
    --debug)     FORCE_DEBUG=1 ;;
    --ci)        CI_MODE=1 ;;
    --clean)     CLEAN=1 ;;
    --skip-sign) SKIP_SIGN=1 ;;
    -h|--help)   sed -n '2,7p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Неизвестный аргумент: $1" ;;
  esac
  shift
done

[ "$FORCE_SIGNED" -eq 1 ] && [ "$FORCE_DEBUG" -eq 1 ] && \
  die "Нельзя同时使用 --signed и --debug"

need_cmd node
need_cmd npm

if [ ! -x "$SB_ROOT/node_modules/.bin/tauri" ]; then
  log "Устанавливаем npm-зависимости..."
  (cd "$SB_ROOT" && npm ci --no-audit --no-fund)
fi

bash "$SB_ROOT/scripts/prepare-android.sh"

KEYSTORE="${SB_KEYSTORE_PATH:-$SB_ROOT/keystore/sbclient.jks}"
HAVE_KEY=0
if [ -f "$KEYSTORE" ] && [ -n "${SB_KEYSTORE_PASSWORD:-}" ]; then
  HAVE_KEY=1
fi

if [ "$FORCE_SIGNED" -eq 1 ] && [ "$HAVE_KEY" -eq 0 ]; then
  die "Требуется подпись, но нет keystore или SB_KEYSTORE_PASSWORD"
fi

if [ "$FORCE_DEBUG" -eq 1 ]; then
  MODE=debug
elif [ "$HAVE_KEY" -eq 1 ]; then
  MODE=release
else
  warn "Keystore/пароль не заданы — собираем debug APK (секреты не нужны)."
  MODE=debug
fi

ARGS=(android build --apk)
IFS=',' read -r -a target_list <<< "$TARGETS"
for target in "${target_list[@]}"; do
  [ -n "$target" ] || continue
  ARGS+=(--target "$target")
done
[ "$MODE" = debug ] && ARGS+=(--debug)
[ "$CI_MODE" -eq 1 ] && ARGS+=(--ci)

if [ "$CLEAN" -eq 1 ]; then
  log "Очищаем Android-артефакты..."
  rm -rf "$SB_ROOT/src-tauri/gen/android/app/build"
fi

log "Собираем Android ($MODE, targets: $TARGETS)..."
(cd "$SB_ROOT" && npx --no-install tauri "${ARGS[@]}")

if [ "$MODE" = release ] && [ "$SKIP_SIGN" -eq 0 ]; then
  bash "$SB_ROOT/scripts/sign-apk.sh"
else
  bash "$SB_ROOT/scripts/sign-apk.sh" --copy-only --allow-debug
fi

write_ready
list_dist
ok "Android-сборка завершена ($MODE)."
