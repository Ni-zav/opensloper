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

// The files each app opened or saved last, for File → Open Recent. They are
// kept in recent-files.json in the state folder, one list per app. The apps
// run at the same time, so every change reads the file afresh and writes it
// straight back, rather than keeping a copy that would overwrite the others'.
// A portable install keeps the files inside its own folder relative to it, so
// the list still works when the drive it is on gets another letter or mount
// point. No LCL dependency.
unit Sloper.Core.RecentFiles;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

type
  TRecentList = (rlPatterns, rlMeasurements, rlLayouts);

const
  MAX_RECENT_FILES = 10;

type
  TRecentFiles = class
  private
    FLists: array[TRecentList] of TStringArray;
    FNewerVersion: boolean;
    FBase: string;
    function GetFiles(List: TRecentList): TStringArray;
  public
    procedure Clear;
    // Puts FileName first, as a full path, moving it up if it is already listed
    procedure Add(List: TRecentList; const FileName: string);
    procedure Remove(List: TRecentList; const FileName: string);
    procedure ClearList(List: TRecentList);
    function SaveToText: string;
    // On failure the lists are empty and ErrorMessage says why
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    // A missing file is empty lists, not an error
    function LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
    function SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
    property Files[List: TRecentList]: TStringArray read GetFiles;
    // The last load found a file from a newer version, which is not overwritten
    property NewerVersion: boolean read FNewerVersion;
    // Files inside this folder are saved relative to it, and read back
    // against it; '' saves full paths
    property Base: string read FBase write FBase;
  end;

// Read and change the list in StoreFile (TAppPaths.RecentFilesFile in the
// apps), with files inside Base kept relative to it (TAppPaths.PortableRoot).
// Recent files are a convenience, so a problem is never reported: a file that
// cannot be read is replaced, except one from a newer version.
function ReadRecentFiles(const StoreFile: string; List: TRecentList; const Base: string = ''): TStringArray;
procedure RememberRecentFile(const StoreFile: string; List: TRecentList; const FileName: string; const Base: string = '');
procedure ForgetRecentFile(const StoreFile: string; List: TRecentList; const FileName: string; const Base: string = '');
procedure ClearRecentFiles(const StoreFile: string; List: TRecentList; const Base: string = '');

resourcestring
  rsRecentWrongFormat = 'This is not an OpenSloper recent files list';
  rsRecentNewerVersion = 'This file was made by a newer version of OpenSloper (file version %d)';

implementation

uses
  fpjson, Sloper.Core.JSON;

const
  RECENT_FORMAT = 'opensloper-recent-files';
  RECENT_VERSION = 1;
  LIST_NAMES: array[TRecentList] of string = ('design', 'measurements', 'publish');
  // Between the folders of a relative path in the file, on every platform
  SAVED_DELIM = '/';
  PARENT_FOLDER = '..';

// FileName relative to Base when it is inside it, else as it is
function SavedName(const Base, FileName: string): string;
var
  Relative: string;
begin
  if Base = '' then
    Exit(FileName);
  Relative := ExtractRelativePath(IncludeTrailingPathDelimiter(ExpandFileName(Base)), FileName);
  // Elsewhere: above Base, or on another drive
  if (Relative = '') or (Copy(Relative, 1, Length(PARENT_FOLDER)) = PARENT_FOLDER) or (ExtractFileDrive(Relative) <> '') or
    (Relative[1] = PathDelim) then
    Exit(FileName);
  Result := StringReplace(Relative, PathDelim, SAVED_DELIM, [rfReplaceAll]);
end;

// A name as saved, as a full path
function LoadedName(const Base, Saved: string): string;
var
  Name: string;
begin
  Name := Saved;
  DoDirSeparators(Name);
  if (Base <> '') and (ExtractFileDrive(Name) = '') and ((Name = '') or (Name[1] <> PathDelim)) then
    Result := ExpandFileName(ConcatPaths([Base, Name]))
  else
    Result := Name;
end;

function TRecentFiles.GetFiles(List: TRecentList): TStringArray;
begin
  Result := Copy(FLists[List]);
end;

procedure TRecentFiles.Clear;
var
  List: TRecentList;
begin
  for List := Low(TRecentList) to High(TRecentList) do
    FLists[List] := nil;
  FNewerVersion := False;
end;

procedure TRecentFiles.Add(List: TRecentList; const FileName: string);
var
  FullName: string;
begin
  if FileName = '' then
    Exit;
  FullName := ExpandFileName(FileName);
  Remove(List, FullName);
  Insert(FullName, FLists[List], 0);
  if Length(FLists[List]) > MAX_RECENT_FILES then
    SetLength(FLists[List], MAX_RECENT_FILES);
end;

procedure TRecentFiles.Remove(List: TRecentList; const FileName: string);
var
  Index: integer;
  FullName: string;
begin
  FullName := ExpandFileName(FileName);
  for Index := High(FLists[List]) downto 0 do
    if SameFileName(FLists[List][Index], FullName) then
      Delete(FLists[List], Index, 1);
end;

procedure TRecentFiles.ClearList(List: TRecentList);
begin
  FLists[List] := nil;
end;

function TRecentFiles.SaveToText: string;
var
  Obj: TJSONObject;
  Names: TJSONArray;
  List: TRecentList;
  FileName: string;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('format', RECENT_FORMAT);
    Obj.Add('version', RECENT_VERSION);
    for List := Low(TRecentList) to High(TRecentList) do
    begin
      Names := TJSONArray.Create;
      Obj.Add(LIST_NAMES[List], Names);
      for FileName in FLists[List] do
        Names.Add(SavedName(FBase, FileName));
    end;
    Result := JSONToText(Obj);
  finally
    FreeAndNil(Obj);
  end;
end;

function TRecentFiles.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Obj: TJSONObject;
  Names: TJSONData;
  TextValue: string;
  Version, Index: integer;
  List: TRecentList;
begin
  Clear;
  if not ParseJSONObject(Text, Obj, ErrorMessage) then
    Exit(False);
  try
    if not GetJSONString(Obj, 'format', TextValue) or (TextValue <> RECENT_FORMAT) or not GetJSONInteger(Obj, 'version', Version) then
    begin
      ErrorMessage := rsRecentWrongFormat;
      Exit(False);
    end;
    if Version > RECENT_VERSION then
    begin
      FNewerVersion := True;
      ErrorMessage := Format(rsRecentNewerVersion, [Version]);
      Exit(False);
    end;
    // Read oldest first, so Add keeps the order and drops repeats and blanks
    for List := Low(TRecentList) to High(TRecentList) do
    begin
      Names := Obj.Find(LIST_NAMES[List]);
      if Names is TJSONArray then
        for Index := TJSONArray(Names).Count - 1 downto 0 do
          if (TJSONArray(Names)[Index].JSONType = jtString) and (TJSONArray(Names)[Index].AsString <> '') then
            Add(List, LoadedName(FBase, TJSONArray(Names)[Index].AsString));
    end;
    Result := True;
  finally
    FreeAndNil(Obj);
  end;
end;

function TRecentFiles.LoadFromFile(const FileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Clear;
  ErrorMessage := '';
  if not FileExists(FileName) then
    Exit(True);
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
end;

function TRecentFiles.SaveToFile(const FileName: string; out ErrorMessage: string): boolean;
var
  Folder: string;
begin
  Folder := ExtractFileDir(FileName);
  if (Folder <> '') and not ForceDirectories(Folder) then
  begin
    ErrorMessage := Format('%s: %s', [Folder, SysErrorMessage(GetLastOSError)]);
    Exit(False);
  end;
  Result := WriteTextFileAtomic(FileName, SaveToText, ErrorMessage);
end;

function ReadRecentFiles(const StoreFile: string; List: TRecentList; const Base: string): TStringArray;
var
  Recent: TRecentFiles;
  Reason: string;
begin
  Recent := TRecentFiles.Create;
  try
    Recent.Base := Base;
    Recent.LoadFromFile(StoreFile, Reason);
    Result := Recent.Files[List];
  finally
    FreeAndNil(Recent);
  end;
end;

type
  TRecentChange = (rcRemember, rcForget, rcClear);

procedure ChangeRecentFiles(const StoreFile: string; List: TRecentList; Change: TRecentChange; const FileName, Base: string);
var
  Recent: TRecentFiles;
  Reason: string;
begin
  Recent := TRecentFiles.Create;
  try
    Recent.Base := Base;
    // Unreadable lists start again, which loses nothing that matters
    Recent.LoadFromFile(StoreFile, Reason);
    if Recent.NewerVersion then
      Exit;
    case Change of
      rcRemember: Recent.Add(List, FileName);
      rcForget: Recent.Remove(List, FileName);
      rcClear: Recent.ClearList(List);
    end;
    Recent.SaveToFile(StoreFile, Reason);
  finally
    FreeAndNil(Recent);
  end;
end;

procedure RememberRecentFile(const StoreFile: string; List: TRecentList; const FileName, Base: string);
begin
  ChangeRecentFiles(StoreFile, List, rcRemember, FileName, Base);
end;

procedure ForgetRecentFile(const StoreFile: string; List: TRecentList; const FileName, Base: string);
begin
  ChangeRecentFiles(StoreFile, List, rcForget, FileName, Base);
end;

procedure ClearRecentFiles(const StoreFile: string; List: TRecentList; const Base: string);
begin
  ChangeRecentFiles(StoreFile, List, rcClear, '', Base);
end;

end.
