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

// Drape files (.sdrape): the patterns the drape app places on a body, the body,
// and where each copy of each piece is placed in 3D. Information flows one
// way, measurements to patterns to this file; nothing is written back to a
// pattern. A placement names its piece by source and piece ID, so it survives
// edits. Described in the design document under "Drape app and Blender
// export". No LCL dependency.
unit Sloper.Core.DrapeFile;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.PatternSources,
  Sloper.Core.DrapePlacement, Sloper.Core.FileVersions, Sloper.Core.Measurements, Sloper.Core.BodyForm;

const
  DRAPE_FORMAT = 'drape';
  DRAPE_VERSION = 1;
  DRAPE_EXTENSION = '.sdrape';
  // How far (mm) pieces are placed off the body and apart across a seam
  DEFAULT_DRAPE_GAP = 20;

type
  // bkMeasurements builds a generic body from a measurement set; bkNone has no
  // body, for accessories
  TDrapeBodyKind = (bkMeasurements, bkNone);

  // The body's measurement set and size; an empty MeasurementFile is the first
  // source's, with its size unless Size is given
  TDrapeBody = record
    Kind: TDrapeBodyKind;
    MeasurementFile, Size: string;
  end;

  TDrapePieceCopy = record
    SourceId, Copy: integer;
    PieceKey: string;
  end;

  TDrapePieceCopyArray = array of TDrapePieceCopy;

  TDrapeItem = record
    Piece: TDrapePieceCopy;
    Placement: TDrapePlacement;
  end;

  TDrapeItemArray = array of TDrapeItem;

  // A line between the two sides of a seam, at its start, middle or end, as
  // the view draws them so a piece far from its partner stands out
  TDrapeSeamLink = record
    Seam: TSeamObject;
    // The item on side A
    Item: integer;
    From, Onto: TVec3;
  end;

  TDrapeSeamLinkArray = array of TDrapeSeamLink;
  TSeamObjectArray = array of TSeamObject;

  // A problem with the file, and the index of the item it is about or -1
  TDrapeProblem = record
    Text: string;
    Item: integer;
  end;

  TDrapeProblemArray = array of TDrapeProblem;

  TDrape = class
  private
    FSources: TPatternSources;
    // The body's own measurement set, when it names one, and why it could not
    // be read
    FBodySet: TMeasurementSet;
    FBodyError: string;
    function GetSources: TPatternSourceList;
    // Where guesses go: the height of the first piece's middle, and how far in
    // front of the centre line the body reaches
    procedure GuessFrame(out Height, Depth: double);
    function GuessFirstPieces: integer;
    function GuessAlongSeams: integer;
    function GuessMirroredCopies: integer;
    function GuessRest: integer;
    // A placed copy of the other side of Seam from Copy, preferring one on the
    // same side of the body (left with left), as a seam joins them
    function FindPartner(const Copy: TDrapePieceCopy; Seam: TSeamObject; out OnSideB: boolean; out PartnerIndex: integer): boolean;
    // The longest seam joining Copy to a placed copy that it can be aligned to
    function LongestPlacedSeam(const Copy: TDrapePieceCopy; out Seam: TSeamObject; out Length: double): boolean;
  public
    Name: string;
    // Where the file is saved; relative paths start from its folder
    FileName: string;
    Body: TDrapeBody;
    Gap: double;
    Items: TDrapeItemArray;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddSource(const APatternFile, AMeasurementFile, ASize: string): TPatternSource;
    // Takes away the source and its placements
    procedure RemoveSource(Source: TPatternSource);
    function FindSource(Id: integer): TPatternSource;
    function StoredPath(const Path: string): string;
    // Reads the sources' files again, and the body's measurement set
    procedure LoadSources;
    // Reads the body's measurement set again, as after the body changes
    procedure LoadBody;
    // The body's measurements: its own set, else the first source's, at the
    // body's size, else the source's. False when there is no body; the default
    // form when no set can be read.
    function BodyMeasures(out Measures: TBodyMeasures): boolean;
    function SaveToText: string;
    function LoadFromText(const Text: string; out ErrorMessage: string): boolean;
    function SaveToFile(const AFileName: string; out ErrorMessage: string): boolean;
    function LoadFromFile(const AFileName: string; out ErrorMessage: string): boolean;
    // The piece of a copy, when its source is loaded and has it
    function FindPiece(const Copy: TDrapePieceCopy; out Piece: TPieceObject): boolean;
    // The index of the copy's item, or -1 when it is unplaced
    function IndexOf(const Copy: TDrapePieceCopy): integer;
    // Places the copy, or moves it when it is placed
    procedure Place(const Copy: TDrapePieceCopy; const Placement: TDrapePlacement);
    procedure Unplace(const Copy: TDrapePieceCopy);
    // Every copy of every working piece of the loaded sources with no item
    function Unplaced: TDrapePieceCopyArray;
    // The copy's points placed on the body: its seam line, opened out on a
    // fold. False when the piece cannot be found or is not placed.
    function PlacedOutline(const Copy: TDrapePieceCopy; out Points: TVec3Array): boolean;
    // Places Copy so its side of Seam lies along the other side's placed
    // copy, Gap apart; Folded turns it over about the seam. False when the
    // copy is not in the seam or no copy of the other side is placed.
    function AlignToSeam(const Copy: TDrapePieceCopy; Seam: TSeamObject; Folded: boolean; out Placement: TDrapePlacement): boolean;
    // The seams, darts left out, that join Copy to a placed copy
    function AlignableSeams(const Copy: TDrapePieceCopy): TSeamObjectArray;
    // Three lines (start, middle, end) for each seam between placed copies
    function SeamLinks: TDrapeSeamLinkArray;
    // Places every unplaced copy that can be, as a first guess: the largest
    // piece of each source in front of the body, pieces sewn to a placed one
    // along their seam, the other of a mirrored pair as its mirror image, and
    // the rest in a row beside the body. Returns how many were placed.
    function GuessPlacements: integer;
    function Problems: TDrapeProblemArray;
    property Sources: TPatternSourceList read GetSources;
  end;

// Whether a copy is cut mirrored: the even copies of a mirrored piece not on a
// fold, as the publish app flips them
function CopyIsMirrored(Piece: TPieceObject; Copy: integer): boolean;
function DrapePieceCopy(SourceId: integer; const PieceKey: string; Copy: integer): TDrapePieceCopy;
function DrapeFileVersions: TFormatVersions;
// What the drape app opens for a pattern: the drape file named after it when
// there is one, else the pattern, which starts a new one
function DrapeTargetFor(const PatternFile: string): string;

resourcestring
  rsDrapeWrongFormat = 'This is not a drape file';
  rsDrapeUnits = 'Units "%s" are not supported; use mm';
  rsDrapeList = 'The file has no valid "%s" list';
  rsDrapeBadPlacement = 'Placement %d is not valid';
  rsDrapeUnknownSource = 'Placement %d uses source %d, which is not in the file';
  rsDrapeRepeatedPlacement = 'Placement %d places a copy already placed';
  rsDrapeBadBody = 'The body is not valid';
  rsDrapeBadGap = 'The gap must be 0 or more';
  rsDrapeSourceProblem = '%s: %s';
  rsDrapePieceGone = '%s: piece %s no longer exists';
  rsDrapeExtraCopy = '%s: %s is cut %d times now, but copy %d is still placed';
  rsDrapePieceFailing = '%s: %s cannot be placed: %s';
  rsDrapeUnplaced = '%s: %s (copy %d of %d) is not placed, so it is left out';
  rsDrapeBodyProblem = 'The body: %s';
  rsDrapeBodySize = 'Size "%s" is not in the body''s measurement set';
  rsDrapeNoPieces = '%s has no pieces. Make them in the drafting app and save the pattern';

implementation

uses
  Math, fpjson, Sloper.Core.JSON, Sloper.Core.Draft, Sloper.Core.EvalTypes;

const
  BODY_KIND_NAMES: array[TDrapeBodyKind] of string = ('measurements', 'none');
  // Where guesses go with no body: the height (mm) of the middle of the first
  // piece, and how far in front of the centre line it goes, less the gap
  GUESS_HEIGHT = 1000;
  GUESS_BODY_DEPTH = 150;
  // Pieces with no seams wait in a row this far (mm) to the body's right,
  // this far apart
  GUESS_ROW_SIDE = 600;
  GUESS_ROW_STEP = 50;

function CopyIsMirrored(Piece: TPieceObject; Copy: integer): boolean;
begin
  Result := Piece.Mirrored and not Piece.OnFold and not Odd(Copy);
end;

function DrapePieceCopy(SourceId: integer; const PieceKey: string; Copy: integer): TDrapePieceCopy;
begin
  Result.SourceId := SourceId;
  Result.PieceKey := PieceKey;
  Result.Copy := Copy;
end;

function SameCopy(const First, Second: TDrapePieceCopy): boolean;
begin
  Result := (First.SourceId = Second.SourceId) and (First.PieceKey = Second.PieceKey) and (First.Copy = Second.Copy);
end;

function DrapeTargetFor(const PatternFile: string): string;
begin
  Result := ChangeFileExt(PatternFile, DRAPE_EXTENSION);
  if not FileExists(Result) then
    Result := PatternFile;
end;

function DrapeFileVersions: TFormatVersions;
begin
  Result.Current := DRAPE_VERSION;
  Result.Steps := [];
end;

{ TDrape }

constructor TDrape.Create;
begin
  FSources := TPatternSources.Create;
  Clear;
end;

destructor TDrape.Destroy;
begin
  FreeAndNil(FBodySet);
  FreeAndNil(FSources);
  inherited Destroy;
end;

procedure TDrape.Clear;
begin
  FSources.Clear;
  FreeAndNil(FBodySet);
  FBodyError := '';
  Name := '';
  Body := Default(TDrapeBody);
  Gap := DEFAULT_DRAPE_GAP;
  Items := nil;
end;

function TDrape.GetSources: TPatternSourceList;
begin
  Result := FSources.Items;
end;

function TDrape.AddSource(const APatternFile, AMeasurementFile, ASize: string): TPatternSource;
begin
  Result := FSources.Add(APatternFile, AMeasurementFile, ASize);
end;

procedure TDrape.RemoveSource(Source: TPatternSource);
var
  Index: integer;
begin
  for Index := High(Items) downto 0 do
    if Items[Index].Piece.SourceId = Source.Id then
      System.Delete(Items, Index, 1);
  FSources.Remove(Source);
end;

function TDrape.FindSource(Id: integer): TPatternSource;
begin
  Result := FSources.FindById(Id);
end;

function TDrape.StoredPath(const Path: string): string;
begin
  Result := StoredSourcePath(FileName, Path);
end;

procedure TDrape.LoadSources;
begin
  FSources.LoadAll(FileName);
  LoadBody;
end;

procedure TDrape.LoadBody;
var
  Path, Err: string;
begin
  FreeAndNil(FBodySet);
  FBodyError := '';
  if (Body.Kind = bkNone) or (Body.MeasurementFile = '') then
    Exit;
  Path := ResolveSourcePath(FileName, Body.MeasurementFile);
  if not FileExists(Path) then
  begin
    FBodyError := Format(rsPatternSourcesNoFile, [Path]);
    Exit;
  end;
  FBodySet := TMeasurementSet.Create;
  if not FBodySet.LoadFromFile(Path, Err) then
  begin
    FBodyError := Err;
    FreeAndNil(FBodySet);
  end;
end;

function TDrape.BodyMeasures(out Measures: TBodyMeasures): boolean;
var
  BodySet: TMeasurementSet;
  SizeIndex: integer;
begin
  Measures := DefaultBodyMeasures;
  if Body.Kind = bkNone then
    Exit(False);
  Result := True;
  if Body.MeasurementFile <> '' then
    BodySet := FBodySet
  else if (Sources.Count > 0) and (Sources[0].LoadError = '') then
    BodySet := Sources[0].Measurements
  else
    BodySet := nil;
  if not Assigned(BodySet) then
    Exit;
  SizeIndex := -1;
  if Body.Size <> '' then
  begin
    SizeIndex := BodySet.IndexOfSize(Body.Size);
    if SizeIndex < 0 then
      Exit;
  end;
  Measures := BodyMeasuresFrom(BodySet, SizeIndex);
end;

procedure TDrape.GuessFrame(out Height, Depth: double);
var
  Measures: TBodyMeasures;
begin
  Height := GUESS_HEIGHT;
  Depth := GUESS_BODY_DEPTH;
  if BodyMeasures(Measures) then
  begin
    Height := Measures.WaistHeight;
    Depth := BodyFrontDepth(Measures);
  end;
end;

function Vec3ToJSON(const Value: TVec3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(JSONFloat(Value.X));
  Result.Add(JSONFloat(Value.Y));
  Result.Add(JSONFloat(Value.Z));
end;

function JSONToVec3(Data: TJSONData; out Value: TVec3): boolean;
var
  Index: integer;
  Parts: array[0..2] of double;
begin
  Value := Vec3(0, 0, 0);
  if not Assigned(Data) or (Data.JSONType <> jtArray) or (Data.Count <> 3) then
    Exit(False);
  for Index := 0 to 2 do
  begin
    if Data.Items[Index].JSONType <> jtNumber then
      Exit(False);
    Parts[Index] := Data.Items[Index].AsFloat;
    if IsNan(Parts[Index]) or IsInfinite(Parts[Index]) then
      Exit(False);
  end;
  Value := Vec3(Parts[0], Parts[1], Parts[2]);
  Result := True;
end;

function TDrape.SaveToText: string;
var
  Root, Item: TJSONObject;
  List: TJSONArray;
  Entry: TDrapeItem;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', DRAPE_FORMAT);
    Root.Add('version', DRAPE_VERSION);
    Root.Add('units', 'mm');
    Root.Add('name', Name);
    FSources.SaveTo(Root);
    Item := TJSONObject.Create;
    Root.Add('body', Item);
    Item.Add('kind', BODY_KIND_NAMES[Body.Kind]);
    if Body.MeasurementFile <> '' then
      Item.Add('measurementFile', Body.MeasurementFile);
    if Body.Size <> '' then
      Item.Add('size', Body.Size);
    Root.Add('gap', JSONFloat(Gap));
    List := TJSONArray.Create;
    Root.Add('placements', List);
    for Entry in Items do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('source', Entry.Piece.SourceId);
      Item.Add('piece', StrToInt(Entry.Piece.PieceKey));
      Item.Add('copy', Entry.Piece.Copy);
      Item.Add('position', Vec3ToJSON(Entry.Placement.Position));
      Item.Add('rotation', Vec3ToJSON(Entry.Placement.Rotation));
    end;
    Result := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
end;

function ReadBody(Data: TJSONData; out Body: TDrapeBody): boolean;
var
  Item: TJSONObject;
  KindText: string;
  Kind: TDrapeBodyKind;
begin
  Body := Default(TDrapeBody);
  if not Assigned(Data) then
    Exit(True);
  if Data.JSONType <> jtObject then
    Exit(False);
  Item := TJSONObject(Data);
  if not GetJSONString(Item, 'kind', KindText) then
    Exit(False);
  Result := False;
  for Kind := Low(TDrapeBodyKind) to High(TDrapeBodyKind) do
    if KindText = BODY_KIND_NAMES[Kind] then
    begin
      Body.Kind := Kind;
      Result := True;
    end;
  GetJSONString(Item, 'measurementFile', Body.MeasurementFile);
  GetJSONString(Item, 'size', Body.Size);
end;

function TDrape.LoadFromText(const Text: string; out ErrorMessage: string): boolean;
var
  Root, Item: TJSONObject;
  Data: TJSONData;
  TextValue: string;
  Version, Index, PieceId: integer;
  Entry: TDrapeItem;

  function Fail(const Msg: string): boolean;
  begin
    ErrorMessage := Msg;
    Clear;
    Result := False;
  end;

begin
  Clear;
  ErrorMessage := '';
  if not ParseJSONObject(Text, Root, ErrorMessage) then
    Exit(False);
  try
    if not GetJSONString(Root, 'format', TextValue) or (TextValue <> DRAPE_FORMAT) or not GetJSONInteger(Root, 'version', Version) then
      Exit(Fail(rsDrapeWrongFormat));
    if not (UpgradeFile(Root, Version, DrapeFileVersions, TextValue) in [vcCurrent, vcUpgraded]) then
      Exit(Fail(TextValue));
    if GetJSONString(Root, 'units', TextValue) and (TextValue <> 'mm') then
      Exit(Fail(Format(rsDrapeUnits, [TextValue])));
    GetJSONString(Root, 'name', Name);
    if not FSources.LoadFrom(Root, TextValue) then
      Exit(Fail(TextValue));
    if not ReadBody(Root.Find('body'), Body) then
      Exit(Fail(rsDrapeBadBody));
    if Assigned(Root.Find('gap')) and (not GetJSONNumber(Root, 'gap', Gap) or (Gap < 0)) then
      Exit(Fail(rsDrapeBadGap));

    Data := Root.Find('placements');
    if Assigned(Data) then
    begin
      if Data.JSONType <> jtArray then
        Exit(Fail(Format(rsDrapeList, ['placements'])));
      for Index := 0 to Data.Count - 1 do
      begin
        if Data.Items[Index].JSONType <> jtObject then
          Exit(Fail(Format(rsDrapeList, ['placements'])));
        Item := TJSONObject(Data.Items[Index]);
        Entry := Default(TDrapeItem);
        if not GetJSONInteger(Item, 'source', Entry.Piece.SourceId) or not GetJSONId(Item, 'piece', PieceId) or not
          JSONToVec3(Item.Find('position'), Entry.Placement.Position) or not JSONToVec3(Item.Find('rotation'), Entry.Placement.Rotation) then
          Exit(Fail(Format(rsDrapeBadPlacement, [Index + 1])));
        if not Assigned(FindSource(Entry.Piece.SourceId)) then
          Exit(Fail(Format(rsDrapeUnknownSource, [Index + 1, Entry.Piece.SourceId])));
        Entry.Piece.PieceKey := IntToStr(PieceId);
        if not GetJSONInteger(Item, 'copy', Entry.Piece.Copy) then
          Entry.Piece.Copy := 1;
        if (Entry.Piece.Copy < 1) then
          Exit(Fail(Format(rsDrapeBadPlacement, [Index + 1])));
        if IndexOf(Entry.Piece) >= 0 then
          Exit(Fail(Format(rsDrapeRepeatedPlacement, [Index + 1])));
        SetLength(Items, Length(Items) + 1);
        Items[High(Items)] := Entry;
      end;
    end;
    Result := True;
  finally
    FreeAndNil(Root);
  end;
end;

function TDrape.SaveToFile(const AFileName: string; out ErrorMessage: string): boolean;
var
  OldName: string;
begin
  // Paths are stored relative to where the file goes
  OldName := FileName;
  FileName := AFileName;
  Result := WriteTextFileAtomic(AFileName, SaveToText, ErrorMessage);
  if not Result then
    FileName := OldName;
end;

function TDrape.LoadFromFile(const AFileName: string; out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Clear;
  if not ReadTextFile(AFileName, Text, ErrorMessage) then
    Exit(False);
  Result := LoadFromText(Text, ErrorMessage);
  if Result then
    FileName := AFileName;
end;

function TDrape.FindPiece(const Copy: TDrapePieceCopy; out Piece: TPieceObject): boolean;
var
  Source: TPatternSource;
  Node: TObject;
begin
  Piece := nil;
  Source := FindSource(Copy.SourceId);
  if not Assigned(Source) or not Assigned(Source.Pattern) then
    Exit(False);
  Node := Source.Pattern.FindNode(Copy.PieceKey);
  Result := Node is TPieceObject;
  if Result then
    Piece := TPieceObject(Node);
end;

function TDrape.IndexOf(const Copy: TDrapePieceCopy): integer;
begin
  for Result := 0 to High(Items) do
    if SameCopy(Items[Result].Piece, Copy) then
      Exit;
  Result := -1;
end;

procedure TDrape.Place(const Copy: TDrapePieceCopy; const Placement: TDrapePlacement);
var
  Index: integer;
begin
  Index := IndexOf(Copy);
  if Index < 0 then
  begin
    SetLength(Items, Length(Items) + 1);
    Index := High(Items);
    Items[Index].Piece := Copy;
  end;
  Items[Index].Placement := Placement;
end;

procedure TDrape.Unplace(const Copy: TDrapePieceCopy);
var
  Index: integer;
begin
  Index := IndexOf(Copy);
  if Index >= 0 then
    System.Delete(Items, Index, 1);
end;

function CanPlace(Piece: TPieceObject): boolean;
begin
  Result := (Piece.State = esValid) and (Length(Piece.Outline) > 0);
end;

function TDrape.Unplaced: TDrapePieceCopyArray;
var
  Source: TPatternSource;
  Index, Copy: integer;
  Piece: TPieceObject;
begin
  Result := nil;
  for Source in FSources.Items do
    if Assigned(Source.Pattern) then
      for Index := 0 to Source.Pattern.ObjectCount - 1 do
        if Source.Pattern.Objects[Index] is TPieceObject then
        begin
          Piece := TPieceObject(Source.Pattern.Objects[Index]);
          if CanPlace(Piece) then
            for Copy := 1 to Piece.CutCount do
              if IndexOf(DrapePieceCopy(Source.Id, Piece.Key, Copy)) < 0 then
                Insert(DrapePieceCopy(Source.Id, Piece.Key, Copy), Result, Length(Result));
        end;
end;

function TDrape.PlacedOutline(const Copy: TDrapePieceCopy; out Points: TVec3Array): boolean;
var
  Piece: TPieceObject;
  Index: integer;
begin
  Points := nil;
  Index := IndexOf(Copy);
  Result := (Index >= 0) and FindPiece(Copy, Piece) and CanPlace(Piece);
  if Result then
    Points := PlacePoints(PlacedSeamLine(Piece), PieceAnchor(Piece), CopyIsMirrored(Piece, Copy.Copy), Items[Index].Placement);
end;

// The run of a seam side on one piece, in the seam's direction, as drafted:
// from the start of its first entry on the piece, through the point halfway
// along it, to the end of its last. False when the side has no entry on the
// piece.
function SideRun(Pattern: TPattern; Seam: TSeamObject; Piece: TPieceObject; OnSideB: boolean; out First, Middle, Last: TVec2): boolean;
var
  Side: TSeamSide;
  Entry: TSeamEntry;
  Edges: array of TEdgeObject;
  Forward: array of boolean;
  Node: TObject;
  Index: integer;
  Total, Along: double;

  function PointOn(EdgeIndex: integer; Distance: double): TVec2;
  begin
    if Forward[EdgeIndex] then
      Result := Edges[EdgeIndex].PointAtLength(Distance)
    else
      Result := Edges[EdgeIndex].PointAtLength(Edges[EdgeIndex].Length - Distance);
  end;

begin
  First := Vec2(0, 0);
  Middle := First;
  Last := First;
  if OnSideB then
    Side := Seam.SideB
  else
    Side := Seam.SideA;
  Edges := nil;
  Forward := nil;
  Total := 0;
  for Entry in Side do
    if Entry.PieceKey = Piece.Key then
    begin
      Node := Pattern.FindNode(Entry.EdgeKey);
      if not (Node is TEdgeObject) then
        Continue;
      Insert(TEdgeObject(Node), Edges, Length(Edges));
      Insert(Seam.RunsForward(Piece, Entry, OnSideB), Forward, Length(Forward));
      Total := Total + TEdgeObject(Node).Length;
    end;
  if Length(Edges) = 0 then
    Exit(False);
  First := PointOn(0, 0);
  Last := PointOn(High(Edges), Edges[High(Edges)].Length);
  Along := Total / 2;
  for Index := 0 to High(Edges) do
  begin
    if (Along <= Edges[Index].Length) or (Index = High(Edges)) then
    begin
      Middle := PointOn(Index, Min(Along, Edges[Index].Length));
      Break;
    end;
    Along := Along - Edges[Index].Length;
  end;
  Result := True;
end;

function SideHasPiece(const Side: TSeamSide; const PieceKey: string): boolean;
var
  Entry: TSeamEntry;
begin
  for Entry in Side do
    if Entry.PieceKey = PieceKey then
      Exit(True);
  Result := False;
end;

function TDrape.FindPartner(const Copy: TDrapePieceCopy; Seam: TSeamObject; out OnSideB: boolean; out PartnerIndex: integer): boolean;
var
  Piece, Partner: TPieceObject;
  Other: TSeamSide;
  Entry: TSeamEntry;
  Candidate: TDrapePieceCopy;
  Index: integer;
  Mirrored: boolean;
begin
  PartnerIndex := -1;
  OnSideB := False;
  if not FindPiece(Copy, Piece) or not CanPlace(Piece) then
    Exit(False);
  OnSideB := SideHasPiece(Seam.SideB, Piece.Key) and not SideHasPiece(Seam.SideA, Piece.Key);
  if not SideHasPiece(Seam.SideA, Piece.Key) and not OnSideB then
    Exit(False);
  if OnSideB then
    Other := Seam.SideA
  else
    Other := Seam.SideB;
  Mirrored := CopyIsMirrored(Piece, Copy.Copy);
  // A placed copy of the other side, preferring one on the same side of the
  // body (left with left) as a seam joins
  for Entry in Other do
    for Index := 0 to High(Items) do
    begin
      Candidate := Items[Index].Piece;
      if (Candidate.SourceId <> Copy.SourceId) or (Candidate.PieceKey <> Entry.PieceKey) or SameCopy(Candidate, Copy) then
        Continue;
      if not FindPiece(Candidate, Partner) or not CanPlace(Partner) then
        Continue;
      if (PartnerIndex < 0) or ((CopyIsMirrored(Partner, Candidate.Copy) = Mirrored) and
        (CopyIsMirrored(Partner, Items[PartnerIndex].Piece.Copy) <> Mirrored)) then
        PartnerIndex := Index;
    end;
  Result := PartnerIndex >= 0;
end;

function TDrape.AlignToSeam(const Copy: TDrapePieceCopy; Seam: TSeamObject; Folded: boolean; out Placement: TDrapePlacement): boolean;
var
  Piece, Partner: TPieceObject;
  OnSideB, Mirrored, PartnerMirrored: boolean;
  PartnerIndex: integer;
  EdgeStart, EdgeMiddle, EdgeEnd, PartnerStart, PartnerMiddle, PartnerEnd, PartnerAnchor: TVec2;
  Partnered: TDrapePlacement;
  Pattern: TPattern;
begin
  Placement := Default(TDrapePlacement);
  if not FindPartner(Copy, Seam, OnSideB, PartnerIndex) or not FindPiece(Copy, Piece) or not FindPiece(Items[PartnerIndex].Piece, Partner) then
    Exit(False);
  Pattern := FindSource(Copy.SourceId).Pattern;
  if not SideRun(Pattern, Seam, Piece, OnSideB, EdgeStart, EdgeMiddle, EdgeEnd) or not SideRun(Pattern, Seam, Partner, not
    OnSideB, PartnerStart, PartnerMiddle, PartnerEnd) then
    Exit(False);
  Mirrored := CopyIsMirrored(Piece, Copy.Copy);
  Partnered := Items[PartnerIndex].Placement;
  PartnerMirrored := CopyIsMirrored(Partner, Items[PartnerIndex].Piece.Copy);
  PartnerAnchor := PieceAnchor(Partner);
  Placement := AlignedPlacement(PlacePoint(PartnerStart, PartnerAnchor, PartnerMirrored, Partnered),
    PlacePoint(PartnerEnd, PartnerAnchor, PartnerMirrored, Partnered),
    PlacePoint(PolygonMiddle(PlacedSeamLine(Partner)), PartnerAnchor, PartnerMirrored, Partnered), PlacedNormal(Partnered),
    EdgeStart, EdgeEnd, PolygonMiddle(PlacedSeamLine(Piece)), PieceAnchor(Piece), Mirrored, Gap, Folded);
  Result := True;
end;

function IsDart(Seam: TSeamObject; const PieceKey: string): boolean;
begin
  Result := SideHasPiece(Seam.SideA, PieceKey) and SideHasPiece(Seam.SideB, PieceKey);
end;

function TDrape.AlignableSeams(const Copy: TDrapePieceCopy): TSeamObjectArray;
var
  Source: TPatternSource;
  Index, PartnerIndex: integer;
  Seam: TSeamObject;
  OnSideB: boolean;
begin
  Result := nil;
  Source := FindSource(Copy.SourceId);
  if not Assigned(Source) or not Assigned(Source.Pattern) then
    Exit;
  for Index := 0 to Source.Pattern.ObjectCount - 1 do
    if Source.Pattern.Objects[Index] is TSeamObject then
    begin
      Seam := TSeamObject(Source.Pattern.Objects[Index]);
      if (Seam.State = esValid) and Seam.UsesPiece(Copy.PieceKey) and not IsDart(Seam, Copy.PieceKey) and
        FindPartner(Copy, Seam, OnSideB, PartnerIndex) then
        Insert(Seam, Result, Length(Result));
    end;
end;

function TDrape.SeamLinks: TDrapeSeamLinkArray;
var
  ItemIndex, PartnerIndex, Index: integer;
  Copy: TDrapePieceCopy;
  Seam: TSeamObject;
  Piece, Partner: TPieceObject;
  OnSideB: boolean;
  Pattern: TPattern;
  Own, Theirs: array[0..2] of TVec2;
  Link: TDrapeSeamLink;
begin
  Result := nil;
  for ItemIndex := 0 to High(Items) do
  begin
    Copy := Items[ItemIndex].Piece;
    if not FindPiece(Copy, Piece) then
      Continue;
    Pattern := FindSource(Copy.SourceId).Pattern;
    for Seam in AlignableSeams(Copy) do
    begin
      // Once per seam and pair: from the copy on side A
      if not FindPartner(Copy, Seam, OnSideB, PartnerIndex) or OnSideB or not FindPiece(Items[PartnerIndex].Piece, Partner) then
        Continue;
      if not SideRun(Pattern, Seam, Piece, False, Own[0], Own[1], Own[2]) or not SideRun(Pattern, Seam, Partner, True, Theirs[0], Theirs[1], Theirs[2]) then
        Continue;
      for Index := 0 to 2 do
      begin
        Link.Seam := Seam;
        Link.Item := ItemIndex;
        Link.From := PlacePoint(Own[Index], PieceAnchor(Piece), CopyIsMirrored(Piece, Copy.Copy), Items[ItemIndex].Placement);
        Link.Onto := PlacePoint(Theirs[Index], PieceAnchor(Partner), CopyIsMirrored(Partner, Items[PartnerIndex].Piece.Copy),
          Items[PartnerIndex].Placement);
        Insert(Link, Result, Length(Result));
      end;
    end;
  end;
end;

function TDrape.LongestPlacedSeam(const Copy: TDrapePieceCopy; out Seam: TSeamObject; out Length: double): boolean;
var
  Source: TPatternSource;
  Index: integer;
  Candidate: TSeamObject;
  Placement: TDrapePlacement;
begin
  Seam := nil;
  Length := 0;
  Source := FindSource(Copy.SourceId);
  if not Assigned(Source) or not Assigned(Source.Pattern) then
    Exit(False);
  for Index := 0 to Source.Pattern.ObjectCount - 1 do
    if Source.Pattern.Objects[Index] is TSeamObject then
    begin
      Candidate := TSeamObject(Source.Pattern.Objects[Index]);
      // A dart joins a piece to itself, which places nothing
      if not Candidate.UsesPiece(Copy.PieceKey) or (Candidate.State <> esValid) then
        Continue;
      if IsDart(Candidate, Copy.PieceKey) then
        Continue;
      if (Candidate.LengthA > Length) and AlignToSeam(Copy, Candidate, False, Placement) then
      begin
        Seam := Candidate;
        Length := Candidate.LengthA;
      end;
    end;
  Result := Assigned(Seam);
end;

function TDrape.GuessFirstPieces: integer;
var
  Source: TPatternSource;
  Copy, Largest: TDrapePieceCopy;
  Item: TDrapeItem;
  Piece: TPieceObject;
  LargestArea: double;
  Placed: boolean;
  Turn, Height, Depth: double;
  Placement: TDrapePlacement;
begin
  Result := 0;
  GuessFrame(Height, Depth);
  for Source in FSources.Items do
  begin
    Placed := False;
    for Item in Items do
      Placed := Placed or (Item.Piece.SourceId = Source.Id);
    if Placed then
      Continue;
    LargestArea := 0;
    Largest := Default(TDrapePieceCopy);
    for Copy in Unplaced do
      if (Copy.SourceId = Source.Id) and (Copy.Copy = 1) and FindPiece(Copy, Piece) and (Abs(Piece.Area) > LargestArea) then
      begin
        LargestArea := Abs(Piece.Area);
        Largest := Copy;
      end;
    if (LargestArea <= 0) or not FindPiece(Largest, Piece) then
      Continue;
    // Turned about Y so the grainline points up
    Turn := 0;
    if (Piece.GrainKind <> gkNone) and (Piece.Grainline.Length > EPSILON) then
      Turn := Piece.Grainline.Angle - 90;
    Placement := UprightPlacement(Vec3(0, -(Depth + Gap), Height));
    Placement.Rotation := Vec3(0, Turn, 0);
    Place(Largest, Placement);
    Inc(Result);
  end;
end;

function TDrape.GuessAlongSeams: integer;
var
  Copy, Best: TDrapePieceCopy;
  Seam, BestSeam: TSeamObject;
  SeamLength, BestLength: double;
  Placement: TDrapePlacement;
  Piece: TPieceObject;
begin
  Result := 0;
  repeat
    BestLength := 0;
    BestSeam := nil;
    Best := Default(TDrapePieceCopy);
    // The other of a mirrored pair follows its partner (GuessMirroredCopies)
    for Copy in Unplaced do
      if FindPiece(Copy, Piece) and not CopyIsMirrored(Piece, Copy.Copy) and LongestPlacedSeam(Copy, Seam, SeamLength) and
        (SeamLength > BestLength) then
      begin
        BestLength := SeamLength;
        BestSeam := Seam;
        Best := Copy;
      end;
    if not Assigned(BestSeam) or not AlignToSeam(Best, BestSeam, False, Placement) then
      Break;
    Place(Best, Placement);
    Inc(Result);
  until False;
end;

function TDrape.GuessMirroredCopies: integer;
var
  Copy: TDrapePieceCopy;
  Piece: TPieceObject;
  Partner: integer;
begin
  Result := 0;
  for Copy in Unplaced do
    if FindPiece(Copy, Piece) and CopyIsMirrored(Piece, Copy.Copy) then
    begin
      Partner := IndexOf(DrapePieceCopy(Copy.SourceId, Copy.PieceKey, Copy.Copy - 1));
      if Partner >= 0 then
      begin
        Place(Copy, MirroredPlacement(Items[Partner].Placement));
        Inc(Result);
      end;
    end;
end;

function TDrape.GuessRest: integer;
var
  Copy: TDrapePieceCopy;
  Piece: TPieceObject;
  Across, Height, Depth: double;
  Extent: TVec2;
begin
  Result := 0;
  GuessFrame(Height, Depth);
  Across := GUESS_ROW_SIDE;
  for Copy in Unplaced do
    if FindPiece(Copy, Piece) then
    begin
      Extent := PointsExtent(PlacedSeamLine(Piece));
      Place(Copy, UprightPlacement(Vec3(-(Across + Extent.X / 2), -(Depth + Gap), Height)));
      Across := Across + Extent.X + GUESS_ROW_STEP;
      Inc(Result);
    end;
end;

function TDrape.GuessPlacements: integer;
var
  Step: integer;
begin
  Result := GuessFirstPieces;
  repeat
    Step := GuessAlongSeams + GuessMirroredCopies;
    Inc(Result, Step);
  until Step = 0;
  Inc(Result, GuessRest);
end;

function TDrape.Problems: TDrapeProblemArray;

  procedure Add(const AText: string; Item: integer);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Text := AText;
    Result[High(Result)].Item := Item;
  end;

var
  Source: TPatternSource;
  Index, PieceCount: integer;
  Piece: TPieceObject;
  Copy: TDrapePieceCopy;
  BodySet: TMeasurementSet;
begin
  Result := nil;
  if FBodyError <> '' then
    Add(Format(rsDrapeBodyProblem, [FBodyError]), -1);
  if (Body.Kind <> bkNone) and (Body.Size <> '') then
  begin
    if Body.MeasurementFile <> '' then
      BodySet := FBodySet
    else if Sources.Count > 0 then
      BodySet := Sources[0].Measurements
    else
      BodySet := nil;
    if Assigned(BodySet) and (BodySet.IndexOfSize(Body.Size) < 0) then
      Add(Format(rsDrapeBodySize, [Body.Size]), -1);
  end;
  for Source in FSources.Items do
    if Source.LoadError <> '' then
      Add(Format(rsDrapeSourceProblem, [ExtractFileName(Source.PatternFile), Source.LoadError]), -1)
    else if Assigned(Source.Pattern) then
    begin
      PieceCount := 0;
      for Index := 0 to Source.Pattern.ObjectCount - 1 do
        if Source.Pattern.Objects[Index] is TPieceObject then
        begin
          Inc(PieceCount);
          Piece := TPieceObject(Source.Pattern.Objects[Index]);
          if not CanPlace(Piece) then
            Add(Format(rsDrapePieceFailing, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Piece.Message]), -1);
        end;
      if PieceCount = 0 then
        Add(Format(rsDrapeNoPieces, [ExtractFileName(Source.PatternFile)]), -1);
    end;
  for Index := 0 to High(Items) do
  begin
    Source := FindSource(Items[Index].Piece.SourceId);
    if not Assigned(Source) or not Assigned(Source.Pattern) then
      Continue;
    if not FindPiece(Items[Index].Piece, Piece) then
      Add(Format(rsDrapePieceGone, [ExtractFileName(Source.PatternFile), Items[Index].Piece.PieceKey]), Index)
    else if Items[Index].Piece.Copy > Piece.CutCount then
      Add(Format(rsDrapeExtraCopy, [ExtractFileName(Source.PatternFile), Piece.DisplayName, Piece.CutCount, Items[Index].Piece.Copy]), Index);
  end;
  for Copy in Unplaced do
    if FindPiece(Copy, Piece) then
      Add(Format(rsDrapeUnplaced, [ExtractFileName(FindSource(Copy.SourceId).PatternFile), Piece.DisplayName, Copy.Copy, Piece.CutCount]), -1);
end;

end.
