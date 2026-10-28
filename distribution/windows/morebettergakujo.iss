; Inno Setup script for the Flutter Windows release bundle.
; Build the bundle first:
;   flutter build windows --release
;
; Then compile this file with Inno Setup on Windows.

#ifndef MyAppId
#define MyAppId "{{30C656ED-D1B4-4FDD-A731-43851D4EB506}"
#endif

#ifndef MyAppRegistryId
#define MyAppRegistryId "{30C656ED-D1B4-4FDD-A731-43851D4EB506}"
#endif

#define MyAppName "More Better Gakujo"

#ifndef MyAppVersion
#define MyAppVersion "0.67.0"
#endif

#ifndef MyAppVersionInfo
#define MyAppVersionInfo "0.67.0.67"
#endif

#define MyAppPublisher "net.yoshida"
#define MyAppExeName "morebettergakujo_flutter.exe"

#ifndef MyBuildDir
#define MyBuildDir "..\..\build\windows\x64\runner\Release"
#endif

#ifndef MyOutputDir
#define MyOutputDir "..\..\dist\windows"
#endif

#ifndef MyOutputBaseFilename
#define MyOutputBaseFilename "MoreBetterGakujo-v" + MyAppVersion
#endif

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir={#MyOutputDir}
OutputBaseFilename={#MyOutputBaseFilename}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
CloseApplicationsFilter={#MyAppExeName}
RestartIfNeededByRun=no
VersionInfoVersion={#MyAppVersionInfo}

[Languages]
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Debug builds from older releases can leave these behind during an upgrade.
; Files present in the new build are copied back by the [Files] section.
Type: files; Name: "{app}\morebettergakujo_flutter.pdb"
Type: files; Name: "{app}\data\flutter_assets\kernel_blob.bin"

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Registry]
Root: HKCU; Subkey: "Software\Yoshida\MoreBetterGakujo"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Yoshida"; Flags: uninsdeletekeyifempty
Root: HKA; Subkey: "Software\Classes\AppUserModelId\Yoshida.MoreBetterGakujo"; ValueType: string; ValueName: "DisplayName"; ValueData: "More Better Gakujo"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\morebettergakujo"; ValueType: string; ValueName: ""; ValueData: "URL:More Better Gakujo"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\morebettergakujo"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\morebettergakujo\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; AppUserModelID: "Yoshida.MoreBetterGakujo"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
