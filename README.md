# SB Client — SkinBase + CapeForge

Лёгкая нативная оболочка (Tauri v2) для **SkinBase** (`skinbase-dov.pages.dev`)
и **CapeForge** (`capeforge.i3667563.workers.dev`): Windows, Linux, macOS и Android.

Репозиторий: **https://github.com/ggshnikk-sudo/sb-client** (public).

## Что внутри

```
ui/                       локальный лаунчер (SkinBase + CapeForge)
src-tauri/                Rust-ядро Tauri v2
  src/lib.rs              окна, трей, F11 (desktop) и mobile-точка входа
  capabilities/           IPC: только лаунчеру; сайт SkinBase — без прав
  icons/                  иконки для всех ОС
.github/
  actions/setup-build/    общий setup Node/Rust/системных библиотек
  actions/setup-android/  JDK, SDK/NDK, Rust-таргеты
  workflows/ci.yml        проверки + smoke-сборки на 3 ОС и Android
  workflows/release.yml   релиз под все ОС по тегу v*
scripts/                  bash-скрипты сборки для Linux/macOS
launchers/                zero-build лаунчеры (bat / desktop), без компиляции
```

В приложении нет токенов, ключей и паролей: вся логика живёт на ваших серверах,
сессии хранятся в системном WebView.

## Релизы и CI/CD

### Сборка релиза

1. В `Settings → Secrets and variables → Actions` добавьте секреты подписи APK
   (подробности — `README-BUILD.txt`):
   - `ANDROID_KEYSTORE_BASE64` — `base64 -w0 keystore/sbclient.jks`
   - `ANDROID_KEYSTORE_PASSWORD`
   - `ANDROID_KEYSTORE_ALIAS` (обычно `sbclient`)
   - `ANDROID_PRIVATE_KEY_PASSWORD` (если отличается от storepass)
2. Запушьте тег:

   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. `release.yml` соберёт и приложит к GitHub Release:

   | ОС | Артефакты |
   |---|---|
   | Windows | `.exe` (NSIS), `.msi` |
   | Linux | `.deb`, `.AppImage` |
   | macOS | `.dmg`, `.app.zip` |
   | Android | подписанный универсальный `.apk` (arm64 + armv7) |

   Если секретов нет — Android-джоб собрать debug APK и явно предупредит об этом.

`ci.yml` при каждом push/PR делает: `fix-sources --check`, `rustfmt --check`,
`clippy -D warnings`, smoke-сборки desktop на ubuntu/macos/windows и debug APK
на ubuntu. Конкурентные запуски отменяются — это быстро.

Релиз можно также запустить вручную: **Actions → Release → Run workflow** и указать тег.

## Локальная сборка

### Linux

```bash
bash scripts/build-linux.sh          # зависимости (sudo/apt) + deb/AppImage
bash scripts/build.sh --all          # десктоп + APK
bash scripts/build.sh --check        # только проверки
```

### macOS

```bash
xcode-select --install               # один раз
bash scripts/build-macos.sh          # dmg + app.zip
bash scripts/build.sh --android      # APK
```

### Универсальный bash-скрипт

```bash
bash scripts/build.sh --desktop --bundles deb,appimage
bash scripts/build.sh --android --signed      # нужен SB_KEYSTORE_PASSWORD
bash scripts/build.sh --android --debug       # без секретов
bash scripts/build.sh --clean                 # очистить перед сборкой
```

### Windows

```powershell
$env:SB_KEYSTORE_PASSWORD = '<пароль>'   # только если нужен подписанный APK
powershell -ExecutionPolicy Bypass -File .\build.ps1
powershell -ExecutionPolicy Bypass -File .\fix.ps1
powershell -ExecutionPolicy Bypass -File .\sign-apk.ps1
```

Подробности по скриптам и секретам: `README-BUILD.txt`.

## Без сборки (zero-build лаунчеры)

Открывают сайты в отдельном окне браузера (app-mode), без WebView и без компиляции.

- **Windows**: `launchers/windows/SkinBase.bat`, `CapeForge.bat`
- **Linux/macOS**:

  ```bash
  cd launchers/linux
  chmod +x open-app.sh install-linux.sh
  ./install-linux.sh
  ```

- **Android**: Chrome → сайт → «Добавить на главный экран».

## Безопасность

- Никаких секретов в исходниках и бандлах: пароль живёт только в окружении
  (`SB_KEYSTORE_PASSWORD` / GitHub Secrets) и не попадает в репозиторий.
- `scripts/fix-sources.sh` и `fix.ps1` проверяют конфигурацию исходников и то,
  что `keystore/` не отслеживается git; `keystore/` и `dist/` исключены из git.
- Пароль читается только из `SB_KEYSTORE_PASSWORD` / GitHub Secrets;
  `apksigner` получает его через `env:` — он не попадает в argv и логи.
- Окно SkinBase создано без IPC-разрешений: удалённый сайт не может работать
  с файлами, окнами и хранилищем приложения.
- Подпись Android: `zipalign` → `apksigner sign` → `apksigner verify`.

## Требования

Node 20+, Rust stable (1.90+), для Linux — webkit2gtk-4.1, GTK3, appindicator,
librsvg, patchelf; для Android — JDK 21, Android SDK 37 / NDK 27, цели
`aarch64-linux-android` и `armv7-linux-androideabi`.
