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

// The drape exported for Blender: the scene file, and the pieces' and body's
// OBJ meshes it names.
unit Sloper.Tests.DrapeExport;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.PatternSources, Sloper.Core.DrapePlacement, Sloper.Core.DrapeFile,
  Sloper.Core.BodyForm, Sloper.Core.Materials, Sloper.Output.DrapeExport, Sloper.Output.BlenderRun;

type
  // The objects of an OBJ file: their names, vertices and triangles, which
  // count vertices from 0 within the object, as Blender's do
  TObjObject = record
    Name: string;
    Vertices: TVec3Array;
    Triangles: array of array[0..2] of integer;
  end;

  TObjObjectArray = array of TObjObject;

  TTestDrapeExport = class(TOSTestCase)
  private
    FDrape: TDrape;
    FPattern: TPattern;
    FSource: TPatternSource;
    function Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
    function EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
    procedure FrontAndBack(out Front, Back: TPieceObject);
    function Scene(const Exported: TDrapeExport): TJSONObject;
    // A triangle's normal in its object's frame
    function Normal(const Item: TObjObject; Triangle: integer): TVec3;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFileNames;
    procedure TestSceneListsObjectsAndSeams;
    procedure TestPairsMeetWhenPlaced;
    procedure TestMeshesFaceTheRightSide;
    procedure TestMirroredCopyMirrored;
    procedure TestBody;
    procedure TestNoBody;
    procedure TestUnplacedLeftOut;
    procedure TestScriptFound;
    procedure TestBlenderParameters;
    procedure TestBlenderProgress;
    procedure TestRunReadsLinesAndCode;
    procedure TestRunStops;
  end;

  // Keeps the lines a run passes on
  TLineCatcher = class
  public
    Lines: TStringArray;
    procedure Line(const Text: string);
  end;

// Reads the OBJ text the export writes
function ParseObj(const Text: string): TObjObjectArray;

implementation

uses
  {$IFDEF UNIX}
  BaseUnix,
  {$ENDIF}
  Classes, Sloper.Core.JSON, Sloper.Core.Mesher, Sloper.Core.AppPaths, Sloper.Core.Settings;

const
  SPACING = 10;
  // mm: OBJ coordinates are written to a thousandth
  OBJ_TOLERANCE = 1e-3;

function ParseObj(const Text: string): TObjObjectArray;
var
  Line, Corner: string;
  Parts: TStringArray;
  Base, Index: integer;
  Settings: TFormatSettings;
  Triangle: array[0..2] of integer;
  Current: integer;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := nil;
  Current := -1;
  // OBJ indexes count from 1 across the file
  Base := 1;
  for Line in Text.Split([#10]) do
  begin
    Parts := Line.Split([' ']);
    if Length(Parts) = 0 then
      Continue;
    if Parts[0] = 'o' then
    begin
      if Current >= 0 then
        Inc(Base, Length(Result[Current].Vertices));
      SetLength(Result, Length(Result) + 1);
      Current := High(Result);
      Result[Current].Name := Copy(Line, 3, MaxInt);
    end
    else if Parts[0] = 'v' then
      Insert(Vec3(StrToFloat(Parts[1], Settings), StrToFloat(Parts[2], Settings), StrToFloat(Parts[3], Settings)), Result[Current].Vertices,
        Length(Result[Current].Vertices))
    else if Parts[0] = 'f' then
    begin
      for Index := 0 to 2 do
      begin
        Corner := Parts[Index + 1];
        if Pos('/', Corner) > 0 then
          Corner := Copy(Corner, 1, Pos('/', Corner) - 1);
        Triangle[Index] := StrToInt(Corner) - Base;
      end;
      SetLength(Result[Current].Triangles, Length(Result[Current].Triangles) + 1);
      Result[Current].Triangles[High(Result[Current].Triangles)] := Triangle;
    end;
  end;
end;

procedure TTestDrapeExport.SetUp;
begin
  FDrape := TDrape.Create;
  FDrape.Name := 'Dress';
  FSource := FDrape.AddSource('dress.sloper', '', '');
  FPattern := TPattern.Create;
  FSource.Pattern := FPattern;
end;

procedure TTestDrapeExport.TearDown;
begin
  // The source owns the pattern
  FreeAndNil(FDrape);
end;

function TTestDrapeExport.Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
var
  Keys: array of string;
  Index: integer;
  Path: TPiecePath;
begin
  Keys := nil;
  SetLength(Keys, Length(Xs));
  for Index := 0 to High(Xs) do
    Keys[Index] := FPattern.AddFreePoint('', FloatToStr(Xs[Index]), FloatToStr(Ys[Index])).Key;
  Path := nil;
  SetLength(Path, Length(Keys));
  for Index := 0 to High(Keys) do
  begin
    Path[Index].EdgeKey := FPattern.AddLine(Keys[Index], Keys[(Index + 1) mod Length(Keys)], erOutline).Key;
    Path[Index].Reversed := False;
  end;
  FPattern.Evaluate;
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestDrapeExport.EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
var
  Index: integer;
  Edge: TEdgeObject;
begin
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Piece.Path[Index].EdgeKey));
    if (PointsNear(Edge.PointAtLength(0), A) and PointsNear(Edge.PointAtLength(Edge.Length), B)) or
      (PointsNear(Edge.PointAtLength(0), B) and PointsNear(Edge.PointAtLength(Edge.Length), A)) then
      Exit(Edge.Key);
  end;
  Fail('No edge');
  Result := '';
end;

procedure TTestDrapeExport.FrontAndBack(out Front, Back: TPieceObject);
var
  SideA, SideB: TSeamSide;
begin
  Front := Shape('Front', [0, 120, 120, 0], [0, 0, 200, 200]);
  Back := Shape('Back', [200, 300, 300, 200], [0, 0, 200, 200]);
  SideA := nil;
  SetLength(SideA, 1);
  SideA[0].PieceKey := Front.Key;
  SideA[0].EdgeKey := EdgeBetween(Front, Vec2(120, 0), Vec2(120, 200));
  SideB := nil;
  SetLength(SideB, 1);
  SideB[0].PieceKey := Back.Key;
  SideB[0].EdgeKey := EdgeBetween(Back, Vec2(200, 0), Vec2(200, 200));
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Side', SideA, SideB));
  FPattern.Evaluate;
  FDrape.Place(DrapePieceCopy(FSource.Id, Front.Key, 1), UprightPlacement(Vec3(-150, -200, 1000)));
  // Round to the side, as a back sewn to the front's side would go
  FDrape.Place(DrapePieceCopy(FSource.Id, Back.Key, 1), RoundBodyPlacement(UprightPlacement(Vec3(0, -200, 1000)), 90));
end;

function TTestDrapeExport.Scene(const Exported: TDrapeExport): TJSONObject;
var
  Err: string;
begin
  AssertTrue(Err, ParseJSONObject(DrapeSceneText(FDrape, Exported, 'dress.pieces.obj', 'dress.body.obj', SPACING), Result, Err));
end;

function TTestDrapeExport.Normal(const Item: TObjObject; Triangle: integer): TVec3;
var
  A, B, C: TVec3;
begin
  A := Item.Vertices[Item.Triangles[Triangle][0]];
  B := Item.Vertices[Item.Triangles[Triangle][1]];
  C := Item.Vertices[Item.Triangles[Triangle][2]];
  Result := Cross3(B - A, C - A);
end;

procedure TTestDrapeExport.TestFileNames;
var
  Files: TDrapeExportFiles;
begin
  AssertEquals(ConcatPaths(['out', 'skirt.blender.json']), DrapeExportTarget(ConcatPaths(['out', 'skirt.sdrape'])));
  Files := DrapeExportFiles(ConcatPaths(['out', 'skirt.blender.json']));
  AssertEquals(ConcatPaths(['out', 'skirt.pieces.obj']), Files.Pieces);
  AssertEquals(ConcatPaths(['out', 'skirt.body.obj']), Files.Body);
  // Any other name loses its extension
  Files := DrapeExportFiles('scene.json');
  AssertEquals('scene.pieces.obj', Files.Pieces);
end;

procedure TTestDrapeExport.TestSceneListsObjectsAndSeams;
var
  Front, Back: TPieceObject;
  Exported: TDrapeExport;
  Root: TJSONObject;
  Objects, Seams: TJSONArray;
  Item: TJSONObject;
begin
  FrontAndBack(Front, Back);
  Exported := BuildDrapeExport(FDrape, SPACING);
  AssertEquals('problems', 0, Length(Exported.Problems));
  Root := Scene(Exported);
  try
    AssertEquals(BLENDER_FORMAT, Root.Get('format', ''));
    AssertEquals('Dress', Root.Get('name', ''));
    AssertEquals('dress.pieces.obj', Root.Get('pieces', ''));
    AssertEquals('dress.body.obj', Root.Get('body', ''));
    Objects := Root.Arrays['objects'];
    AssertEquals(2, Objects.Count);
    Item := Objects.Objects[0];
    AssertEquals('dress Front 1', Item.Get('name', ''));
    AssertEquals(StrToInt(Front.Key), Item.Get('piece', 0));
    AssertEquals(1, Item.Get('copy', 0));
    AssertFalse(Item.Get('mirrored', True));
    AssertEquals(Length(Exported.Meshing.Meshes[0].Points), Item.Get('vertices', 0));
    AssertNear('position', -150, Item.Arrays['position'].Floats[0]);
    Seams := Root.Arrays['seams'];
    AssertEquals(1, Seams.Count);
    AssertEquals('Side', Seams.Objects[0].Get('name', ''));
    AssertEquals('a pair every 10 mm, both ends', 21, Seams.Objects[0].Arrays['pairs'].Count);
  finally
    FreeAndNil(Root);
  end;
end;

// Each pair's two vertices, placed as the scene says, are where the drape
// places them: on the two pieces' seam edges, level with each other
procedure TTestDrapeExport.TestPairsMeetWhenPlaced;
var
  Front, Back: TPieceObject;
  Exported: TDrapeExport;
  Root: TJSONObject;
  Objects: TObjObjectArray;
  Pairs: TJSONArray;
  Index: integer;
  Pair: TJSONObject;
  First, Second: TVec3;

  function Placed(ObjectIndex, Vertex: integer): TVec3;
  var
    Placement: TDrapePlacement;
    Item: TJSONObject;
  begin
    Item := Root.Arrays['objects'].Objects[ObjectIndex];
    Placement.Position := Vec3(Item.Arrays['position'].Floats[0], Item.Arrays['position'].Floats[1], Item.Arrays['position'].Floats[2]);
    Placement.Rotation := Vec3(Item.Arrays['rotation'].Floats[0], Item.Arrays['rotation'].Floats[1], Item.Arrays['rotation'].Floats[2]);
    Result := PlacementMatrix(Placement).Apply(Objects[ObjectIndex].Vertices[Vertex]) + Placement.Position;
  end;

begin
  FrontAndBack(Front, Back);
  Exported := BuildDrapeExport(FDrape, SPACING);
  Objects := ParseObj(DrapePiecesOBJ(FDrape, Exported));
  AssertEquals(2, Length(Objects));
  AssertEquals('dress Back 1', Objects[1].Name);
  Root := Scene(Exported);
  try
    Pairs := Root.Arrays['seams'].Objects[0].Arrays['pairs'];
    for Index := 0 to Pairs.Count - 1 do
    begin
      Pair := Pairs.Objects[Index];
      First := Placed(Pair.Get('first', -1), Pair.Get('firstVertex', -1));
      Second := Placed(Pair.Get('second', -1), Pair.Get('secondVertex', -1));
      AssertTrue('placed as the drape places it', PointsNear3(First, PlacePoint(
        Exported.Meshing.Meshes[Pair.Get('first', -1)].Points[Pair.Get('firstVertex', -1)], PieceAnchor(Front), False,
        FDrape.Items[0].Placement), OBJ_TOLERANCE * 2));
      AssertNear('level', First.Z, Second.Z, OBJ_TOLERANCE * 2);
    end;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestDrapeExport.TestMeshesFaceTheRightSide;
var
  Front, Back: TPieceObject;
  Objects: TObjObjectArray;
  Item: TObjObject;
  Triangle: integer;
begin
  FrontAndBack(Front, Back);
  Objects := ParseObj(DrapePiecesOBJ(FDrape, BuildDrapeExport(FDrape, SPACING)));
  for Item in Objects do
  begin
    AssertTrue('triangles', Length(Item.Triangles) > 0);
    for Triangle := 0 to High(Item.Triangles) do
    begin
      AssertNear('flat in its frame', 0, Item.Vertices[Item.Triangles[Triangle][0]].Y, OBJ_TOLERANCE);
      AssertTrue('right side towards -y', Normal(Item, Triangle).Y < 0);
    end;
  end;
end;

procedure TTestDrapeExport.TestMirroredCopyMirrored;
var
  Piece: TPieceObject;
  Objects: TObjObjectArray;
  Root: TJSONObject;
  Index, Triangle: integer;
begin
  Piece := Shape('Sleeve', [0, 100, 140, 0], [0, 0, 160, 200]);
  Piece.CutCount := 2;
  Piece.Mirrored := True;
  FPattern.Evaluate;
  FDrape.Place(DrapePieceCopy(FSource.Id, Piece.Key, 1), UprightPlacement(Vec3(-200, -200, 1000)));
  FDrape.Place(DrapePieceCopy(FSource.Id, Piece.Key, 2), MirroredPlacement(FDrape.Items[0].Placement));
  Objects := ParseObj(DrapePiecesOBJ(FDrape, BuildDrapeExport(FDrape, SPACING)));
  AssertEquals(2, Length(Objects));
  AssertEquals(Length(Objects[0].Vertices), Length(Objects[1].Vertices));
  for Index := 0 to High(Objects[0].Vertices) do
  begin
    AssertNear('mirrored', -Objects[0].Vertices[Index].X, Objects[1].Vertices[Index].X, OBJ_TOLERANCE);
    AssertNear('same height', Objects[0].Vertices[Index].Z, Objects[1].Vertices[Index].Z, OBJ_TOLERANCE);
  end;
  for Triangle := 0 to High(Objects[1].Triangles) do
    AssertTrue('turned round to face the right side', Normal(Objects[1], Triangle).Y < 0);
  Root := Scene(BuildDrapeExport(FDrape, SPACING));
  try
    AssertTrue('second mirrored', Root.Arrays['objects'].Objects[1].Get('mirrored', False));
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestDrapeExport.TestBody;
var
  Exported: TDrapeExport;
  Objects: TObjObjectArray;
begin
  Exported := BuildDrapeExport(FDrape, SPACING);
  AssertTrue('a body', Exported.HasBody);
  Objects := ParseObj(BodyOBJ(Exported.Body));
  AssertEquals(1, Length(Objects));
  AssertEquals('body', Objects[0].Name);
  AssertEquals(Length(Exported.Body.Vertices), Length(Objects[0].Vertices));
  AssertEquals(Length(Exported.Body.Triangles), Length(Objects[0].Triangles));
  AssertEquals(Exported.Body.Triangles[0].Second, Objects[0].Triangles[0][1]);
end;

procedure TTestDrapeExport.TestNoBody;
var
  Exported: TDrapeExport;
  Root: TJSONObject;
begin
  FDrape.Body.Kind := bkNone;
  Exported := BuildDrapeExport(FDrape, SPACING);
  AssertFalse('no body', Exported.HasBody);
  Root := Scene(Exported);
  try
    AssertNull('no body file', Root.Find('body'));
    AssertEquals('no objects', 0, Root.Arrays['objects'].Count);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestDrapeExport.TestUnplacedLeftOut;
var
  Front, Back: TPieceObject;
  Exported: TDrapeExport;
  Root: TJSONObject;
begin
  FrontAndBack(Front, Back);
  FDrape.Unplace(DrapePieceCopy(FSource.Id, Back.Key, 1));
  Exported := BuildDrapeExport(FDrape, SPACING);
  AssertEquals('the back is not placed', 1, Length(Exported.Problems));
  Root := Scene(Exported);
  try
    AssertEquals(1, Root.Arrays['objects'].Count);
    AssertEquals('nothing to sew', 0, Root.Arrays['seams'].Count);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TLineCatcher.Line(const Text: string);
begin
  Insert(Text, Lines, Length(Lines));
end;

procedure TTestDrapeExport.TestScriptFound;
var
  Script, Err: string;
  Index: integer;
begin
  AssertTrue('in data/blender', TAppPaths.BlenderScriptFile <> '');
  AssertTrue(Err, ReadTextFile(TAppPaths.BlenderScriptFile, Script, Err));
  // The script reads the files the export names, by the names it gives them
  AssertTrue('scene format', Pos('SCENE_FORMAT = "' + BLENDER_FORMAT + '"', Script) > 0);
  AssertTrue('scene version', Pos('SCENE_VERSION = ' + IntToStr(BLENDER_VERSION), Script) > 0);
  AssertTrue('script name', Pos('SCRIPT_SUFFIX = "' + BLENDER_SCRIPT_EXTENSION + '"', Script) > 0);
  AssertTrue('scene name', Pos('SCENE_SUFFIX = "' + BLENDER_EXTENSION + '"', Script) > 0);
  AssertTrue('frames', Pos('DEFAULT_FRAMES = ' + IntToStr(DEFAULT_DRAPE_FRAMES), Script) > 0);
  AssertTrue('Blender version', Pos('BLENDER_VERSION = (' + StringReplace(BLENDER_SCRIPT_VERSION, '.', ', ', []) + ')', Script) > 0);
  // Cloth settings for every fabric a material can take, and cotton for none
  for Index := 1 to High(FABRIC_NAMES) do
    AssertTrue('fabric ' + FABRIC_NAMES[Index], Pos('"' + FABRIC_NAMES[Index] + '": (', Script) > 0);
  AssertTrue('the default', Pos('DEFAULT_FABRIC = "' + FABRIC_NAMES[Ord(fbCotton)] + '"', Script) > 0);
end;

procedure TTestDrapeExport.TestBlenderParameters;
var
  Parameters: TStringArray;
begin
  Parameters := BlenderParameters('skirt.blender.py', 80);
  AssertEquals('in the background', '--background', Parameters[0]);
  AssertTrue('the script', string.Join(' ', Parameters).Contains('--python skirt.blender.py -- --frames 80'));
  AssertTrue('a failing script fails Blender', string.Join(' ', Parameters).Contains('--python-exit-code 1'));
end;

procedure TTestDrapeExport.TestBlenderProgress;
var
  Text: string;
  Frame, Total: integer;
begin
  AssertTrue(BlenderProgress('OpenSloper: frame 3 of 120', Text));
  AssertEquals('frame 3 of 120', Text);
  AssertFalse(BlenderProgress('Blender 5.2.2 LTS', Text));
  AssertTrue(BlenderFrame('frame 3 of 120', Frame, Total));
  AssertEquals(3, Frame);
  AssertEquals(120, Total);
  AssertFalse('not a frame', BlenderFrame('importing the pieces', Frame, Total));
end;

// A stand-in for Blender, a shell script, shows how lines and the exit code come back
procedure TTestDrapeExport.TestRunReadsLinesAndCode;
{$IFDEF UNIX}
var
  Fake, Err: string;
  Catcher: TLineCatcher;
  Outcome: TBlenderRun;
begin
  Fake := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-fake-blender-' + IntToStr(Random(MaxInt));
  AssertTrue(Err, WriteTextFile(Fake, '#!/bin/sh' + #10 + 'echo "Blender 5.2"' + #10 + 'echo "OpenSloper: frame 1 of 2"' + #10 +
    'echo "Traceback" >&2' + #10 + 'printf "last"' + #10 + 'exit 3' + #10, Err));
  Catcher := TLineCatcher.Create;
  try
    AssertEquals(0, FpChmod(Fake, &755));
    AssertTrue(Err, RunBlender(Fake, 'skirt.blender.py', 2, @Catcher.Line, nil, Outcome, Err));
    AssertEquals('code', 3, Outcome.ExitCode);
    AssertEquals('every line, the last without an end', 4, Length(Catcher.Lines));
    AssertEquals('OpenSloper: frame 1 of 2', Catcher.Lines[1]);
    AssertEquals('the rest kept to show', 3, Length(Outcome.Tail));
    AssertEquals('last', Outcome.Tail[2]);
  finally
    FreeAndNil(Catcher);
    DeleteFile(Fake);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

// The window's Cancel ends a Blender that would run on
procedure TTestDrapeExport.TestRunStops;
{$IFDEF UNIX}
var
  Fake, Err: string;
  Outcome: TBlenderRun;
  Stop: boolean;
  Started: QWord;
begin
  Fake := IncludeTrailingPathDelimiter(GetTempDir) + 'sloper-slow-blender-' + IntToStr(Random(MaxInt));
  AssertTrue(Err, WriteTextFile(Fake, '#!/bin/sh' + #10 + 'sleep 30' + #10, Err));
  try
    AssertEquals(0, FpChmod(Fake, &755));
    Stop := True;
    Started := GetTickCount64;
    AssertTrue(Err, RunBlender(Fake, 'skirt.blender.py', 2, nil, @Stop, Outcome, Err));
    AssertTrue('stopped', Outcome.Stopped);
    AssertTrue('at once', GetTickCount64 - Started < 5000);
  finally
    DeleteFile(Fake);
  end;
end;
{$ELSE}
begin
end;
{$ENDIF}

initialization
  RegisterTest(TTestDrapeExport);
end.
