#!/usr/bin/env bash
# Общие функции для bash-скриптов SB Client (Linux / macOS / Git Bash).
# Не запускать напрямую.

set -euo pipefail

SB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SB_ROOT

DIST_DIR="$SB_ROOT/dist"
BUNDLE_DIR="$SB_ROOT/src-tauri/target/release/bundle"

C='\033[1;36m'; Y='\033[1;33m'; R='\033[1;31m'; G='\033[1;32m'; Z='\033[0m'

log()  { printf '%s==>%s %s\n' "$C" "$Z" "$*"; }
ok()   { printf '%s OK %s %s\n' "$G" "$Z" "$*"; }
warn() { printf '%s[!]%s %s\n' "$Y" "$Z" "$*" >&2; }
die()  { printf '%sERR%s %s\n' "$R" "$Z" "$*" >&2; exit 1; }
step() { printf '\n%s=== [%s/%s] %s ===%s\n' "$C" "$1" "$2" "$3" "$Z"; }

run() {
  printf '+ '; printf '%q ' "$@"; printf '\n'
  "$@"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"
}

os_name() {
  case "$(uname -s)" in
    Linux*)  echo linux ;;
    Darwin*) echo macos ;;
    MINGW*|MSYS*|CYGWIN*) echo windows ;;
    *) die "Неподдерживаемая ОС: $(uname -s)" ;;
  esac
}

sb_version() {
  (
    cd "$SB_ROOT"
    if command -v node >/dev/null 2>&1; then
      node -p "require('./src-tauri/tauri.conf.json').version"
    else
      sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        src-tauri/tauri.conf.json | head -n 1
    fi
  )
}

ensure_dist() {
  mkdir -p "$DIST_DIR"
  rm -f "$DIST_DIR/FAILED.txt"
}

# Копирует готовые бандлы в dist/; возвращает 0, если скопирован хотя бы один файл.
collect_bundles() {
  local copied=0 pattern file base target app zip_name
  ensure_dist

  for pattern in \
    'nsis/*.exe' 'msi/*.msi' 'deb/*.deb' 'appimage/*.AppImage' \
    'rpm/*.rpm' 'dmg/*.dmg'; do
    for file in "$BUNDLE_DIR"/$pattern; do
      [ -f "$file" ] || continue
      cp -f "$file" "$DIST_DIR/"
      copied=1
    done
  done

  # macOS .app удобно отдавать одним zip-архивом.
  for app in "$BUNDLE_DIR"/macos/*.app; do
    [ -d "$app" ] || continue
    zip_name="SB-Client-v$(sb_version)-macos-app.zip"
    rm -f "$DIST_DIR/$zip_name"
    (cd "$(dirname "$app")" && zip -qry "$DIST_DIR/$zip_name" "$(basename "$app")")
    copied=1
    break
  done

  # Портативный бинарник (для пользователей без прав установщика).
  local bin="sb-client"
  [ "$(os_name)" = windows ] && bin="sb-client.exe"
  if [ -f "$SB_ROOT/src-tauri/target/release/$bin" ]; then
    target="$DIST_DIR/SB-Client-v$(sb_version)-$(os_name)-bin${bin#sb-client}"
    cp -f "$SB_ROOT/src-tauri/target/release/$bin" "$target"
    copied=1
  fi

  return $(( 1 - copied ))
}

write_ready() {
  local ready="$DIST_DIR/READY.txt"
  {
    echo "SB Client - build finished: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Version: $(sb_version)"
    echo
    echo "Artifacts:"
    (cd "$DIST_DIR" && ls -lh 2>/dev/null | tail -n +2 || true)
    echo
    echo "Android: установите APK и разрешите установку из неизвестных источников один раз."
    echo "Безопасность: пароль keystore НЕ хранится в репозитории; используйте SB_KEYSTORE_PASSWORD."
  } > "$ready"
  ok "Отчёт: $ready"
}

list_dist() {
  log "Файлы в dist/:"
  (cd "$DIST_DIR" && ls -lh 2>/dev/null | tail -n +2 || true)
}
