#!/usr/bin/env bash
# Готовит сгенерированный Android-проект Tauri: иконки, полноэкранный режим,
# память Gradle. Безопасен для повторного запуска.
#
#   bash scripts/prepare-android.sh
#
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ANDROID_DIR="$SB_ROOT/src-tauri/gen/android"
MAIN_ACTIVITY=""

need_cmd node
need_cmd npm

if [ ! -d "$ANDROID_DIR" ]; then
  log "Инициализируем Android-проект (tauri android init)..."
  (cd "$SB_ROOT" && npx --no-install tauri android init)
else
  log "Android-проект уже инициализирован: $ANDROID_DIR"
fi

[ -d "$ANDROID_DIR" ] || die "tauri android init не создал $ANDROID_DIR"

# Tauri CLI может сгенерировать compileSdk/targetSdk новее стабильного SDK.
# Фиксируем API 36, который доступен в SDK Manager на всех runners.
ANDROID_APP_GRADLE="$ANDROID_DIR/app/build.gradle.kts"
[ -f "$ANDROID_APP_GRADLE" ] || die "Не найден $ANDROID_APP_GRADLE"
tmp="$(mktemp)"
awk '
  /^[[:space:]]*compileSdk[[:space:]]*=/ { sub(/=.*/, "= 36") }
  /^[[:space:]]*targetSdk[[:space:]]*=/  { sub(/=.*/, "= 36") }
  { print }
' "$ANDROID_APP_GRADLE" > "$tmp"
mv "$tmp" "$ANDROID_APP_GRADLE"
ok "compileSdk/targetSdk зафиксированы на API 36"

log "Применяем иконки Android..."
bash "$SB_ROOT/tools/apply-android-icons.sh" >/dev/null

log "Применяем immersive fullscreen к MainActivity..."
MAIN_ACTIVITY="$(find "$ANDROID_DIR/app/src/main/java" -type f -name 'MainActivity.kt' -print 2>/dev/null | head -n 1 || true)"
[ -n "$MAIN_ACTIVITY" ] || die "MainActivity.kt не найден в $ANDROID_DIR"

if grep -q 'onWindowFocusChanged' "$MAIN_ACTIVITY"; then
  ok " immersive fullscreen уже применён"
else
  tmp="$(mktemp)"
  awk '
    { print }
    /class MainActivity/ && /\{/ && !done {
      print ""
      print "    override fun onWindowFocusChanged(hasFocus: Boolean) {"
      print "        super.onWindowFocusChanged(hasFocus)"
      print "        if (hasFocus) {"
      print "            window.decorView.systemUiVisibility = ("
      print "                android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY"
      print "                    or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN"
      print "                    or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION"
      print "                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN"
      print "                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION"
      print "                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE"
      print "            )"
      print "        }"
      print "    }"
      done = 1
    }
  ' "$MAIN_ACTIVITY" > "$tmp"
  mv "$tmp" "$MAIN_ACTIVITY"
  ok " immersive fullscreen применён"
fi

GRADLE_PROPS="$ANDROID_DIR/gradle.properties"
if [ -f "$GRADLE_PROPS" ] && ! grep -q '^org.gradle.jvmargs=' "$GRADLE_PROPS"; then
  printf '\norg.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8\n' >> "$GRADLE_PROPS"
  ok "Параметры JVM Gradle добавлены"
fi

ok "Android-проект готов: $ANDROID_DIR"
