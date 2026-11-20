# =====================================================================
#  SB CLIENT - SOURCE CHECK / REPAIR  (Windows PowerShell 5.1+)
#  Bash equivalent: scripts/fix-sources.sh
#
#  Checks desktop/mobile cfg split, Tauri config, icons and release
#  profile. Does NOT store or print any keystore password.
#
#  Check : powershell -ExecutionPolicy Bypass -File .\fix.ps1
#  Restore: powershell -ExecutionPolicy Bypass -File .\fix.ps1 -Restore
# =====================================================================
param(
  [switch]$Restore,
  [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$LibRs   = Join-Path $Root 'src-tauri\src\lib.rs'
$Cargo   = Join-Path $Root 'src-tauri\Cargo.toml'
$BuildRs = Join-Path $Root 'src-tauri\build.rs'
$Conf    = Join-Path $Root 'src-tauri\tauri.conf.json'

function OK($msg)   { Write-Host (" OK  " + $msg) -ForegroundColor Green }
function BAD($msg)  { Write-Host ("FAIL " + $msg) -ForegroundColor Red; $script:fail++ }
function Has($path, $needle) {
  (Test-Path $path) -and ((Get-Content $path -Raw) -like ("*" + $needle + "*"))
}

$script:fail = 0
Write-Host 'SB-CLIENT SOURCE CHECK' -ForegroundColor Cyan
Write-Host ("  project: " + $Root)

if ($Restore) {
  git -C $Root checkout -- src-tauri/src/lib.rs src-tauri/Cargo.toml src-tauri/tauri.conf.json src-tauri/build.rs
  if ($LASTEXITCODE -ne 0) { throw 'git checkout failed' }
  OK 'Sources restored from git.'
}

Has $LibRs '#[cfg(desktop)]'            | ForEach-Object { if ($_) { OK 'lib.rs: desktop cfg' } else { BAD 'lib.rs: no #[cfg(desktop)]' } }
Has $LibRs '#[cfg(mobile)]'             | ForEach-Object { if ($_) { OK 'lib.rs: mobile cfg' } else { BAD 'lib.rs: no #[cfg(mobile)]' } }
Has $LibRs 'tauri::mobile_entry_point'  | ForEach-Object { if ($_) { OK 'lib.rs: mobile_entry_point' } else { BAD 'lib.rs: no mobile_entry_point' } }
Has $Cargo 'tray-icon'                  | ForEach-Object { if ($_) { OK 'Cargo.toml: tray-icon' } else { BAD 'Cargo.toml: no tray-icon' } }
Has $Cargo 'strip = "debuginfo"'        | ForEach-Object { if ($_) { OK 'Cargo.toml: JNI symbols kept' } else { BAD 'Cargo.toml: strip = true would remove JNI symbols' } }
Has $BuildRs 'tauri_build::build'       | ForEach-Object { if ($_) { OK 'build.rs: tauri-build' } else { BAD 'build.rs: no tauri_build::build()' } }

foreach ($icon in 'app-icon.png','32x32.png','128x128.png','icon.ico','icon.icns') {
  if (Test-Path (Join-Path $Root ('src-tauri\icons\' + $icon))) {
    OK ("icon " + $icon)
  } else {
    BAD ("missing icon " + $icon)
  }
}

try {
  $cfg = Get-Content $Conf -Raw | ConvertFrom-Json
  if ($cfg.identifier -and $cfg.version -and $cfg.build) { OK 'tauri.conf.json is valid' }
  else { BAD 'tauri.conf.json: required fields missing' }
} catch { BAD ('tauri.conf.json: ' + $_) }

if ($script:fail -gt 0) {
  throw ("Source check failed: " + $script:fail + " problem(s). Run with -Restore.")
}
OK 'All source checks passed.'
