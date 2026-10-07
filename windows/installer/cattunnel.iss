; CatTunnel installer (Inno Setup 6). Also the in-app update: the app runs it
; with /VERYSILENT /SUPPRESSMSGBOXES /NORESTART (UpdatePlatform.install) and
; quits; Setup closes what is still running, replaces the files and starts
; CatTunnel again.
;
;   iscc /DAppVersion=1.4.5 /DBuildDir=..\..\build\windows\x64\runner\Release windows\installer\cattunnel.iss
;
; AppId must never change - it's how Windows knows an update from a new app.

#ifndef AppVersion
  #error Pass /DAppVersion=<x.y.z>
#endif
#ifndef BuildDir
  #define BuildDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{70D11BF1-614C-4D9C-BB84-61D60AC2D8C2}
AppName=CatTunnel
AppVersion={#AppVersion}
AppPublisher=CatTunnel
DefaultDirName={autopf}\CatTunnel
DefaultGroupName=CatTunnel
DisableProgramGroupPage=yes
; The VPN (wintun) needs administrator rights anyway.
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir=..\..\build\installer
OutputBaseFilename=CatTunnel-{#AppVersion}-Setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\cattunnel.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Updates replace files of a running app (and of trusttunnel_client.exe).
CloseApplications=force
RestartApplications=no

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\CatTunnel"; Filename: "{app}\cattunnel.exe"
Name: "{autodesktop}\CatTunnel"; Filename: "{app}\cattunnel.exe"; Tasks: desktopicon

[Run]
; Runs after a silent update too (no skipifsilent): the app comes back.
Filename: "{app}\cattunnel.exe"; Description: "{cm:LaunchProgram,CatTunnel}"; Flags: nowait postinstall

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM trusttunnel_client.exe"; Flags: runhidden; RunOnceId: "StopClient"
