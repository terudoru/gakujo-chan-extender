param(
  [string]$InnoSetupCompiler
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallerScript = Join-Path $RepoRoot "distribution\windows\morebettergakujo.iss"

if (-not $InnoSetupCompiler) {
  $Candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
  )

  $InnoSetupCompiler = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $InnoSetupCompiler -or -not (Test-Path $InnoSetupCompiler)) {
  throw "ISCC.exe was not found. Install Inno Setup 6 or pass -InnoSetupCompiler path\to\ISCC.exe."
}

Push-Location $RepoRoot
try {
  flutter build windows --release
  & $InnoSetupCompiler $InstallerScript
}
finally {
  Pop-Location
}
