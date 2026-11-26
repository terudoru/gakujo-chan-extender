$ErrorActionPreference = 'Stop'

$safeTagName = "${env:RELEASE_TAG}" -replace '[^A-Za-z0-9._-]', '-'
$appVersion = $safeTagName -replace '^[vV]', ''
$versionNumbers = @([regex]::Matches($appVersion, '\d+') | ForEach-Object { $_.Value })
while ($versionNumbers.Count -lt 4) {
  $versionNumbers += "0"
}
$versionInfo = ($versionNumbers | Select-Object -First 4) -join "."

$releaseDir = "build\windows\x64\runner\Release"
if (-not (Test-Path $releaseDir)) {
  $releaseDir = "build\windows\runner\Release"
}
if (-not (Test-Path $releaseDir)) {
  throw "Windows release output directory was not found."
}

# Use the release checkout's working directory, including for the .iss inputs.
$releaseDir = (Resolve-Path $releaseDir).Path
$outputBaseName = "${env:APP_NAME}-$safeTagName"
New-Item -ItemType Directory -Force -Path "dist" | Out-Null
Compress-Archive -Path "$releaseDir\*" -DestinationPath "dist\$outputBaseName.zip" -Force

$installerScript = (Resolve-Path "distribution\windows\morebettergakujo.iss").Path
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" `
  $installerScript `
  "/DMyBuildDir=$releaseDir" `
  "/DMyOutputDir=$((Resolve-Path dist).Path)" `
  "/DMyAppVersion=$appVersion" `
  "/DMyAppVersionInfo=$versionInfo" `
  "/DMyOutputBaseFilename=$outputBaseName"
exit $LASTEXITCODE
