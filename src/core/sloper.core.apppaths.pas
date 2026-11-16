{
  OpenSloper - parametric sewing pattern drafting
  Copyright (C) 2026 The OpenSloper authors

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
}

// Platform folders for config, data, state, cache and user documents.
// All other code gets its folders from TAppPaths. A portable install, with
// portable.ini beside the programs (or beside the macOS app bundle), keeps
// them all beside it instead: config, data, state and cache in user/, apart
// from the data/ the programs ship with, and documents in documents/.
// No LCL dependency.
unit Sloper.Core.AppPaths;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

type
  TAppPaths = class
  public
    class function ConfigDir: string;
    class function DataDir: string;
    class function StateDir: string;
    class function CacheDir: string;
    // Files that last only while an app runs, such as the automation socket:
    // $XDG_RUNTIME_DIR on Linux, the user's own temporary folder on macOS,
    // Local AppData on Windows. Never the portable folder, which may be on a
    // drive that cannot hold a socket. Not made private here.
    class function RuntimeDir: string;
    class function DefaultDocumentsDir: string;
    class function SettingsFile: string;
    // File → Open Recent's lists, which are state rather than settings
    class function RecentFilesFile: string;
    // True when portable.ini sits beside the executable, or beside the macOS
    // app bundle it is in
    class function IsPortable: boolean;
    // The folder a portable install keeps its files in: the one holding
    // portable.ini. '' when the install is not portable.
    class function PortableRoot: string;
    // The same for programs in ProgramFolder
    class function PortableRootIn(const ProgramFolder: string): string;
    // Where a portable install in Root keeps Kind (config, data, state, cache)
    class function PortableDirIn(const Root, Kind: string): string;
    // The publish app beside this program, or in the source tree in publish/
    // below it or beside its folder. Empty when it is in none of these.
    class function PublishProgram: string;
    class function PublishProgramIn(const Folder: string): string;
    // opensloper-measurements, found the same way; '' when it is not there
    class function MeasurementsProgram: string;
    class function MeasurementsProgramIn(const Folder: string): string;
    // The measurement catalogue, in data beside this program when installed
    // or one or two folders up in the source tree; '' when it is not there
    class function CatalogueFile: string;
    class function CatalogueFileIn(const Folder: string): string;
    // The toolbar and menu icons, found the same way; '' when they are not there
    class function IconDir: string;
    class function IconDirIn(const Folder: string): string;
    // The fonts bundled for drawing text into images, data/fonts
    class function FontDir: string;
    class function FontDirIn(const Folder: string): string;
    // The user guide's front page in the offline copy of the site that the
    // downloads ship in data/help; '' when there is none, as in the source tree
    class function UserGuideFile: string;
    class function UserGuideFileIn(const Folder: string): string;
    // Libraries a download ships for its programs: the programs' own folder
    // on Windows, Contents/Frameworks of a macOS app bundle, lib beside the
    // programs elsewhere. The folder may not exist.
    class function LibraryDir: string;
    class function LibraryDirIn(const Folder: string): string;
    // The certificates the assistant trusts where OpenSSL cannot read the
    // system's, data/cacert.pem in the Windows and macOS downloads; '' when
    // there is none, as on Linux, where the system's are used
    class function TrustedCertificatesFile: string;
    class function TrustedCertificatesFileIn(const Folder: string): string;
    // The folders the system and the user install fonts in, which may not
    // exist; PDF export looks there for a note's font
    class function SystemFontDirs: TStringArray;
    // Creates Dir if missing and returns it; folders are made on first use
    class function ForceDir(const Dir: string): string;
    // XDG rule: EnvValue when it is an absolute path, else Home + Fallback
    class function ResolveXdgDir(const EnvValue, Home, Fallback: string): string;
  end;

implementation

uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  Sloper.Core.Version;

const
  PORTABLE_FILE_NAME = 'portable.ini';
  // A portable install's own files, kept apart from the data it ships with
  PORTABLE_USER_FOLDER = 'user';
  PORTABLE_DOCUMENTS_FOLDER = 'documents';
  // A macOS app bundle's programs, three folders below where it lies
  BUNDLE_SUFFIX = '.app';
  BUNDLE_PROGRAM_FOLDERS: array[0..1] of string = ('Contents', 'MacOS');
  SETTINGS_FILE_NAME = 'settings.json';
  RECENT_FILES_FILE_NAME = 'recent-files.json';
  PUBLISH_FOLDER = 'publish';
  MEASUREMENTS_FOLDER = 'measurements';
  DATA_FOLDER = 'data';
  CATALOGUE_FILE_NAME = 'measurement-catalogue.json';
  ICON_FOLDER = 'icons';
  FONT_FOLDER = 'fonts';
  USER_GUIDE_FOLDER = 'help';
  USER_GUIDE_PAGE = 'index.html';
  TRUSTED_CERTIFICATES_FILE_NAME = 'cacert.pem';
  LIBRARY_FOLDER = 'lib';
  BUNDLE_LIBRARY_FOLDER = 'Frameworks';
  {$IFDEF WINDOWS}
  PUBLISH_FILE_NAME = 'opensloper-publish.exe';
  MEASUREMENTS_FILE_NAME = 'opensloper-measurements.exe';
  {$ELSE}
  PUBLISH_FILE_NAME = 'opensloper-publish';
  MEASUREMENTS_FILE_NAME = 'opensloper-measurements';
  {$ENDIF}
  // Beside the program, one or two folders up (the source tree), and in
  // Contents/Resources of a macOS app bundle, whose programs are in Contents/MacOS
  DATA_UP_LEVELS: array[0..3] of string = ('', '..', '..' + PathDelim + '..', '..' + PathDelim + 'Resources');

function HomeDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(GetUserDir);
end;

function ExeDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
end;

function PortableDir(const Kind: string): string;
begin
  Result := TAppPaths.PortableDirIn(TAppPaths.PortableRoot, Kind);
end;

{$IFDEF WINDOWS}
function WinDir(const EnvName: string; const Extra: array of string): string;
begin
  Result := ConcatPaths([GetEnvironmentVariable(EnvName), APP_NAME]);
  if Length(Extra) > 0 then
    Result := ConcatPaths([Result, ConcatPaths(Extra)]);
end;
{$ENDIF}

{$IFDEF DARWIN}
function MacDir(const Sub: string): string;
begin
  Result := ConcatPaths([HomeDir, 'Library', Sub, APP_NAME]);
end;
{$ENDIF}

{$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}
function XdgDir(const EnvName, Fallback: string): string;
begin
  Result := ConcatPaths([TAppPaths.ResolveXdgDir(GetEnvironmentVariable(EnvName),
    HomeDir, Fallback), APP_NAME_LOWER]);
end;
{$ENDIF}

class function TAppPaths.ConfigDir: string;
begin
  if IsPortable then
    Exit(PortableDir('config'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('APPDATA', []);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Application Support');
  {$ELSE}
  Result := XdgDir('XDG_CONFIG_HOME', '.config');
  {$ENDIF}
end;

class function TAppPaths.DataDir: string;
begin
  if IsPortable then
    Exit(PortableDir('data'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('APPDATA', []);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Application Support');
  {$ELSE}
  Result := XdgDir('XDG_DATA_HOME', ConcatPaths(['.local', 'share']));
  {$ENDIF}
end;

class function TAppPaths.StateDir: string;
begin
  if IsPortable then
    Exit(PortableDir('state'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('LOCALAPPDATA', []);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Application Support');
  {$ELSE}
  Result := XdgDir('XDG_STATE_HOME', ConcatPaths(['.local', 'state']));
  {$ENDIF}
end;

class function TAppPaths.RuntimeDir: string;
begin
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('LOCALAPPDATA', ['run']);
  {$ELSEIF DEFINED(DARWIN)}
  // TMPDIR is already the user's own
  Result := ConcatPaths([ExcludeTrailingPathDelimiter(GetTempDir), APP_NAME_LOWER]);
  {$ELSE}
  if (GetEnvironmentVariable('XDG_RUNTIME_DIR') <> '') and (GetEnvironmentVariable('XDG_RUNTIME_DIR')[1] = PathDelim) then
    Result := ConcatPaths([GetEnvironmentVariable('XDG_RUNTIME_DIR'), APP_NAME_LOWER])
  else
    Result := ConcatPaths([ExcludeTrailingPathDelimiter(GetTempDir), APP_NAME_LOWER + '-' + IntToStr(fpGetUid)]);
  {$ENDIF}
end;

class function TAppPaths.CacheDir: string;
begin
  if IsPortable then
    Exit(PortableDir('cache'));
  {$IF DEFINED(WINDOWS)}
  Result := WinDir('LOCALAPPDATA', ['Cache']);
  {$ELSEIF DEFINED(DARWIN)}
  Result := MacDir('Caches');
  {$ELSE}
  Result := XdgDir('XDG_CACHE_HOME', '.cache');
  {$ENDIF}
end;

class function TAppPaths.DefaultDocumentsDir: string;
begin
  if IsPortable then
    Exit(ConcatPaths([PortableRoot, PORTABLE_DOCUMENTS_FOLDER]));
  Result := ConcatPaths([HomeDir, 'Documents', APP_NAME]);
end;

class function TAppPaths.SettingsFile: string;
begin
  Result := ConcatPaths([ConfigDir, SETTINGS_FILE_NAME]);
end;

class function TAppPaths.RecentFilesFile: string;
begin
  Result := ConcatPaths([StateDir, RECENT_FILES_FILE_NAME]);
end;

// Beside this program when installed; in the source tree in its own folder,
// below this program or beside its folder (src/design and src/publish)
function CompanionIn(const Folder, SubFolder, FileName: string): string;
begin
  Result := ConcatPaths([Folder, FileName]);
  if FileExists(Result) then
    Exit;
  Result := ConcatPaths([Folder, SubFolder, FileName]);
  if FileExists(Result) then
    Exit;
  Result := ExpandFileName(ConcatPaths([Folder, '..', SubFolder, FileName]));
  if not FileExists(Result) then
    Result := '';
end;

// Path in data beside Folder when installed (in Resources in a macOS app
// bundle), or in the data folder of the source tree: one folder up from tests
// and cli, two up from src/<app>
function DataPathIn(const Folder, Path: string; WantDir: boolean): string;
var
  Up: string;
begin
  for Up in DATA_UP_LEVELS do
  begin
    Result := ExpandFileName(ConcatPaths([Folder, Up, DATA_FOLDER, Path]));
    if (WantDir and DirectoryExists(Result)) or (not WantDir and FileExists(Result)) then
      Exit;
  end;
  Result := '';
end;

class function TAppPaths.PublishProgram: string;
begin
  Result := PublishProgramIn(ExeDir);
end;

class function TAppPaths.PublishProgramIn(const Folder: string): string;
begin
  Result := CompanionIn(Folder, PUBLISH_FOLDER, PUBLISH_FILE_NAME);
end;

class function TAppPaths.CatalogueFile: string;
begin
  Result := CatalogueFileIn(ExeDir);
end;

class function TAppPaths.CatalogueFileIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, CATALOGUE_FILE_NAME, False);
end;

class function TAppPaths.IconDir: string;
begin
  Result := IconDirIn(ExeDir);
end;

class function TAppPaths.IconDirIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, ICON_FOLDER, True);
end;

class function TAppPaths.FontDir: string;
begin
  Result := FontDirIn(ExeDir);
end;

class function TAppPaths.FontDirIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, FONT_FOLDER, True);
end;

class function TAppPaths.UserGuideFile: string;
begin
  Result := UserGuideFileIn(ExeDir);
end;

class function TAppPaths.UserGuideFileIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, ConcatPaths([USER_GUIDE_FOLDER, USER_GUIDE_PAGE]), False);
end;

class function TAppPaths.LibraryDir: string;
begin
  Result := LibraryDirIn(ExeDir);
end;

class function TAppPaths.LibraryDirIn(const Folder: string): string;
begin
  {$IF DEFINED(WINDOWS)}
  Result := ExcludeTrailingPathDelimiter(Folder);
  {$ELSEIF DEFINED(DARWIN)}
  Result := ExpandFileName(ConcatPaths([Folder, '..', BUNDLE_LIBRARY_FOLDER]));
  {$ELSE}
  Result := ConcatPaths([Folder, LIBRARY_FOLDER]);
  {$ENDIF}
end;

class function TAppPaths.TrustedCertificatesFile: string;
begin
  Result := TrustedCertificatesFileIn(ExeDir);
end;

class function TAppPaths.TrustedCertificatesFileIn(const Folder: string): string;
begin
  Result := DataPathIn(Folder, TRUSTED_CERTIFICATES_FILE_NAME, False);
end;

class function TAppPaths.SystemFontDirs: TStringArray;
begin
  {$IF DEFINED(WINDOWS)}
  Result := [ConcatPaths([GetEnvironmentVariable('WINDIR'), 'Fonts']),
    ConcatPaths([GetEnvironmentVariable('LOCALAPPDATA'), 'Microsoft', 'Windows', 'Fonts'])];
  {$ELSEIF DEFINED(DARWIN)}
  Result := [ConcatPaths([PathDelim + 'System', 'Library', 'Fonts']), ConcatPaths([PathDelim + 'Library', 'Fonts']),
    ConcatPaths([HomeDir, 'Library', 'Fonts'])];
  {$ELSE}
  Result := [ConcatPaths([PathDelim + 'usr', 'share', 'fonts']), ConcatPaths([PathDelim + 'usr', 'local', 'share', 'fonts']),
    ConcatPaths([ResolveXdgDir(GetEnvironmentVariable('XDG_DATA_HOME'), HomeDir, ConcatPaths(['.local', 'share'])), 'fonts']),
    ConcatPaths([HomeDir, '.fonts'])];
  {$ENDIF}
end;

class function TAppPaths.MeasurementsProgram: string;
begin
  Result := MeasurementsProgramIn(ExeDir);
end;

class function TAppPaths.MeasurementsProgramIn(const Folder: string): string;
begin
  Result := CompanionIn(Folder, MEASUREMENTS_FOLDER, MEASUREMENTS_FILE_NAME);
end;

class function TAppPaths.IsPortable: boolean;
begin
  Result := PortableRoot <> '';
end;

class function TAppPaths.PortableRoot: string;
begin
  Result := PortableRootIn(ExeDir);
end;

// Code signing takes nothing new inside a bundle, so its portable.ini lies
// beside it. Looked for on every platform, so tests can check it.
class function TAppPaths.PortableRootIn(const ProgramFolder: string): string;
var
  Folder, Bundle: string;
begin
  Folder := ExcludeTrailingPathDelimiter(ProgramFolder);
  if FileExists(ConcatPaths([Folder, PORTABLE_FILE_NAME])) then
    Exit(Folder);
  Result := '';
  if not SameText(ExtractFileName(Folder), BUNDLE_PROGRAM_FOLDERS[1]) or not SameText(ExtractFileName(ExtractFileDir(Folder)), BUNDLE_PROGRAM_FOLDERS[0]) then
    Exit;
  Bundle := ExtractFileDir(ExtractFileDir(Folder));
  if not SameText(ExtractFileExt(Bundle), BUNDLE_SUFFIX) then
    Exit;
  if FileExists(ConcatPaths([ExtractFileDir(Bundle), PORTABLE_FILE_NAME])) then
    Result := ExtractFileDir(Bundle);
end;

class function TAppPaths.PortableDirIn(const Root, Kind: string): string;
begin
  Result := ConcatPaths([Root, PORTABLE_USER_FOLDER, Kind]);
end;

class function TAppPaths.ForceDir(const Dir: string): string;
begin
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);
  Result := Dir;
end;

class function TAppPaths.ResolveXdgDir(const EnvValue, Home, Fallback: string): string;
begin
  // The XDG spec says relative values are invalid and must be ignored
  if (EnvValue <> '') and (EnvValue[1] = PathDelim) then
    Result := ExcludeTrailingPathDelimiter(EnvValue)
  else
    Result := ConcatPaths([Home, Fallback]);
end;

end.
