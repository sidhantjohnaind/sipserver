; =====================================================================
; JioFiber SIP B2BUA - Inno Setup 6 Script
; =====================================================================

#define MyAppName "JioFiber SIP B2BUA"
#define MyAppVersion "1.3.0"
#define MyAppPublisher "Sidhant"
#define MyAppURL "https://github.com/sidhantjohnaind/sipserver"
#define MyAppExeName "b2bua_msvc.exe"

[Setup]
AppId={{00000000-0000-1000-8000-00001AE07D9A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\JioFiberB2BUA
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=.
OutputBaseFilename=JioFiber_B2BUA_Setup_x64
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayName={#MyAppName}
UninstallFilesDir={app}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "bin\windows-x64\b2bua_msvc.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "view_logs.bat"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "run_windows.bat"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName} (Console)"; Filename: "{app}\b2bua_msvc.exe"; Parameters: "--console"
Name: "{group}\View Logs"; Filename: "{app}\view_logs.bat"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\b2bua_msvc.exe"; Parameters: "--console"; Tasks: desktopicon

[Run]
; Configure Firewall Rules
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""JioFiber B2BUA SIP UDP"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""JioFiber B2BUA SIP UDP"" dir=in action=allow protocol=UDP localport=5061"; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""JioFiber B2BUA RTP Media UDP"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""JioFiber B2BUA RTP Media UDP"" dir=in action=allow protocol=UDP localport=4000-4050,52000-52200"; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""JioFiber B2BUA App"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall add rule name=""JioFiber B2BUA App"" dir=in action=allow program=""{app}\{#MyAppExeName}"" enable=yes"; Flags: runhidden

; Create & Start Windows Service
Filename: "sc.exe"; Parameters: "stop JioFiberB2BUA"; Flags: runhidden
Filename: "sc.exe"; Parameters: "delete JioFiberB2BUA"; Flags: runhidden
Filename: "sc.exe"; Parameters: "create JioFiberB2BUA binPath= """"{app}\{#MyAppExeName}"""" start= auto DisplayName= ""JioFiber SIP B2BUA Service"""; Flags: runhidden
Filename: "sc.exe"; Parameters: "description JioFiberB2BUA ""Lightweight native SIP B2BUA proxy for JioFiber VoIP"""; Flags: runhidden
Filename: "sc.exe"; Parameters: "failure JioFiberB2BUA reset= 86400 actions= restart/5000/restart/5000/restart/5000"; Flags: runhidden
Filename: "sc.exe"; Parameters: "start JioFiberB2BUA"; Flags: runhidden nowait

[UninstallRun]
Filename: "sc.exe"; Parameters: "stop JioFiberB2BUA"; Flags: runhidden
Filename: "sc.exe"; Parameters: "delete JioFiberB2BUA"; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""JioFiber B2BUA SIP UDP"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""JioFiber B2BUA RTP Media UDP"""; Flags: runhidden
Filename: "netsh"; Parameters: "advfirewall firewall delete rule name=""JioFiber B2BUA App"""; Flags: runhidden
