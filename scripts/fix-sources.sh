#!/usr/bin/env bash
# Проверка (и при --restore восстановление из git) исходников Tauri.
# Bash-аналог fix.ps1 без 54 КБ base64-блобов и без записи паролей.
#
#   bash scripts/fix-sources.sh            # только проверить
#   bash scripts/fix-sources.sh --restore  # вернуть src-tauri/ к закоммиченной версии
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RESTORE=0
case "${1:-}" in
  ""|--check) ;;
  --restore|--fix) RESTORE=1 ;;
  -h|--help)
    sed -n '2,7p' "${BASH_SOURCE[0]}"
    exit 0 ;;
  *) die "Неизвестный аргумент: $1 (используйте --check или --restore)" ;;
esac

if [ "$RESTORE" -eq 1 ]; then
  need_cmd git
  git -C "$SB_ROOT" checkout -- \
    src-tauri/src/lib.rs \
    src-tauri/Cargo.toml \
    src-tauri/tauri.conf.json \
    src-tauri/build.rs
  ok "Исходники src-tauri восстановлены из git."
fi

fail=0
check_contains() {
  local file="$1" needle="$2" label="$3"
  if [ -f "$SB_ROOT/$file" ] && grep -qF -- "$needle" "$SB_ROOT/$file"; then
    ok "$label"
  else
    warn "Нет '$needle' в $file"
    fail=1
  fi
}
check_file() {
  if [ -f "$SB_ROOT/$1" ]; then ok "Файл $1 на месте"; else warn "Отсутствует $1"; fail=1; fi
}

log "Проверяем конфигурацию Tauri..."
check_contains src-tauri/src/lib.rs '#[cfg(desktop)]' 'lib.rs: desktop-код изолирован cfg'
check_contains src-tauri/src/lib.rs '#[cfg(mobile)]' 'lib.rs: mobile-код изолирован cfg'
check_contains src-tauri/src/lib.rs 'tauri::mobile_entry_point' 'lib.rs: mobile_entry_point присутствует'
check_contains src-tauri/Cargo.toml 'tray-icon' 'Cargo.toml: включён tray-icon'
check_contains src-tauri/build.rs 'tauri_build::build' 'build.rs: tauri-build подключён'
check_contains src-tauri/Cargo.toml 'strip = "debuginfo"' 'Cargo.toml: JNI-символы не вырезаются'
for icon in app-icon.png 32x32.png 128x128.png icon.ico icon.icns; do
  check_file "src-tauri/icons/$icon"
done

if command -v node >/dev/null 2>&1; then
  if (cd "$SB_ROOT" && node -e "const c=require('./src-tauri/tauri.conf.json'); if(!c.identifier||!c.version||!c.build) process.exit(1)"); then
    ok "tauri.conf.json валиден"
  else
    warn "tauri.conf.json невалиден или отсутствуют обязательные поля"
    fail=1
  fi
else
  check_file src-tauri/tauri.conf.json
fi

# Проверка безопасности: keystore и пароли приходят только из окружения.
# Никакой секрет в этот скрипт не вшит - см. README-BUILD.txt.
if git -C "$SB_ROOT" ls-files --error-unmatch keystore >/dev/null 2>&1; then
  warn "Каталог keystore попал в git! Удалите его из индекса и добавьте в .gitignore."
  fail=1
else
  ok "keystore не отслеживается git"
fi

if [ "$fail" -ne 0 ]; then
  die "Проверка не пройдена. Запустите: bash scripts/fix-sources.sh --restore"
fi
ok "Все проверки исходников пройдены."
