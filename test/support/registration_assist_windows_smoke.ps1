# Build an independent Flutter runner under build/ and use a new WebView2
# profile on every run. The Dart host denies network access before navigation.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
# Keep MSVC's generated plugin include paths below MAX_PATH in worktrees.
$hostDir = Join-Path $root 'build/reg_smoke_host'
$manifest = Join-Path $hostDir 'pubspec.yaml'
if (!(Test-Path -LiteralPath $manifest)) {
    flutter create --no-pub --platforms=windows --empty --project-name registration_smoke $hostDir
    if ($LASTEXITCODE) { throw 'Could not create the registration fixture host' }
}
if (!(Select-String -LiteralPath $manifest -Pattern '^name: registration_smoke$' -Quiet)) {
    throw 'Expected the dedicated registration_smoke fixture project'
}
@'
name: registration_smoke
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  flutter_test:
    sdk: flutter
  flutter_secure_storage: ^11.2.0
  morebettergakujo_flutter:
    path: ../..
  webview_flutter_windows:
    path: ../../third_party/webview_flutter_windows
dependency_overrides:
  flutter_secure_storage_windows:
    path: ../../third_party/flutter_secure_storage_windows
  flutter_secure_storage_darwin:
    path: ../../third_party/flutter_secure_storage_darwin
flutter:
  uses-material-design: true
'@ | Set-Content -LiteralPath $manifest -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'registration_assist_windows_smoke.dart') -Destination (Join-Path $hostDir 'lib/main.dart')
$nativeBuild = Join-Path $hostDir 'build/windows/x64'
$cachedBuild = Join-Path $root 'build/windows/x64'
New-Item -ItemType Directory -Path $nativeBuild -Force | Out-Null
foreach ($dependency in @('nuget.exe', 'packages')) {
    if (!(Test-Path -LiteralPath (Join-Path $nativeBuild $dependency))) {
        Copy-Item -LiteralPath (Join-Path $cachedBuild $dependency) -Destination $nativeBuild -Recurse
    }
}
foreach ($marker in @(
    'packages/Microsoft.Web.WebView2/build/native/Microsoft.Web.WebView2.targets',
    'packages/Microsoft.Windows.ImplementationLibrary/build/native/Microsoft.Windows.ImplementationLibrary.targets'
)) {
    if (!(Test-Path -LiteralPath (Join-Path $nativeBuild $marker) -PathType Leaf)) {
        throw "Missing offline Windows build dependency: $marker"
    }
}
Push-Location -LiteralPath $hostDir
$previousRunDir = $env:MBG_REGISTRATION_SMOKE_DIR
try {
    flutter pub get --offline
    if ($LASTEXITCODE) { throw 'Could not prepare the offline fixture dependencies' }
    flutter build windows --debug --no-pub
    if ($LASTEXITCODE) { throw 'Could not build the registration fixture host' }
    $runDir = New-Item -ItemType Directory -Path (Join-Path $hostDir ([Guid]::NewGuid().ToString('N')))
    $env:MBG_REGISTRATION_SMOKE_DIR = $runDir.FullName
    $exe = (Resolve-Path 'build/windows/x64/runner/Debug/registration_smoke.exe').Path
    $proc = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden -PassThru
    if (!$proc.WaitForExit(90000)) {
        $proc.Kill()
        throw "The registration fixture timed out ($runDir)"
    }
    $proof = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $runDir.FullName 'result.txt')
    if ($proc.ExitCode -ne 0 -or !$proof.StartsWith('Verified Windows WebView2 registration preview')) {
        throw "The registration smoke failed ($runDir): $proof"
    }
    Write-Output $proof
    Write-Output (Join-Path $runDir.FullName 'result.txt')
} finally {
    $env:MBG_REGISTRATION_SMOKE_DIR = $previousRunDir
    Pop-Location
}
