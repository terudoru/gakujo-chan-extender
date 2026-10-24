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

[Code]
const
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#MyAppRegistryId}_is1';

var
  PreviousUninstaller: String;

function RemoveOuterQuotes(Value: String): String;
begin
  Result := Value;
  if (Length(Result) >= 2) and (Copy(Result, 1, 1) = '"') and
     (Copy(Result, Length(Result), 1) = '"') then begin
    Result := Copy(Result, 2, Length(Result) - 2);
  end;
end;

function TryGetPreviousInstall(var UninstallString: String; var DisplayVersion: String): Boolean;
var
  InstallLocation: String;
  UninstallerName: String;
begin
  Result := False;
  // Never execute an HKCU command with the installer's elevated privileges.
  if not RegQueryStringValue(HKLM, UninstallKey, 'UninstallString', UninstallString) then begin
    exit;
  end;

  UninstallString := RemoveOuterQuotes(Trim(UninstallString));
  if (Copy(UninstallString, 2, 2) <> ':\') or not FileExists(UninstallString) then begin
    exit;
  end;
  UninstallString := ExpandFileName(UninstallString);
  UninstallerName := Lowercase(ExtractFileName(UninstallString));
  if (Copy(UninstallerName, 1, 5) <> 'unins') or
     (ExtractFileExt(UninstallerName) <> '.exe') then begin
    exit;
  end;

  if not RegQueryStringValue(HKLM, UninstallKey, 'InstallLocation', InstallLocation) or
     (Trim(InstallLocation) = '') then begin
    InstallLocation := ExpandConstant('{commonpf}\{#MyAppName}');
  end;
  InstallLocation := RemoveOuterQuotes(Trim(InstallLocation));
  if Copy(InstallLocation, 2, 2) <> ':\' then begin
    exit;
  end;
  InstallLocation := RemoveBackslashUnlessRoot(ExpandFileName(InstallLocation));
  if CompareText(ExtractFileDir(UninstallString), InstallLocation) <> 0 then begin
    exit;
  end;

  RegQueryStringValue(HKLM, UninstallKey, 'DisplayVersion', DisplayVersion);
  Result := True;
end;

function InitializeSetup(): Boolean;
var
  UninstallString: String;
  DisplayVersion: String;
  MessageText: String;
begin
  Result := True;

  if not TryGetPreviousInstall(UninstallString, DisplayVersion) then begin
    exit;
  end;

  if DisplayVersion <> '' then begin
    MessageText :=
      '既存の More Better Gakujo ' + DisplayVersion + ' が見つかりました。' + #13#10#13#10 +
      '古いバージョンを削除してから新しいバージョンをインストールしますか？';
  end else begin
    MessageText :=
      '既存の More Better Gakujo が見つかりました。' + #13#10#13#10 +
      '古いバージョンを削除してから新しいバージョンをインストールしますか？';
  end;

  if MsgBox(MessageText, mbConfirmation, MB_YESNO) <> IDYES then begin
    exit;
  end;

  PreviousUninstaller := UninstallString;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  UninstallString: String;
  DisplayVersion: String;
  ErrorCode: Integer;
begin
  if (CurStep <> ssInstall) or (PreviousUninstaller = '') then begin
    exit;
  end;
  // Revalidate the approved machine entry after the user commits to installing.
  if not TryGetPreviousInstall(UninstallString, DisplayVersion) then begin
    exit;
  end;
  if CompareText(UninstallString, PreviousUninstaller) <> 0 then begin
    exit;
  end;
  PreviousUninstaller := '';
  if not Exec(
    UninstallString,
    '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART',
    '',
    SW_SHOW,
    ewWaitUntilTerminated,
    ErrorCode
  ) then begin
    RaiseException(
      '古いバージョンの削除を開始できませんでした。インストールを中止します。'
    );
  end;

  if ErrorCode <> 0 then begin
    RaiseException(
      '古いバージョンの削除に失敗しました。インストールを中止します。' + #13#10 +
      '終了コード: ' + IntToStr(ErrorCode)
    );
  end;
end;
