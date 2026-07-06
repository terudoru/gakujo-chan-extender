param(
  [string]$InnoSetupCompiler
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$InstallerScript = Join-Path $RepoRoot "distribution\windows\morebettergakujo.iss"
$Pubspec = Join-Path $RepoRoot "pubspec.yaml"

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
  $PubspecVersion = (Select-String -Path $Pubspec -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value.Trim()
  $AppVersion = ($PubspecVersion -split '\+')[0]
  $VersionNumbers = @([regex]::Matches($AppVersion, '\d+') | ForEach-Object { $_.Value })
  if ($VersionNumbers.Count -eq 0) {
    $VersionNumbers = @("0", "0", "0", "0")
  }
  while ($VersionNumbers.Count -lt 4) {
    $VersionNumbers += "0"
  }
  $VersionInfo = ($VersionNumbers | Select-Object -First 4) -join "."

  flutter build windows --release
  & $InnoSetupCompiler `
    $InstallerScript `
    "/DMyAppVersion=$AppVersion" `
    "/DMyAppVersionInfo=$VersionInfo" `
    "/DMyOutputBaseFilename=MoreBetterGakujo-v$AppVersion"
}
finally {
  Pop-Location
}
