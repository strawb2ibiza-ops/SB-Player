#define MyAppName "SB Player"
#define MyAppVersion "0.6.10"
#define MyAppPublisher "SB Player"
#define MyAppExeName "sb_player.exe"

[Setup]
AppId={{B52D97D0-60DE-4D78-A882-A4F0770BE505}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} v{#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\SB Player
DefaultGroupName=SB Player
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=SB-Player-Setup-v0.6.10
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
UsePreviousAppDir=yes
UsePreviousGroup=yes
UsePreviousTasks=yes
Uninstallable=yes
CreateUninstallRegKey=yes
ChangesAssociations=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; App data and secure account/profile storage live outside {app}; upgrades do not delete them.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\SB Player"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\SB Player"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch SB Player"; Flags: nowait postinstall skipifsilent
