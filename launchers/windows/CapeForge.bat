@echo off
chcp 65001 >nul
rem CapeForge - редактор плащей в отдельном окне приложения (app-mode).
set "URL=https://capeforge.i3667563.workers.dev/"

if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" (
  start "" "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" --app=%URL%
  exit /b
)
if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" (
  start "" "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" --app=%URL%
  exit /b
)
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" (
  start "" "%ProgramFiles%\Google\Chrome\Application\chrome.exe" --app=%URL%
  exit /b
)
if exist "%LocalAppData%\Google\Chrome\Application\chrome.exe" (
  start "" "%LocalAppData%\Google\Chrome\Application\chrome.exe" --app=%URL%
  exit /b
)
if exist "%ProgramFiles%\Chromium\Application\chrome.exe" (
  start "" "%ProgramFiles%\Chromium\Application\chrome.exe" --app=%URL%
  exit /b
)
echo Chrome/Edge не найден, открываю в браузере по умолчанию...
start %URL%
