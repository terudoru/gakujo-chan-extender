# Use Flutter's stock runner, a fresh WebView2 profile and synthetic localhost
# data. The installed application's instance and protocol registration are separate.
# With -PlannerDist <built site/planner>, verify capture, React review and durable save.
# Add -SyncProject <course_planner> to test the same build in WebView2 and Chrome.
# The corresponding public UI reference is node course_planner/tools/check-planner-sync.mjs --dist <built site/planner>.
param([string]$PlannerDist, [string]$SyncProject)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$dist = if ($PlannerDist) {
    $resolved = (Resolve-Path -LiteralPath $PlannerDist).Path
    if (!(Test-Path -LiteralPath (Join-Path $resolved 'index.html') -PathType Leaf)) {
        throw 'PlannerDist must contain the compiled planner index.html'
    }
    $resolved
}
$syncRoot = if ($SyncProject) {
    if (!$dist) { throw 'SyncProject requires a compiled PlannerDist' }
    $resolvedProject = (Resolve-Path -LiteralPath $SyncProject).Path
    if (!(Test-Path -LiteralPath (Join-Path $resolvedProject 'sync/relay.mjs') -PathType Leaf)) {
        throw 'SyncProject must contain the local planner relay'
    }
    $resolvedProject
}
$hostDir = Join-Path $root 'build/course_planner_smoke_host'
if (!(Test-Path -LiteralPath $hostDir)) {
    flutter create --no-pub --platforms=windows --empty --project-name planner_smoke $hostDir
    if ($LASTEXITCODE) { throw 'Could not create the fixture host' }
}
$manifest = Join-Path $hostDir 'pubspec.yaml'
if (!(Select-String -LiteralPath $manifest -Pattern '^name: planner_smoke$' -Quiet)) {
    throw 'Expected the dedicated planner_smoke fixture project'
}
@'
name: planner_smoke
publish_to: none
environment:
  sdk: '>=3.13.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
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
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'course_planner_windows_smoke.dart') -Destination (Join-Path $hostDir 'lib/main.dart') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'course_planner_windows_react_smoke.dart') -Destination (Join-Path $hostDir 'lib/course_planner_windows_react_smoke.dart') -Force
Push-Location -LiteralPath $hostDir
$previousFixture = $env:MBG_PLANNER_SMOKE_DIR
$previousDist = $env:MBG_PLANNER_SMOKE_DIST
$previousSync = $env:MBG_PLANNER_SMOKE_SYNC_PROJECT
$previousDriver = $env:MBG_PLANNER_SMOKE_SYNC_DRIVER
try {
    flutter pub get
    if ($LASTEXITCODE) { throw 'Could not prepare fixture dependencies' }
    flutter build windows --debug --no-pub
    if ($LASTEXITCODE) { throw 'Could not build the fixture host' }
    $runDir = New-Item -ItemType Directory -Path (Join-Path $hostDir ([Guid]::NewGuid().ToString('N')))
    $env:MBG_PLANNER_SMOKE_DIR = $runDir.FullName
    $env:MBG_PLANNER_SMOKE_DIST = $dist
    $env:MBG_PLANNER_SMOKE_SYNC_PROJECT = $syncRoot
    $env:MBG_PLANNER_SMOKE_SYNC_DRIVER = Join-Path $PSScriptRoot 'course_planner_windows_sync.mjs'
    $exe = (Resolve-Path 'build/windows/x64/runner/Debug/planner_smoke.exe').Path
    $proc = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden -PassThru
    $timeout = if ($syncRoot) { 300000 } else { 90000 }
    if (!$proc.WaitForExit($timeout)) {
        $proc.Kill()
        throw 'The fixture did not finish'
    }
    $proof = Get-Content -Raw -LiteralPath (Join-Path $runDir.FullName 'result.txt')
    $expected = if ($syncRoot) { 'Verified WebView2 and Chrome relay edits, history consent and withdrawal' } elseif ($dist) { 'Verified Windows WebView2 React planner capture, consent and persisted grade after reload' } else { 'Verified Windows WebView2 planner review' }
    if ($proc.ExitCode -ne 0 -or $proof -ne $expected) {
        throw "The planner smoke test failed ($proof)"
    }
    Write-Output $proof
} finally {
    $env:MBG_PLANNER_SMOKE_DIR = $previousFixture
    $env:MBG_PLANNER_SMOKE_DIST = $previousDist
    $env:MBG_PLANNER_SMOKE_SYNC_PROJECT = $previousSync
    $env:MBG_PLANNER_SMOKE_SYNC_DRIVER = $previousDriver
    Pop-Location
}
