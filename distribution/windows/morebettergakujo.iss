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
#ifdef InstallerTestMode
AppId={{89144F42-FA57-47AA-A155-3046DF8F26B7}
#else
AppId={#MyAppId}
#endif
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
#ifdef InstallerTestMode
PrivilegesRequired=lowest
CreateUninstallRegKey=no
#else
PrivilegesRequired=admin
#endif
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
Type: files; Name: "{app}\morebettergakujo_flutter.pdb"; Check: CanRemoveLegacy('morebettergakujo_flutter.pdb')
Type: files; Name: "{app}\data\flutter_assets\kernel_blob.bin"; Check: CanRemoveLegacy('data\flutter_assets\kernel_blob.bin')

[UninstallDelete]
Type: files; Name: "{app}\.mbg-installed-files.txt"
Type: files; Name: "{app}\.mbg-installed-files.txt.tmp"

[Files]
Source: "{#MyBuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; AfterInstall: RecordInstalledFile

#ifndef InstallerTestMode
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
#endif

[Code]
const
  ManifestName = '.mbg-installed-files.txt';
  ReparsePoint = $400;
  DirectoryAttribute = $10;
  InvalidAttributes = $FFFFFFFF;

var
  PreviousFiles, CurrentFiles: TArrayOfString;
  TrackingOK: Boolean;

function GetFileAttributesW(Name: String): LongWord;
  external 'GetFileAttributesW@kernel32.dll stdcall';
function MoveFileExW(ExistingName, NewName: String; Flags: LongWord): Boolean;
  external 'MoveFileExW@kernel32.dll stdcall';

function TrustedRoot: Boolean;
var Root, Expected: String;
begin
  Root := RemoveBackslashUnlessRoot(ExpandFileName(ExpandConstant('{app}')));
#ifdef InstallerTestMode
  Expected := RemoveBackslashUnlessRoot(ExpandFileName('{#InstallerTestRoot}'));
#else
  Expected := RemoveBackslashUnlessRoot(ExpandFileName(ExpandConstant('{autopf}\{#MyAppName}')));
#endif
  Result := CompareText(Root, Expected) = 0;
end;

function SafeFile(RelativeName: String): Boolean;
var Root, Part, Tail, Current: String; P: Integer; Attr: LongWord;
begin
  Result := False;
  if not TrustedRoot then exit;
  if RelativeName = '' then exit;
  if (RelativeName[1] = '\') or (Pos('/', RelativeName) > 0) or (Pos(':', RelativeName) > 0) or
     (Pos('|', RelativeName) > 0) or (Pos('\\', RelativeName) > 0) or
     (Pos('\..\', '\' + RelativeName + '\') > 0) or
     (Pos('\.\', '\' + RelativeName + '\') > 0) then exit;
  Root := RemoveBackslashUnlessRoot(ExpandFileName(ExpandConstant('{app}')));
  Current := Root;
  Attr := GetFileAttributesW(Current);
  if (Attr = InvalidAttributes) or ((Attr and ReparsePoint) <> 0) then exit;
  Tail := RelativeName;
  while True do begin
    P := Pos('\', Tail);
    if P = 0 then Part := Tail else Part := Copy(Tail, 1, P - 1);
    if Part = '' then exit;
    if (Part[Length(Part)] = '.') or (Part[Length(Part)] = ' ') then exit;
    Current := Current + '\' + Part;
    Attr := GetFileAttributesW(Current);
    if (Attr = InvalidAttributes) or ((Attr and ReparsePoint) <> 0) then exit;
    if P = 0 then begin
      Result := (Attr and DirectoryAttribute) = 0;
      exit;
    end;
    if (Attr and DirectoryAttribute) = 0 then exit;
    Delete(Tail, 1, P);
  end;
end;

function CanRemoveLegacy(RelativeName: String): Boolean;
begin
  Result := SafeFile(RelativeName);
end;

function RecordedPath(const Entry: String): String;
begin
  Result := '';
  if Length(Entry) > 65 then
    if Entry[65] = '|' then Result := Copy(Entry, 66, MaxInt);
end;

function IsCurrent(const RelativeName: String): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to GetArrayLength(CurrentFiles) - 1 do
    if CompareText(RecordedPath(CurrentFiles[I]), RelativeName) = 0 then begin
      Result := True;
      exit;
    end;
end;

procedure AddCurrent(const Entry: String);
var N: Integer;
begin
  N := GetArrayLength(CurrentFiles);
  SetArrayLength(CurrentFiles, N + 1);
  CurrentFiles[N] := Entry;
end;

procedure RecordInstalledFile;
var Root, FullName, RelativeName: String;
begin
  if not TrustedRoot then exit;
  Root := AddBackslash(RemoveBackslashUnlessRoot(ExpandFileName(ExpandConstant('{app}'))));
  FullName := ExpandFileName(ExpandConstant(CurrentFilename));
  if CompareText(Copy(FullName, 1, Length(Root)), Root) <> 0 then begin
    TrackingOK := False;
    exit;
  end;
  RelativeName := Copy(FullName, Length(Root) + 1, MaxInt);
  if not SafeFile(RelativeName) then begin
    TrackingOK := False;
    exit;
  end;
  try
    AddCurrent(GetSHA256OfFile(FullName) + '|' + RelativeName);
  except
    TrackingOK := False;
    Log('Could not record installed file: ' + RelativeName);
  end;
end;

procedure RemoveEmptyParents(const FullName: String);
var Root, Parent: String;
begin
  Root := RemoveBackslashUnlessRoot(ExpandFileName(ExpandConstant('{app}')));
  Parent := ExtractFileDir(FullName);
  while (CompareText(Parent, Root) <> 0) and
        (CompareText(Copy(Parent, 1, Length(Root) + 1), Root + '\') = 0) do begin
    if not RemoveDir(Parent) then exit;
    Parent := ExtractFileDir(Parent);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var I: Integer; RelativeName, FullName, Manifest, Temporary: String;
begin
  if CurStep = ssInstall then begin
    TrackingOK := True;
    SetArrayLength(PreviousFiles, 0);
    SetArrayLength(CurrentFiles, 0);
    if SafeFile(ManifestName) then
      if not LoadStringsFromFile(ExpandConstant('{app}\') + ManifestName, PreviousFiles) then
        TrackingOK := False;
  end;
  if (CurStep <> ssPostInstall) or not TrustedRoot or not TrackingOK then exit;
  for I := 0 to GetArrayLength(PreviousFiles) - 1 do begin
    RelativeName := RecordedPath(PreviousFiles[I]);
    if (RelativeName <> '') and not IsCurrent(RelativeName) and SafeFile(RelativeName) then begin
      FullName := AddBackslash(ExpandConstant('{app}')) + RelativeName;
      try
        if CompareText(GetSHA256OfFile(FullName), Copy(PreviousFiles[I], 1, 64)) = 0 then begin
          if DeleteFile(FullName) then
            RemoveEmptyParents(FullName)
          else begin
            Log('Could not remove obsolete installed file: ' + RelativeName);
            AddCurrent(PreviousFiles[I]);
          end;
        end else
          Log('Preserved changed file: ' + RelativeName);
      except
        Log('Could not inspect obsolete installed file: ' + RelativeName);
        AddCurrent(PreviousFiles[I]);
      end;
    end;
  end;
  Manifest := AddBackslash(ExpandConstant('{app}')) + ManifestName;
  Temporary := Manifest + '.tmp';
  if SaveStringsToUTF8File(Temporary, CurrentFiles, False) then begin
    if not MoveFileExW(Temporary, Manifest, 9) then
      Log('Could not replace installed-file manifest.');
  end else
    Log('Could not write installed-file manifest.');
end;
