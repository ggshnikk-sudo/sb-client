# =====================================================================
#  SB CLIENT - BUILD SCRIPT (Windows 10/11)  [v1.5, pure ASCII]
#  Builds: Android APK (universal, signed) + Windows NSIS installer
#  Run:  powershell -ExecutionPolicy Bypass -File .\build.ps1
#  APK signing needs SB_KEYSTORE_PASSWORD (never hardcode it). Unix: scripts/build.sh
#  Progress: build.log    Result: dist\READY.txt + artifacts
#  On ANY error the window stays open and writes:
#    - dist\FAILED.txt (or project root, if dist was not created)
#    - C:\Users\<you>\sb-client-error.txt  (always, fixed location)
#  Re-run is safe: finished steps are skipped.
#
#  v1.5 changes:
#   - APK signing via zipalign + apksigner (Tauri CLI 2.12.6 does NOT
#     sign Android APKs at all - it leaves *-unsigned.apk behind).
#   - dist cleanup: stale FAILED.txt removed before collecting.
#   - sb-client.exe is collected as "SB Client.exe" too.
# =====================================================================
param(
  [switch]$OnlyWindows,
  [switch]$OnlyAndroid,
  [switch]$SkipWindows,
  [switch]$SkipAndroid
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

function Write-Crash([string]$Text) {
  # writes the crash report to fixed locations so it is never lost
  try {
    $rep = @"
SB CLIENT BUILD - CRASH REPORT
Time : $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')
PS   : $($PSVersionTable.PSVersion)
OS   : $([Environment]::OSVersion.VersionString)

ERROR:
$Text

Send this file (and build.log if it exists) to the assistant.
"@
    Set-Content -Path "$env:USERPROFILE\sb-client-error.txt" -Value $rep -Encoding UTF8
    Write-Host "  crash report saved to: $env:USERPROFILE\sb-client-error.txt" -ForegroundColor Yellow
  } catch {}
}

function Sign-AndroidApks([string]$Root, [string]$Ver) {
  # Tauri CLI 2.12.6 leaves *-unsigned.apk behind and has NO signing code.
  # We sign every non-debug unsigned APK with zipalign + apksigner ourselves.
  $Bt = $null
  foreach ($s in @($env:ANDROID_HOME, (Join-Path $env:USERPROFILE 'sb-client-android-sdk'))) {
    if ($s -and (Test-Path (Join-Path $s 'build-tools'))) {
      foreach ($d in (Get-ChildItem (Join-Path $s 'build-tools') -Directory | Sort-Object Name -Descending)) {
        if (Test-Path (Join-Path $d.FullName 'apksigner.bat')) { $Bt = $d.FullName; break }
      }
      if ($Bt) { break }
    }
  }
  if (-not $Bt) { Write-Warning '  build-tools with apksigner.bat not found - APK stays unsigned'; return }
  if ($javaHome -and (Test-Path (Join-Path $javaHome 'bin\java.exe'))) {
    $env:JAVA_HOME = $javaHome
    $env:Path = (Join-Path $javaHome 'bin') + ';' + $env:Path
  }
  $storePass = $env:SB_KEYSTORE_PASSWORD
  $keyPass   = if ($env:SB_KEY_PASSWORD) { $env:SB_KEY_PASSWORD } else { $storePass }
  $aliasName = if ($env:SB_KEY_ALIAS) { $env:SB_KEY_ALIAS } else { 'sbclient' }
  if (-not $storePass) {
    Write-Warning '  SB_KEYSTORE_PASSWORD is not set - APK stays unsigned (CI: add GitHub Secret)'
    return
  }
  $Ks = if ($env:SB_KEYSTORE_PATH) { $env:SB_KEYSTORE_PATH } else { Join-Path $Root 'keystore\sbclient.jks' }
  if (-not (Test-Path $Ks)) { Write-Warning '  keystore not found - APK stays unsigned'; return }
  $ApkDir = Join-Path $Root 'src-tauri\gen\android\app\build\outputs\apk'
  $unsigned = @(Get-ChildItem $ApkDir -Recurse -Filter '*-unsigned.apk' -ErrorAction SilentlyContinue |
    Where-Object { ($_.FullName -split '\\') -notcontains 'debug' })
  if ($unsigned.Count -eq 0) { Write-Host '  no unsigned APKs left (already signed).' -ForegroundColor DarkGray; return }
  $Dist2 = Join-Path $Root 'dist'
  New-Item -ItemType Directory -Force -Path $Dist2 | Out-Null
  foreach ($apk in $unsigned) {
    $variant = Split-Path (Split-Path $apk.DirectoryName -Parent) -Leaf
    $final   = Join-Path $Dist2 ('SB-Client-v' + $Ver + '-' + $variant + '.apk')
    $aligned = Join-Path $env:TEMP ('sb-align-' + $variant + '.apk')
    Write-Host ('  signing ' + $apk.Name + ' ...')
    & (Join-Path $Bt 'zipalign.exe') -f -p 4 $apk.FullName $aligned
    if ($LASTEXITCODE -ne 0) { Write-Warning ('  zipalign failed for ' + $apk.Name); continue }
    & (Join-Path $Bt 'apksigner.bat') sign --ks $Ks --ks-key-alias $aliasName `
      --ks-pass "pass:$storePass" --key-pass "pass:$keyPass" --out $final $aligned
    if ($LASTEXITCODE -ne 0) { Write-Warning ('  apksigner failed for ' + $apk.Name); continue }
    & (Join-Path $Bt 'apksigner.bat') verify $final | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning ('  verification failed for ' + $final); continue }
    Remove-Item $aligned -Force -ErrorAction SilentlyContinue
    Write-Host ('  SIGNED + VERIFIED: ' + (Split-Path $final -Leaf)) -ForegroundColor Green
  }
}

$Root = $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }
$OrigRoot = $Root

$doWindows = (-not $SkipWindows) -and (-not $OnlyAndroid)
$doAndroid = (-not $SkipAndroid) -and (-not $OnlyWindows)

try {
  # ---------- admin rights ----------
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    Write-Host 'Relaunching with administrator rights - confirm the UAC prompt...' -ForegroundColor Yellow
    $argList = @('-ExecutionPolicy','Bypass','-NoProfile','-File', "`"$PSCommandPath`"")
    foreach ($k in 'OnlyWindows','OnlyAndroid','SkipWindows','SkipAndroid') {
      if ($PSBoundParameters.ContainsKey($k)) { $argList += "-$k" }
    }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($argList -join ' ')
    exit
  }

  # ---------- long paths (best effort) ----------
  try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
  } catch {}

  # ---------- disk space check ----------
  try {
    $freeGB = [math]::Round((Get-PSDrive C).Free / 1GB)
    Write-Host ("Free space on C: {0} GB" -f $freeGB)
    if ($freeGB -lt 15) {
      Write-Warning ("Only {0} GB free on C:. The full toolchain needs about 12-15 GB. Build may fail." -f $freeGB)
    }
  } catch {}

  # ---------- path with spaces? copy project to C:\sb-client ----------
  if ($Root -match ' ') {
    $Target = 'C:\sb-client'
    Write-Host "Project path has spaces -> copying project to $Target ..." -ForegroundColor Yellow
    robocopy $Root $Target /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy failed with code $LASTEXITCODE" }
    $Root = $Target
    Set-Content -Path (Join-Path $OrigRoot 'RESULT-IN-C-sb-client.txt') `
      -Value "Build runs in C:\sb-client (spaces were removed from the path).`r`nResults: C:\sb-client\dist  Log: C:\sb-client\build.log" `
      -Encoding ASCII
  }
  $Dist = Join-Path $Root 'dist'

  $Ver = '1.0.0'
  try {
    $c = Get-Content (Join-Path $Root 'src-tauri\tauri.conf.json') -Raw | ConvertFrom-Json
    if ($c.version) { $Ver = $c.version }
  } catch {}

  try { Start-Transcript -Path (Join-Path $Root 'build.log') -Append | Out-Null } catch {}

  function Step([int]$n, [string]$msg) {
    Write-Host ''
    Write-Host "=== [$n/9] $msg ===" -ForegroundColor Cyan
    Write-Host ("    " + (Get-Date -Format 'HH:mm:ss'))
  }
  function Get-File([string]$Url, [string]$Out) {
    if (Test-Path $Out) { Write-Host "  already downloaded: $Out" -ForegroundColor DarkGray; return }
    Write-Host "  downloading: $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing
  }

  # ================================================================
  # [1/9] MSVC Build Tools
  # ================================================================
  Step 1 'Visual Studio Build Tools (C++)'
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $haveMsvc = $false
  if (Test-Path $vswhere) {
    $inst = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($inst) { $haveMsvc = $true; Write-Host "  MSVC already installed: $inst" -ForegroundColor Green }
  }
  if (-not $haveMsvc) {
    Get-File 'https://aka.ms/vs/17/release/vs_BuildTools.exe' "$env:TEMP\vs_BuildTools.exe"
    Write-Host '  installing VS Build Tools (2-4 GB, 15-40 min, window may look silent - it is normal)...' -ForegroundColor Yellow
    $p = Start-Process -FilePath "$env:TEMP\vs_BuildTools.exe" -Wait -PassThru -ArgumentList `
      '--quiet','--wait','--norestart','--nocache',
      '--add','Microsoft.VisualStudio.Workload.VCTools','--includeRecommended'
    if ($p.ExitCode -ne 0) { throw "VS Build Tools install failed, exit code $($p.ExitCode)" }
    Write-Host '  VS Build Tools installed.' -ForegroundColor Green
  }

  # ================================================================
  # [2/9] Rust + Android targets
  # ================================================================
  Step 2 'Rust (rustup, minimal profile)'
  $cargoBin  = "$env:USERPROFILE\.cargo\bin"
  $rustupExe = Join-Path $cargoBin 'rustup.exe'
  if (-not (Test-Path $rustupExe)) {
    Get-File 'https://win.rustup.rs/x86_64' "$env:TEMP\rustup-init.exe"
    & "$env:TEMP\rustup-init.exe" -y --profile minimal --default-toolchain stable-x86_64-pc-windows-msvc
    if ($LASTEXITCODE -ne 0) { throw "rustup init failed, exit code $LASTEXITCODE" }
  } else { Write-Host '  Rust already installed.' -ForegroundColor Green }
  $env:Path = "$cargoBin;$env:Path"
  if ($doAndroid) {
    Write-Host '  adding Android Rust targets...'
    & $rustupExe target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android
  }

  # ================================================================
  # [3/9] JDK 17
  # ================================================================
  Step 3 'JDK 17 (portable Temurin)'
  $jdkRoot  = "$env:USERPROFILE\sb-client-jdk17"
  $javaHome = Join-Path $jdkRoot 'jdk'
  if (-not (Test-Path (Join-Path $javaHome 'bin\java.exe'))) {
    Get-File 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk' "$env:TEMP\jdk17.zip"
    Write-Host '  extracting JDK...'
    Expand-Archive "$env:TEMP\jdk17.zip" "$jdkRoot\_tmp" -Force
    $inner = (Get-ChildItem "$jdkRoot\_tmp" -Directory | Select-Object -First 1).FullName
    Move-Item $inner $javaHome
    Remove-Item "$jdkRoot\_tmp" -Recurse -Force
    Remove-Item "$env:TEMP\jdk17.zip" -Force -ErrorAction SilentlyContinue
  } else { Write-Host '  JDK already installed.' -ForegroundColor Green }
  $env:JAVA_HOME = $javaHome
  $env:Path = "$javaHome\bin;$env:Path"

  # ================================================================
  # [4/9] Android SDK + NDK
  # ================================================================
  if ($doAndroid) {
    Step 4 'Android SDK + NDK'
    $Sdk = "$env:USERPROFILE\sb-client-android-sdk"
    if (-not (Test-Path "$Sdk\cmdline-tools\latest\bin\sdkmanager.bat")) {
      Get-File 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip' "$env:TEMP\cmdtools.zip"
      Write-Host '  extracting cmdline-tools...'
      Expand-Archive "$env:TEMP\cmdtools.zip" "$Sdk\cmdline-tools\_tmp" -Force
      Move-Item "$Sdk\cmdline-tools\_tmp\cmdline-tools" "$Sdk\cmdline-tools\latest"
      Remove-Item "$Sdk\cmdline-tools\_tmp" -Recurse -Force
      Remove-Item "$env:TEMP\cmdtools.zip" -Force -ErrorAction SilentlyContinue
    }
    $sdkm = "$Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
    if (-not (Test-Path "$Sdk\ndk\27.0.12077973")) {
      Write-Host '  accepting licenses, installing packages (NDK ~2 GB - longest step)...' -ForegroundColor Yellow
      (1..60 | ForEach-Object { 'y' }) | & $sdkm --licenses --sdk_root="$Sdk"
      & $sdkm --sdk_root="$Sdk" 'platform-tools' 'platforms;android-34' 'build-tools;34.0.0' 'ndk;27.0.12077973'
      if (-not (Test-Path "$Sdk\ndk\27.0.12077973")) { throw 'NDK installation failed - see log above' }
    } else { Write-Host '  SDK/NDK already installed.' -ForegroundColor Green }
    $env:ANDROID_HOME = $Sdk
    $env:NDK_HOME     = Join-Path $Sdk 'ndk\27.0.12077973'
    $env:Path         = "$Sdk\platform-tools;$env:Path"
  }

  # ================================================================
  # [5/9] Node.js + npm
  # ================================================================
  Step 5 'Node.js / npm'
  $sysNpm = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($sysNpm) {
    $npm = $sysNpm.Source
    $npx = (Get-Command npx.cmd -ErrorAction Stop).Source
    $nodeDir = Split-Path $npm -Parent
    Write-Host '  using system Node/npm.' -ForegroundColor Green
  } else {
    $nodeRoot = "$env:USERPROFILE\sb-client-node20"
    $nodeDir  = Join-Path $nodeRoot 'node-v20.18.1-win-x64'
    if (-not (Test-Path (Join-Path $nodeDir 'npm.cmd'))) {
      Get-File 'https://nodejs.org/dist/v20.18.1/node-v20.18.1-win-x64.zip' "$env:TEMP\node20.zip"
      Write-Host '  extracting Node...'
      Expand-Archive "$env:TEMP\node20.zip" $nodeRoot -Force
      Remove-Item "$env:TEMP\node20.zip" -Force -ErrorAction SilentlyContinue
    }
    $npm = Join-Path $nodeDir 'npm.cmd'
    $npx = Join-Path $nodeDir 'npx.cmd'
    Write-Host '  using portable Node 20.' -ForegroundColor Green
  }
  if ($nodeDir -and (Test-Path $nodeDir) -and ($env:Path -notlike "*$nodeDir*")) {
    $env:Path = "$nodeDir;$env:Path"
  }
  Push-Location $Root
  & $npm install --no-audit --no-fund
  Pop-Location

  # ================================================================
  # [6/9] Android project: init + icons + fullscreen patch + signing key
  # ================================================================
  if ($doAndroid) {
    Step 6 'Preparing Android project'
    if (-not (Test-Path "$Root\src-tauri\gen\android")) {
      Write-Host '  tauri android init...'
      & $npx tauri android init
      if (-not (Test-Path "$Root\src-tauri\gen\android")) { throw 'tauri android init failed - see log above' }
    } else { Write-Host '  project already initialized.' -ForegroundColor Green }

    $iconSrc = Join-Path $Root 'branding\app-icon\android'
    $resDst  = Join-Path $Root 'src-tauri\gen\android\app\src\main\res'
    foreach ($d in 'mipmap-mdpi','mipmap-hdpi','mipmap-xhdpi','mipmap-xxhdpi','mipmap-xxxhdpi') {
      $dst = Join-Path $resDst $d
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Copy-Item (Join-Path $iconSrc "$d\*.png") $dst -Force
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $resDst 'values') | Out-Null
    Copy-Item (Join-Path $iconSrc 'values\ic_launcher_background.xml') (Join-Path $resDst 'values') -Force
    Write-Host '  icons applied.' -ForegroundColor Green

    $main = Get-ChildItem "$Root\src-tauri\gen\android\app\src\main\java" -Recurse -Filter 'MainActivity.kt' | Select-Object -First 1
    if ($main) {
      $kt = Get-Content $main.FullName -Raw
      if ($kt -notmatch 'onWindowFocusChanged') {
        $inject = @"

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            window.decorView.systemUiVisibility = (
                android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        }
    }
"@
        $kt = $kt -replace '(class MainActivity[^\r\n]*\{)', "`$1`r`n$inject"
        Set-Content -Path $main.FullName -Value $kt -Encoding UTF8 -NoNewline
        Write-Host '  immersive fullscreen patch applied.' -ForegroundColor Green
      }
    }

    $gp = "$Root\src-tauri\gen\android\gradle.properties"
    if ((Test-Path $gp) -and -not (Select-String -Path $gp -Pattern 'org.gradle.jvmargs' -Quiet)) {
      Add-Content $gp "`norg.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m"
    }

    $ksDir = Join-Path $Root 'keystore'
    New-Item -ItemType Directory -Force -Path $ksDir | Out-Null
    $ks = if ($env:SB_KEYSTORE_PATH) { $env:SB_KEYSTORE_PATH } else { Join-Path $ksDir 'sbclient.jks' }
    $storePass = $env:SB_KEYSTORE_PASSWORD
    $keyPass   = if ($env:SB_KEY_PASSWORD) { $env:SB_KEY_PASSWORD } else { $storePass }
    $aliasName = if ($env:SB_KEY_ALIAS) { $env:SB_KEY_ALIAS } else { 'sbclient' }
    if (-not (Test-Path $ks)) {
      if (-not $storePass) {
        throw 'SB_KEYSTORE_PASSWORD is not set. Set it (or use GitHub Secrets) before generating a key.'
      }
      Write-Host '  generating APK signing key...'
      & "$javaHome\bin\keytool.exe" -genkeypair -v -keystore $ks -alias $aliasName `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -storepass $storePass -keypass $keyPass `
        -dname 'CN=SB Client, OU=ggshnikk, O=ggshnikk, L=RU, ST=RU, C=RU'
      if ($LASTEXITCODE -ne 0) { throw 'keytool failed' }
    }
    if ($storePass) {
      $env:TAURI_ANDROID_KEYSTORE_PATH        = $ks
      $env:TAURI_ANDROID_KEYSTORE_PASSWORD    = $storePass
      $env:TAURI_ANDROID_KEY_ALIAS            = $aliasName
      $env:TAURI_ANDROID_PRIVATE_KEY_PASSWORD = $keyPass
    } else {
      Write-Warning '  SB_KEYSTORE_PASSWORD missing: release APK cannot be signed. Use debug build or add the secret.'
    }
  }

  # ================================================================
  # [7/9] Android APK
  # ================================================================
  if ($doAndroid) {
    Step 7 'Building Android APK (aarch64 + armv7)'
    Push-Location $Root
    & $npx tauri android build --apk --target aarch64 --target armv7
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
      Write-Warning "release build failed (exit $rc), trying debug build..."
      & $npx tauri android build --apk --debug
      if ($LASTEXITCODE -ne 0) { throw "Android build failed (debug too), exit $LASTEXITCODE" }
    }
    Pop-Location
    # v1.5: Tauri CLI does not sign APKs - sign them here (zipalign + apksigner)
    Sign-AndroidApks -Root $Root -Ver $Ver
  }

  # ================================================================
  # [8/9] Windows version
  # ================================================================
  if ($doWindows) {
    Step 8 'Building Windows version (NSIS)'
    Push-Location $Root
    & $npx tauri build
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed, exit $LASTEXITCODE" }
    Pop-Location
  }

  # ================================================================
  # [9/9] Collect artifacts
  # ================================================================
  Step 9 'Collecting artifacts'
  New-Item -ItemType Directory -Force -Path $Dist | Out-Null
  Remove-Item (Join-Path $Dist 'FAILED.txt') -Force -ErrorAction SilentlyContinue
  Get-ChildItem "$Root\src-tauri\target\release\bundle\nsis" -Filter *.exe -ErrorAction SilentlyContinue |
    Copy-Item -Destination $Dist -Force
  Get-ChildItem "$Root\src-tauri\target\release" -Filter 'sb-client.exe' -ErrorAction SilentlyContinue |
    ForEach-Object { Copy-Item $_.FullName (Join-Path $Dist 'SB Client.exe') -Force }
  Get-ChildItem "$Root\src-tauri\gen\android\app\build\outputs\apk" -Recurse -Filter *.apk -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch 'unsigned' } |
    Copy-Item -Destination $Dist -Force

  $list = Get-ChildItem $Dist -ErrorAction SilentlyContinue | ForEach-Object { "{0}  ({1:N1} MB)" -f $_.Name, ($_.Length / 1MB) }
  if ($list) {
    $body = "SB Client - build finished: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`r`n`r`n" + ($list -join "`r`n") +
            "`r`n`r`nInstall APK on the phone (allow unknown sources once).`r`n" +
            "Keystore password is NOT stored in the repo: set SB_KEYSTORE_PASSWORD.`r`n" +
            "KEEP the keystore folder - future updates must be signed with the same key."
    Set-Content -Path (Join-Path $Dist 'READY.txt') -Value $body -Encoding UTF8
    Write-Host ''
    Write-Host 'DONE. Artifacts:' -ForegroundColor Green
    $list | ForEach-Object { Write-Host "  $_" }
    Write-Host "Folder: $Dist"
  } else {
    throw 'No artifacts found - check build.log above.'
  }
} catch {
  Write-Host ''
  Write-Host "ERROR: $_" -ForegroundColor Red
  Write-Crash ("$_`r`n`r`n$($_.ScriptStackTrace)")
  try {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root 'dist') -ErrorAction SilentlyContinue | Out-Null
    Set-Content -Path (Join-Path $Root 'dist\FAILED.txt') -Value "Build failed: $(Get-Date -Format 'dd.MM.yyyy HH:mm')`r`n$_`r`nDetails: build.log" -Encoding UTF8 -ErrorAction SilentlyContinue
  } catch {}
  Write-Host ''
  Write-Host 'The window stays open. Press ENTER to close.' -ForegroundColor Yellow
  if (-not $env:SB_CLIENT_NOPAUSE) { Read-Host 'Press ENTER to close' | Out-Null }
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
