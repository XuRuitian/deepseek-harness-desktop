; DeepSeekHarness-Setup.iss - Inno Setup script for the DeepSeek Harness desktop app.
; Compile with ISCC.exe (Inno Setup 6):  iscc DSHSetup.iss

#define MyAppName "DeepSeek Harness"
#define MyAppVersion "0.1.0-rc.6"
#define MyAppPublisher "DeepSeek"
#define MyAppURL "https://github.com/XuRuitian/deepseek-harness-desktop"

[Setup]
AppId={{C6D84E2F-5B7A-4F9E-8A3D-1E6B9C4D7F21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={localappdata}\DeepSeekHarness
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=DeepSeekHarness-Setup-{#MyAppVersion}
SetupIconFile=..\build\payload\DSH.ico
UninstallDisplayIcon={app}\DSH.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
MinVersion=10.0
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
CreateStartMenuEntry=Create a Start &Menu entry

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "startmenuicon"; Description: "{cm:CreateStartMenuEntry}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\build\payload\app\*"; DestDir: "{app}\app"; Flags: recursesubdirs createallsubdirs
Source: "..\build\payload\Launch.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\payload\Stop.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\payload\README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\payload\DSH.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autodesktop}\{#MyAppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Launch.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\DSH.ico"; Tasks: desktopicon
Name: "{autoprograms}\{#MyAppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Launch.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\DSH.ico"; Tasks: startmenuicon
Name: "{autoprograms}\Stop {#MyAppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Stop.ps1"""; WorkingDir: "{app}"; IconFilename: "{app}\DSH.ico"; Tasks: startmenuicon

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Launch.ps1"""; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
function RemoveQuotes(const S: string): string;
begin
  Result := S;
  StringChange(Result, '"', '');
end;

function DirHasNode(const Dir: string): Boolean;
begin
  Result := (Dir <> '') and FileExists(AddBackslash(Dir) + 'node.exe');
end;

function SearchPathForNode(const PathVar: string): Boolean;
var
  I, Start: Integer;
  Dir: string;
begin
  Result := False;
  Start := 1;
  for I := 1 to Length(PathVar) do
  begin
    if PathVar[I] = ';' then
    begin
      Dir := RemoveQuotes(Copy(PathVar, Start, I - Start));
      Start := I + 1;
      if DirHasNode(Dir) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;
  Dir := RemoveQuotes(Copy(PathVar, Start, Length(PathVar) - Start + 1));
  Result := DirHasNode(Dir);
end;

function InitializeSetup(): Boolean;
var
  Found: Boolean;
begin
  Found := DirHasNode(ExpandConstant('{pf}\nodejs'))
        or DirHasNode(ExpandConstant('{pf32}\nodejs'))
        or DirHasNode(GetEnv('LOCALAPPDATA') + '\Programs\nodejs')
        or DirHasNode(GetEnv('APPDATA') + '\nvm\current')
        or SearchPathForNode(GetEnv('PATH'));
  if not Found then
  begin
    Result := MsgBox('Node.js was not found on this computer.' + #13#10 +
      'DeepSeek Harness needs Node.js to run (https://nodejs.org).' + #13#10 + #13#10 +
      'Continue the installation anyway? (You can install Node.js later.)',
      mbConfirmation, MB_YESNO) = IDYES;
  end
    else
    begin
      Result := True;
    end;
end;
