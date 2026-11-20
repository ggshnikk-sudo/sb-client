#!/usr/bin/env bash
# Открывает URL в отдельном окне приложения (app-mode Chromium/Edge).
# Использование: ./open-app.sh [url]
URL="${1:-https://skinbase-dov.pages.dev}"

BROWSERS=(
  chromium
  chromium-browser
  google-chrome-stable
  google-chrome
  microsoft-edge-stable
  microsoft-edge
  brave-browser
  vivaldi-stable
  vivaldi
  yandex-browser
)

for b in "${BROWSERS[@]}"; do
  if command -v "$b" >/dev/null 2>&1; then
    exec "$b" --app="$URL"
  fi
done

echo "Chromium-браузер не найден — открываю в браузере по умолчанию." >&2
xdg-open "$URL"
