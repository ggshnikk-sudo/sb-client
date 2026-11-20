# =====================================================================
#  SB CLIENT - APK SIGNER v1.0 (pure ASCII)
#  Signs already-built UNSIGNED Android APK(s) with the SB keystore.
#  No rebuild needed - takes ~30 seconds.
#
#  Why: Tauri CLI 2.12.6 does NOT sign Android APKs at all (no apksigner
#  code inside). Gradle leaves an unsigned APK, and build.ps1 v1.2
#  filtered it out. This script fixes the last missing step.
#
#  Run from ANY folder (default project is C:\sb-client):
#    powershell -ExecutionPolicy Bypass -File "C:\Users\<you>\Downloads\sign-apk.ps1"
#
#  Result: C:\sb-client\dist\SB-Client-v1.0.0-<variant>.apk (signed + verified)
# =====================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# Never hardcode the password: read it only from environment / GitHub Secrets.
$StorePass = $env:SB_KEYSTORE_PASSWORD
$KeyPass   = if ($env:SB_KEY_PASSWORD) { $env:SB_KEY_PASSWORD } else { $StorePass }
$AliasName = if ($env:SB_KEY_ALIAS) { $env:SB_KEY_ALIAS } else { 'sbclient' }

function Finish([int]$Code) {
  Write-Host ''
  Write-Host 'Press ENTER to close.' -ForegroundColor Yellow
  if (-not $env:SB_CLIENT_NOPAUSE) { Read-Host 'Press ENTER to close' | Out-Null }
  exit $Code
}
function Fail([string]$Msg) {
  Write-Host ''
  Write-Host ('ERROR: ' + $Msg) -ForegroundColor Red
  Finish 1
}

if (-not $StorePass) { Fail 'Set SB_KEYSTORE_PASSWORD before signing (GitHub Secret on CI).' }

Write-Host 'SB CLIENT - APK SIGNER v1.0' -ForegroundColor Cyan
Write-Host ''

# ---------- locate project ----------
$Root = 'C:\sb-client'
if (-not (Test-Path (Join-Path $Root 'src-tauri\gen\android'))) {
  $alt = $PSScriptRoot
  if ($alt -and (Test-Path (Join-Path $alt 'src-tauri\gen\android'))) {
    $Root = $alt
  } else {
    Fail 'Project not found (C:\sb-client\src-tauri\gen\android missing). Run build.ps1 first.'
  }
}
Write-Host ('Project    : ' + $Root)

# ---------- locate SDK build-tools (zipalign + apksigner) ----------
$Bt = $null
foreach ($s in @($env:ANDROID_HOME, (Join-Path $env:USERPROFILE 'sb-client-android-sdk'))) {
  if ($s -and (Test-Path (Join-Path $s 'build-tools'))) {
    foreach ($d in (Get-ChildItem (Join-Path $s 'build-tools') -Directory | Sort-Object Name -Descending)) {
      if (Test-Path (Join-Path $d.FullName 'apksigner.bat')) { $Bt = $d.FullName; break }
    }
    if ($Bt) { break }
  }
}
if (-not $Bt) {
  Fail 'Android build-tools with apksigner.bat not found. Run build.ps1 once - it installs build-tools 34.0.0.'
}
Write-Host ('Build-tools: ' + $Bt)

# ---------- JDK (apksigner.bat and keytool need java) ----------
$JavaHome = Join-Path $env:USERPROFILE 'sb-client-jdk17\jdk'
if (-not (Test-Path (Join-Path $JavaHome 'bin\java.exe'))) {
  $sysJava = Get-Command java.exe -ErrorAction SilentlyContinue
  if ($sysJava) {
    $JavaHome = Split-Path (Split-Path $sysJava.Source -Parent) -Parent
  } else {
    Fail 'JDK not found (C:\Users\<you>\sb-client-jdk17\jdk). Run build.ps1 once first.'
  }
}
$env:JAVA_HOME = $JavaHome
$env:Path = (Join-Path $JavaHome 'bin') + ';' + $env:Path
Write-Host ('JDK        : ' + $JavaHome)

# ---------- keystore ----------
$Ks = if ($env:SB_KEYSTORE_PATH) { $env:SB_KEYSTORE_PATH } else { Join-Path $Root 'keystore\sbclient.jks' }
if (-not (Test-Path $Ks)) {
  Write-Host '  keystore not found - generating a new one...'
  New-Item -ItemType Directory -Force -Path (Split-Path $Ks -Parent) | Out-Null
  & (Join-Path $JavaHome 'bin\keytool.exe') -genkeypair -v -keystore $Ks -alias $AliasName `
    -keyalg RSA -keysize 2048 -validity 10000 `
    -storepass $StorePass -keypass $KeyPass `
    -dname 'CN=SB Client, OU=ggshnikk, O=ggshnikk, L=RU, ST=RU, C=RU'
  if ($LASTEXITCODE -ne 0) { Fail 'keytool failed to generate the keystore.' }
  Write-Host '  new keystore created.' -ForegroundColor Green
  Write-Host '  SAVE this keystore and add SB_KEYSTORE_PASSWORD to GitHub Secrets.' -ForegroundColor Yellow
}
Write-Host ('Keystore   : ' + $Ks + '  (alias: ' + $AliasName + ')')

# ---------- version from tauri.conf.json ----------
$Ver = '1.0.0'
try {
  $c = Get-Content (Join-Path $Root 'src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json
  if ($c.version) { $Ver = $c.version }
} catch {}
Write-Host ('App version: ' + $Ver)
Write-Host ''

# ---------- find unsigned APKs ----------
$ApkDir = Join-Path $Root 'src-tauri\gen\android\app\build\outputs\apk'
if (-not (Test-Path $ApkDir)) { Fail ('APK output folder not found: ' + $ApkDir) }
$unsigned = @(Get-ChildItem $ApkDir -Recurse -Filter '*-unsigned.apk' -ErrorAction SilentlyContinue |
  Where-Object { ($_.FullName -split '\\') -notcontains 'debug' })

if ($unsigned.Count -eq 0) {
  $signed = @(Get-ChildItem $ApkDir -Recurse -Filter '*.apk' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch 'unsigned' })
  if ($signed.Count -gt 0) {
    Write-Host 'No unsigned APKs left - signed APK(s) already exist:' -ForegroundColor Green
    $signed | ForEach-Object { Write-Host ('  ' + $_.FullName) }
  } else {
    Fail ('No APKs found in ' + $ApkDir + ' - build first: powershell -ExecutionPolicy Bypass -File C:\sb-client\build.ps1')
  }
  Finish 0
}

$Zipalign = Join-Path $Bt 'zipalign.exe'
$Signer   = Join-Path $Bt 'apksigner.bat'
$Dist     = Join-Path $Root 'dist'
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Remove-Item (Join-Path $Dist 'FAILED.txt') -Force -ErrorAction SilentlyContinue

$okCount = 0
foreach ($apk in $unsigned) {
  $variant = Split-Path (Split-Path $apk.DirectoryName -Parent) -Leaf
  $final   = Join-Path $Dist ('SB-Client-v' + $Ver + '-' + $variant + '.apk')
  $aligned = Join-Path $env:TEMP ('sb-align-' + $variant + '.apk')
  Write-Host ('Signing: ' + $apk.Name)
  & $Zipalign -f -p 4 $apk.FullName $aligned
  if ($LASTEXITCODE -ne 0) { Fail ('zipalign failed for ' + $apk.Name) }
  & $Signer sign --ks $Ks --ks-key-alias $AliasName `
    --ks-pass "pass:$StorePass" --key-pass "pass:$KeyPass" --out $final $aligned
  if ($LASTEXITCODE -ne 0) { Fail ('apksigner failed for ' + $apk.Name) }
  & $Signer verify $final
  if ($LASTEXITCODE -ne 0) { Fail ('signature verification FAILED for ' + $final) }
  Remove-Item $aligned -Force -ErrorAction SilentlyContinue
  $mb = [math]::Round((Get-Item $final).Length / 1MB, 1)
  Write-Host ('  SIGNED + VERIFIED: ' + $final + '  (' + $mb + ' MB)') -ForegroundColor Green
  $okCount++
}

Write-Host ''
Write-Host ('VERIFY OK - ' + $okCount + ' APK(s) signed with ' + $Ks + ' (alias: ' + $AliasName + ').') -ForegroundColor Green
Write-Host ('Universal APK works on BOTH arm64 and armv7 devices (both libs are inside).')
Write-Host ('Dist folder: ' + $Dist)
Get-ChildItem $Dist | ForEach-Object { Write-Host ('  ' + $_.Name + '  (' + [math]::Round($_.Length / 1MB, 1) + ' MB)') }
Finish 0
