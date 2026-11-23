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

// The patterns a file reads, each with a measurement set and size: the
// sources of a layout (.slayout) and of a drape file. Each source has an ID
// from the file's own never-reused counter, and is evaluated from the saved
// files, which a checksum tells when they change. Paths are stored relative to
// the file that lists them. No LCL dependency.
unit Sloper.Core.PatternSources;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, fpjson, Sloper.Core.Pattern, Sloper.Core.Measurements;

type
  // A pattern file with its measurement set. The stored paths are as written
  // in the owning file; empty MeasurementFile means the one the pattern names.
  TPatternSource = class
  public
    Id: integer;
    PatternFile, MeasurementFile, Size: string;
    Pattern: TPattern;
    Measurements: TMeasurementSet;
    // Why the source could not be read; empty when it is ready
    LoadError: string;
    // The files read, and their stamps when they were
    PatternPath, MeasurementPath, LoadedStamp: string;
    // The files' stamps now; differs from LoadedStamp once either is saved
    function CurrentStamp: string;
    destructor Destroy; override;
    procedure Unload;
  end;

  TPatternSourceList = specialize TObjectList<TPatternSource>;

  TPatternSources = class
  private
    FItems: TPatternSourceList;
    FNextId: integer;
    // The lowest ID no source has, once the counter is past JSON_MAX_ID
    function LowestFreeId: integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Add(const APatternFile, AMeasurementFile, ASize: string): TPatternSource;
    // The owner takes away what refers to the source first
    procedure Remove(Source: TPatternSource);
    function FindById(Id: integer): TPatternSource;
    // Reads the source's files again; OwnerFile is the file listing it, which
    // relative paths start from
    procedure Load(Source: TPatternSource; const OwnerFile: string);
    procedure LoadAll(const OwnerFile: string);
    // Reads the source from the files' contents, as the web editor holds
    // them, rather than from disk; an empty MeasurementText is no set
    procedure LoadText(Source: TPatternSource; const PatternText, MeasurementText: string);
    // Adds "nextId" and "sources" to a file's root
    procedure SaveTo(Root: TJSONObject);
    // Reads "sources" and "nextId"; on failure the sources are cleared
    function LoadFrom(Root: TJSONObject; out ErrorMessage: string): boolean;
    property Items: TPatternSourceList read FItems;
  end;

// A path as stored in OwnerFile: relative to its folder once it has one
function StoredSourcePath(const OwnerFile, Path: string): string;
function ResolveSourcePath(const OwnerFile, Stored: string): string;
// A checksum of the contents: file times only go to the second, and these
// files are small enough to read each time. '-' when the file cannot be read.
function FileStamp(const Path: string): string;

resourcestring
  rsPatternSourcesList = 'The file has no valid "sources" list';
  rsPatternSourcesBad = 'Source %d has a missing, invalid or repeated ID, or no pattern';
  rsPatternSourcesNextId = '"nextId" must be a whole number above every source ID';
  rsPatternSourcesNoFile = 'File not found: %s';

implementation

uses
  Math, crc, Sloper.Core.JSON, Sloper.Core.PatternFile;

function FileStamp(const Path: string): string;
var
  Text, Reason: string;
begin
  Result := '-';
  if (Path <> '') and FileExists(Path) and ReadTextFile(Path, Text, Reason) then
    Result := IntToStr(crc32(crc32(0, nil, 0), pbyte(PChar(Text)), Length(Text)));
end;

function StoredSourcePath(const OwnerFile, Path: string): string;
begin
  if OwnerFile = '' then
    Result := Path
  else
    Result := ExtractRelativePath(ExtractFilePath(ExpandFileName(OwnerFile)), ExpandFileName(Path));
end;

function ResolveSourcePath(const OwnerFile, Stored: string): string;
var
  Folder: string;
begin
  Result := SetDirSeparators(Stored);
  Folder := ExtractFileDir(OwnerFile);
  if (Result <> '') and (Result[1] <> PathDelim) and (ExtractFileDrive(Result) = '') and (Folder <> '') then
    Result := ConcatPaths([Folder, Result]);
end;

{ TPatternSource }

function TPatternSource.CurrentStamp: string;
begin
  Result := FileStamp(PatternPath) + ' ' + FileStamp(MeasurementPath);
end;

destructor TPatternSource.Destroy;
begin
  Unload;
  inherited Destroy;
end;

// The pattern reads the measurement set, so it goes first
procedure TPatternSource.Unload;
begin
  FreeAndNil(Pattern);
  FreeAndNil(Measurements);
end;

{ TPatternSources }

constructor TPatternSources.Create;
begin
  FItems := TPatternSourceList.Create;
  FNextId := 1;
end;

destructor TPatternSources.Destroy;
begin
  FreeAndNil(FItems);
  inherited Destroy;
end;

procedure TPatternSources.Clear;
begin
  FItems.Clear;
  FNextId := 1;
end;

function TPatternSources.LowestFreeId: integer;
begin
  Result := 1;
  while Assigned(FindById(Result)) do
    Inc(Result);
end;

function TPatternSources.Add(const APatternFile, AMeasurementFile, ASize: string): TPatternSource;
begin
  Result := TPatternSource.Create;
  FItems.Add(Result);
  // Past the highest ID a file may hold, as for pattern IDs: the lowest free
  if FNextId > JSON_MAX_ID then
    Result.Id := LowestFreeId
  else
  begin
    Result.Id := FNextId;
    Inc(FNextId);
  end;
  Result.PatternFile := APatternFile;
  Result.MeasurementFile := AMeasurementFile;
  Result.Size := ASize;
end;

procedure TPatternSources.Remove(Source: TPatternSource);
begin
  FItems.Remove(Source);
end;

function TPatternSources.FindById(Id: integer): TPatternSource;
var
  Source: TPatternSource;
begin
  for Source in FItems do
    if Source.Id = Id then
      Exit(Source);
  Result := nil;
end;

procedure TPatternSources.Load(Source: TPatternSource; const OwnerFile: string);
var
  Err: string;
begin
  Source.Unload;
  Source.LoadError := '';
  Source.PatternPath := ResolveSourcePath(OwnerFile, Source.PatternFile);
  Source.MeasurementPath := '';
  // Taken before reading, so a save during the read is not missed
  Source.LoadedStamp := Source.CurrentStamp;
  if not FileExists(Source.PatternPath) then
  begin
    Source.LoadError := Format(rsPatternSourcesNoFile, [Source.PatternPath]);
    Exit;
  end;
  Source.Pattern := TPattern.Create;
  Source.Measurements := TMeasurementSet.Create;
  if not LoadPatternFromFile(Source.Pattern, Source.PatternPath, Err) then
  begin
    Source.LoadError := Err;
    Exit;
  end;
  Source.MeasurementPath := ResolveSourcePath(OwnerFile, Source.MeasurementFile);
  if Source.MeasurementPath = '' then
    Source.MeasurementPath := MeasurementFilePath(Source.Pattern, Source.PatternPath);
  Source.LoadedStamp := Source.CurrentStamp;
  if Source.MeasurementPath <> '' then
  begin
    if not FileExists(Source.MeasurementPath) then
    begin
      Source.LoadError := Format(rsPatternSourcesNoFile, [Source.MeasurementPath]);
      Exit;
    end;
    if not Source.Measurements.LoadFromFile(Source.MeasurementPath, Err) then
    begin
      Source.LoadError := Err;
      Exit;
    end;
    Source.Pattern.Measurements := Source.Measurements;
  end;
  if (Source.Size <> '') and not Source.Measurements.SelectSize(Source.Size) then
  begin
    Source.LoadError := Format(rsMeasurementUnknownSize, [Source.Size]);
    Exit;
  end;
  Source.Pattern.Evaluate;
end;

procedure TPatternSources.LoadText(Source: TPatternSource; const PatternText, MeasurementText: string);
var
  Err: string;
begin
  Source.Unload;
  Source.LoadError := '';
  Source.PatternPath := '';
  Source.MeasurementPath := '';
  Source.LoadedStamp := '';
  Source.Pattern := TPattern.Create;
  Source.Measurements := TMeasurementSet.Create;
  if not LoadPatternFromText(Source.Pattern, PatternText, Err) then
  begin
    Source.LoadError := Err;
    Exit;
  end;
  if MeasurementText <> '' then
  begin
    if not Source.Measurements.LoadFromText(MeasurementText, Err) then
    begin
      Source.LoadError := Err;
      Exit;
    end;
    Source.Pattern.Measurements := Source.Measurements;
  end;
  if (Source.Size <> '') and not Source.Measurements.SelectSize(Source.Size) then
  begin
    Source.LoadError := Format(rsMeasurementUnknownSize, [Source.Size]);
    Exit;
  end;
  Source.Pattern.Evaluate;
end;

procedure TPatternSources.LoadAll(const OwnerFile: string);
var
  Source: TPatternSource;
begin
  for Source in FItems do
    Load(Source, OwnerFile);
end;

procedure TPatternSources.SaveTo(Root: TJSONObject);
var
  List: TJSONArray;
  Item: TJSONObject;
  Source: TPatternSource;
begin
  Root.Add('nextId', FNextId);
  List := TJSONArray.Create;
  Root.Add('sources', List);
  for Source in FItems do
  begin
    Item := TJSONObject.Create;
    List.Add(Item);
    Item.Add('id', Source.Id);
    Item.Add('pattern', Source.PatternFile);
    if Source.MeasurementFile <> '' then
      Item.Add('measurementFile', Source.MeasurementFile);
    if Source.Size <> '' then
      Item.Add('size', Source.Size);
  end;
end;

function TPatternSources.LoadFrom(Root: TJSONObject; out ErrorMessage: string): boolean;
var
  Data: TJSONData;
  Item: TJSONObject;
  Source: TPatternSource;
  Index, Id, Top, Saved: integer;
  PatternText: string;

  function Fail(const Msg: string): boolean;
  begin
    ErrorMessage := Msg;
    Clear;
    Result := False;
  end;

begin
  Clear;
  ErrorMessage := '';
  Data := Root.Find('sources');
  if not Assigned(Data) or (Data.JSONType <> jtArray) then
    Exit(Fail(rsPatternSourcesList));
  Top := 0;
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      Exit(Fail(rsPatternSourcesList));
    Item := TJSONObject(Data.Items[Index]);
    if not GetJSONId(Item, 'id', Id) or Assigned(FindById(Id)) or not GetJSONString(Item, 'pattern', PatternText) then
      Exit(Fail(Format(rsPatternSourcesBad, [Index + 1])));
    Source := TPatternSource.Create;
    FItems.Add(Source);
    Source.Id := Id;
    Source.PatternFile := PatternText;
    GetJSONString(Item, 'measurementFile', Source.MeasurementFile);
    GetJSONString(Item, 'size', Source.Size);
    Top := Max(Top, Id);
  end;
  FNextId := Top + 1;
  if Assigned(Root.Find('nextId')) then
  begin
    if not GetJSONInteger(Root, 'nextId', Saved) or (Saved < FNextId) then
      Exit(Fail(rsPatternSourcesNextId));
    FNextId := Saved;
  end;
  Result := True;
end;

end.
