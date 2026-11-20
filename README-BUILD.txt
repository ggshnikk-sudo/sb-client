=====================================================================
 SB CLIENT — СБОРКА И ПОДПИСЬ  [v2.0]
=====================================================================

ВАЖНО (безопасность)
  Пароль keystore НЕ хранится в репозитории и НЕ записывается в скрипты.
  Передавайте его через переменную SB_KEYSTORE_PASSWORD (или GitHub Secret
  ANDROID_KEYSTORE_PASSWORD). Файл keystore/*.jks также не коммитится.

  Если вы когда-либо публиковали старый пароль — смените ключ/пароль:
    keytool -change -alias sbclient -keystore keystore\sbclient.jks ...
  и обновите секреты в GitHub.

---------------------------------------------------------------------
 WINDOWS 10/11 (PowerShell)
---------------------------------------------------------------------
  1. Запустите от администратора PowerShell в папке проекта:
       powershell -ExecutionPolicy Bypass -File .\build.ps1
  2. Для подписи APK задайте пароль ДО запуска:
       $env:SB_KEYSTORE_PASSWORD = '<ваш пароль>'
       powershell -ExecutionPolicy Bypass -File .\build.ps1
  3. Раздельные шаги:
       .\build.ps1 -OnlyWindows
       .\build.ps1 -OnlyAndroid
       .\fix.ps1                  — проверить исходники
       .\fix.ps1 -Restore         — восстановить src-tauri из git
       .\sign-apk.ps1             — подписать уже собранные APK

  Результат: dist\READY.txt, установщики Windows и подписанный APK.
  Подробный лог: build.log.

---------------------------------------------------------------------
 LINUX / macOS (bash — основной путь для GitHub Actions)
---------------------------------------------------------------------
  Linux (одной командой, поставит зависимости через sudo/apt):
       bash scripts/build-linux.sh

  Linux/macOS вручную:
       bash scripts/build.sh --desktop        # deb+AppImage или dmg+app
       bash scripts/build.sh --android        # APK
       bash scripts/build.sh --all            # всё сразу
       bash scripts/build.sh --check          # только проверки, без сборки

  Подпись APK на Unix:
       export SB_KEYSTORE_PASSWORD='<ваш пароль>'
       export SB_KEYSTORE_PATH="$PWD/keystore/sbclient.jks"   # по умолчанию
       export SB_KEY_ALIAS=sbclient
       bash scripts/build.sh --android --signed

  Без пароля будет собран debug APK (ставится на телефон, но не release).

  Скрипты:
       scripts/build.sh            — главный orchestrator
       scripts/build-linux.sh      — Linux: deps + desktop-сборка
       scripts/build-macos.sh      — macOS: CLT + dmg/app.zip
       scripts/build-desktop.sh    — только десктоп
       scripts/build-android.sh    — только APK
       scripts/prepare-android.sh  — init/иконки/полный экран
       scripts/sign-apk.sh         — zipalign + apksigner + verify
       scripts/fix-sources.sh      — проверка/восстановление исходников

---------------------------------------------------------------------
 CI/CD И РЕЛИЗ (GitHub Actions)
---------------------------------------------------------------------
  .github/workflows/ci.yml       — PR/push: fmt, clippy, smoke-сборки
  .github/workflows/release.yml  — тег v*: Windows + Linux + macOS + Android

  Секреты репозитория (Settings → Secrets and variables → Actions):
    ANDROID_KEYSTORE_BASE64      — base64 содержимого keystore/sbclient.jks
    ANDROID_KEYSTORE_PASSWORD    — пароль keystore
    ANDROID_KEYSTORE_ALIAS       — sbclient (или ваш alias)
    ANDROID_PRIVATE_KEY_PASSWORD — если отличается от storepass

  Пример загрузки секретов (bash):
    base64 -w0 keystore/sbclient.jks | gh secret set ANDROID_KEYSTORE_BASE64
    gh secret set ANDROID_KEYSTORE_PASSWORD
    gh secret set ANDROID_KEYSTORE_ALIAS --body sbclient

  Без секретов Android-джоб соберёт debug APK, остальные ОС — как обычно.

  Релиз публикуется по тегу:
    git tag v1.0.0 && git push origin v1.0.0
=====================================================================
