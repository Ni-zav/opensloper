; The Windows installer, built with Inno Setup 6 by opensloper-make.sh package:
;   ISCC /DAppVersion=VERSION /DSourceDir=STAGED /DOutputDir=DIST /DOutputName=NAME opensloper.iss
; SourceDir is the folder the .zip download is made from: the programs, data
; (with the offline user guide in data\help), LICENSE.txt and README.txt.
; SourceDir and OutputDir must be absolute: a relative path is taken from the
; folder of this file.
;
; It installs for all users into Program Files, or for the current user alone
; without administrator rights, as the user chooses; the registry entries
; follow the choice (HKA). The AppId never changes, so a new version replaces
; the old one.

#ifndef AppVersion
  #error AppVersion is not defined
#endif
#ifndef SourceDir
  #error SourceDir is not defined
#endif

[Setup]
AppId={{1CD8944A-BB93-42C4-9DB4-10CDB87B3157}
AppName=OpenSloper
AppVersion={#AppVersion}
AppVerName=OpenSloper {#AppVersion}
AppPublisher=The OpenSloper authors
AppPublisherURL=https://github.com/opensloper/opensloper
AppSupportURL=https://github.com/opensloper/opensloper/issues
AppUpdatesURL=https://github.com/opensloper/opensloper/releases
DefaultDirName={autopf}\OpenSloper
DefaultGroupName=OpenSloper
DisableProgramGroupPage=yes
LicenseFile={#SourceDir}\LICENSE.txt
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
ChangesAssociations=yes
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
SetupIconFile=..\..\src\design\opensloper_design.ico
UninstallDisplayIcon={app}\opensloper-design.exe
UninstallDisplayName=OpenSloper
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; The user guide of the version before
Type: filesandordirs; Name: "{app}\data\help"

[Icons]
Name: "{autoprograms}\OpenSloper"; Filename: "{app}\opensloper-design.exe"
Name: "{autoprograms}\OpenSloper Measurements"; Filename: "{app}\opensloper-measurements.exe"
Name: "{autoprograms}\OpenSloper Publish"; Filename: "{app}\opensloper-publish.exe"
Name: "{autodesktop}\OpenSloper"; Filename: "{app}\opensloper-design.exe"; Tasks: desktopicon

[Registry]
; Each file type opens in its own app
Root: HKA; Subkey: "Software\Classes\.sloper"; ValueType: string; ValueName: ""; ValueData: "OpenSloper.Pattern"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.sloper\OpenWithProgids"; ValueType: string; ValueName: "OpenSloper.Pattern"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\OpenSloper.Pattern"; ValueType: string; ValueName: ""; ValueData: "OpenSloper pattern"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\OpenSloper.Pattern\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\opensloper-design.exe,0"
Root: HKA; Subkey: "Software\Classes\OpenSloper.Pattern\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\opensloper-design.exe"" ""%1"""

Root: HKA; Subkey: "Software\Classes\.slm"; ValueType: string; ValueName: ""; ValueData: "OpenSloper.Measurements"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.slm\OpenWithProgids"; ValueType: string; ValueName: "OpenSloper.Measurements"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\OpenSloper.Measurements"; ValueType: string; ValueName: ""; ValueData: "OpenSloper measurements"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\OpenSloper.Measurements\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\opensloper-measurements.exe,0"
Root: HKA; Subkey: "Software\Classes\OpenSloper.Measurements\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\opensloper-measurements.exe"" ""%1"""

Root: HKA; Subkey: "Software\Classes\.slayout"; ValueType: string; ValueName: ""; ValueData: "OpenSloper.Layout"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.slayout\OpenWithProgids"; ValueType: string; ValueName: "OpenSloper.Layout"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\OpenSloper.Layout"; ValueType: string; ValueName: ""; ValueData: "OpenSloper layout"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\OpenSloper.Layout\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\opensloper-publish.exe,0"
Root: HKA; Subkey: "Software\Classes\OpenSloper.Layout\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\opensloper-publish.exe"" ""%1"""

[Run]
Filename: "{app}\opensloper-design.exe"; Description: "{cm:LaunchProgram,OpenSloper}"; Flags: nowait postinstall skipifsilent
