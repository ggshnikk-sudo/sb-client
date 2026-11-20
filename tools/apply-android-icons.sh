#!/usr/bin/env bash
# Копирует mipmap-иконки и цвет фона в сгенерированный Android-проект.
# Запускать ПОСЛЕ `bun run tauri android init`.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="branding/app-icon/android"
DST="src-tauri/gen/android/app/src/main/res"

for d in mipmap-mdpi mipmap-hdpi mipmap-xhdpi mipmap-xxhdpi mipmap-xxxhdpi; do
  mkdir -p "$DST/$d"
  cp "$SRC/$d/"*.png "$DST/$d/"
done

mkdir -p "$DST/values"
cp "$SRC/values/ic_launcher_background.xml" "$DST/values/"

echo "Иконки Android скопированы в $DST"
