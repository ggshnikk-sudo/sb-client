#!/usr/bin/env bash
# Подписывает уже собранные Tauri APK через zipalign + apksigner.
# Пароль НИКОгда не пишется в argv: apksigner/keytool читают его из env.
#
#   export SB_KEYSTORE_PASSWORD='...'            # обязательно
#   export SB_KEYSTORE_PATH=/path/to/key.jks     # по умолчанию keystore/sbclient.jks
#   export SB_KEY_ALIAS=sbclient                 # по умолчанию sbclient
#   export SB_KEY_PASSWORD='...'                 # если отличается от storepass
#   bash scripts/sign-apk.sh [--allow-debug] [--generate-key] [--copy-only]
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ALLOW_DEBUG=0
GENERATE_KEY=0
COPY_ONLY=0
APK_DIR=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --allow-debug)  ALLOW_DEBUG=1 ;;
    --generate-key) GENERATE_KEY=1 ;;
    --copy-only)    COPY_ONLY=1 ;;
    --input-dir)    APK_DIR="${2:?--input-dir требует путь}"; shift ;;
    -h|--help)      sed -n '2,9p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "Неизвестный аргумент: $1" ;;
  esac
  shift
done

KEYSTORE="${SB_KEYSTORE_PATH:-$SB_ROOT/keystore/sbclient.jks}"
ALIAS="${SB_KEY_ALIAS:-sbclient}"
STORE_PASS="${SB_KEYSTORE_PASSWORD:-}"
KEY_PASS="${SB_KEY_PASSWORD:-$STORE_PASS}"
export SB_KEYSTORE_PASSWORD="$STORE_PASS"
export SB_KEY_PASSWORD="$KEY_PASS"

if [ "$COPY_ONLY" -eq 0 ]; then
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
  need_cmd java

  # Находим свежие build-tools (apksigner + zipalign) в установленном Android SDK.
  BUILD_TOOLS=""
  for root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" \
    "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "$HOME/sb-client-android-sdk"; do
    [ -n "$root" ] && [ -d "$root/build-tools" ] || continue
    for candidate in "$root"/build-tools/*; do
      [ -x "$candidate/apksigner" ] && [ -x "$candidate/zipalign" ] || continue
      BUILD_TOOLS="$candidate"   # каталоги отсортированы: последний — самый свежий
    done
  done
  [ -n "$BUILD_TOOLS" ] || die "Android build-tools с apksigner/zipalign не найдены"
  export PATH="$BUILD_TOOLS:$PATH"
  log "build-tools: $BUILD_TOOLS"
  need_cmd zipalign
  need_cmd apksigner
fi

if [ -z "$APK_DIR" ]; then
  APK_DIR="$SB_ROOT/src-tauri/gen/android/app/build/outputs/apk"
fi
[ -d "$APK_DIR" ] || die "Папка APK не найдена: $APK_DIR (сначала запустите сборку)"

if [ "$COPY_ONLY" -eq 0 ]; then
  log "Keystore : $KEYSTORE"
  log "Alias    : $ALIAS"
  if [ ! -f "$KEYSTORE" ]; then
    if [ "$GENERATE_KEY" -eq 1 ]; then
      [ -n "$STORE_PASS" ] || die "Для --generate-key нужен SB_KEYSTORE_PASSWORD"
      mkdir -p "$(dirname "$KEYSTORE")"
      log "Генерируем новый keystore..."
      keytool -genkeypair -v \
        -keystore "$KEYSTORE" -alias "$ALIAS" \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass:env SB_KEYSTORE_PASSWORD -keypass:env SB_KEY_PASSWORD \
        -dname "CN=SB Client, OU=ggshnikk, O=ggshnikk, L=RU, ST=RU, C=RU"
      ok "Keystore создан. Сохраните его и НЕ добавляйте в git."
    else
      die "Keystore не найден: $KEYSTORE (SB_KEYSTORE_PATH или --generate-key)"
    fi
  fi
fi
log "APK dir  : $APK_DIR"

VER="$(sb_version)"
ensure_dist
TMP_ALIGNED="$(mktemp "${TMPDIR:-/tmp}/sb-align-XXXXXX.apk")"
trap 'rm -f "$TMP_ALIGNED"' EXIT

signed_count=0
found_any=0

# 1) Unsigned release APK -> align -> sign -> verify -> dist
if [ "$COPY_ONLY" -eq 0 ]; then
  while IFS= read -r apk; do
    [ -n "$apk" ] || continue
    found_any=1
    [ -n "$STORE_PASS" ] || die "Не задан SB_KEYSTORE_PASSWORD — не могу подписать $apk"
    variant="$(basename "$(dirname "$(dirname "$apk")")")"
    final="$DIST_DIR/SB-Client-v${VER}-android-${variant}.apk"
    log "Подписываем $(basename "$apk") -> $(basename "$final")"
    zipalign -f -p 4 "$apk" "$TMP_ALIGNED"
    apksigner sign \
      --ks "$KEYSTORE" \
      --ks-key-alias "$ALIAS" \
      --ks-pass env:SB_KEYSTORE_PASSWORD \
      --key-pass env:SB_KEY_PASSWORD \
      --out "$final" "$TMP_ALIGNED"
    apksigner verify --verbose "$final" >/dev/null
    ok "Подписан и проверен: $(basename "$final")"
    signed_count=$((signed_count + 1))
  done < <(find "$APK_DIR" -type f -name '*-unsigned.apk' ! -path '*/debug/*' | sort)
fi

# 2) Уже подписанные APK просто копируем в dist (в т.ч. debug по флагу).
while IFS= read -r apk; do
  [ -n "$apk" ] || continue
  case "$apk" in
    *-unsigned.apk) continue ;;
    */debug/*) [ "$ALLOW_DEBUG" -eq 1 ] || continue ;;
  esac
  found_any=1
  variant="$(basename "$(dirname "$(dirname "$apk")")")"
  suffix="-signed"
  case "$apk" in */debug/*) suffix="-debug" ;; esac
  final="$DIST_DIR/SB-Client-v${VER}-android-${variant}${suffix}.apk"
  cp -f "$apk" "$final"
  ok "Скопирован: $(basename "$final")"
  signed_count=$((signed_count + 1))
done < <(find "$APK_DIR" -type f -name '*.apk' | sort)

[ "$found_any" -eq 1 ] || die "В $APK_DIR не найдено APK"
[ "$signed_count" -gt 0 ] || die "Ни один APK не попал в dist"
ok "Готово: $signed_count APK в $DIST_DIR"
