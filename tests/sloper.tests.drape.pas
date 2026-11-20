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

// The drape app's core: 3D geometry, a piece's frame and anchor, placements,
// mirrored copies and the camera.
unit Sloper.Tests.Drape;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.PatternSources, Sloper.Core.DrapePlacement, Sloper.Core.DrapeFile;

type
  TTestGeometry3 = class(TOSTestCase)
  private
    procedure AssertVecNear(const Msg: string; const Expected, Actual: TVec3; Tolerance: double = DEFAULT_TOLERANCE);
  published
    procedure TestTurnsFollowBlender;
    procedure TestEulerOrderIsXYZ;
    procedure TestEulerRoundTrip;
    procedure TestEulerGimbalLock;
  end;

  TTestDrapePlacement = class(TOSTestCase)
  private
    FPattern: TPattern;
    procedure AssertVecNear(const Msg: string; const Expected, Actual: TVec3; Tolerance: double = DEFAULT_TOLERANCE);
    function Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
    function EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAnchorIsGrainlineMiddle;
    procedure TestAnchorWithoutGrainline;
    procedure TestUprightPieceFacesViewer;
    procedure TestTurnedPiece;
    procedure TestNormal;
    procedure TestMirroredCopyIsMirrorImage;
    procedure TestFoldOpensOut;
    procedure TestFrontCamera;
    procedure TestSideAndTopCameras;
    procedure TestDragFollowsScreen;
    procedure TestPerspectiveShrinksFarPoints;
    procedure TestAlignedPlacementBesideItsPartner;
  end;

  // A front and a back joined by a side seam, in a drape file
  TTestDrapeFile = class(TOSTestCase)
  private
    FDrape: TDrape;
    FPattern: TPattern;
    FSource: TPatternSource;
    FFront, FBack: TPieceObject;
    FSideSeam: TSeamObject;
    function Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
    function EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
    function Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
    function FrontCopy: TDrapePieceCopy;
    function BackCopy(Copy: integer = 1): TDrapePieceCopy;
    // The extent of a placed copy's outline
    procedure PlacedExtent(const Copy: TDrapePieceCopy; out Low, High: TVec3);
    procedure AssertVecNear3(const Msg: string; const Expected, Actual: TVec3);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSaveAndLoad;
    procedure TestRefusesBadFiles;
    procedure TestUnplacedAndPlace;
    procedure TestRemoveSourceDropsPlacements;
    procedure TestAlignToSeamFlat;
    procedure TestAlignToSeamFolded;
    procedure TestGuessPlacesEverything;
    procedure TestGuessMirrorsPair;
    procedure TestProblems;
  end;

implementation

uses
  Math;

const
  // Arbitrary turns that test every axis
  SAMPLE_TURNS: array[0..4, 0..2] of double = ((0, 0, 0), (30, 0, 0), (10, 20, 30), (-75, 40, 160), (170, -60, -100));

  { TTestGeometry3 }

procedure TTestGeometry3.AssertVecNear(const Msg: string; const Expected, Actual: TVec3; Tolerance: double);
begin
  if not PointsNear3(Expected, Actual, Tolerance) then
    Fail(Format('%s: expected (%.4f, %.4f, %.4f) but was (%.4f, %.4f, %.4f)', [Msg, Expected.X, Expected.Y, Expected.Z, Actual.X,
      Actual.Y, Actual.Z]));
end;

procedure TTestGeometry3.TestTurnsFollowBlender;
begin
  // Anticlockwise looking down each axis: right-handed
  AssertVecNear('Z turns X to Y', Vec3(0, 1, 0), Mat3TurnZ(90).Apply(Vec3(1, 0, 0)));
  AssertVecNear('X turns Y to Z', Vec3(0, 0, 1), Mat3TurnX(90).Apply(Vec3(0, 1, 0)));
  AssertVecNear('Y turns Z to X', Vec3(1, 0, 0), Mat3TurnY(90).Apply(Vec3(0, 0, 1)));
end;

procedure TTestGeometry3.TestEulerOrderIsXYZ;
var
  Turned: TVec3;
begin
  // X first: Y goes to Z, then Z about Y goes to X, then Z leaves X alone
  Turned := EulerToMat3(Vec3(90, 90, 0)).Apply(Vec3(0, 1, 0));
  AssertVecNear('X then Y', Vec3(1, 0, 0), Turned);
  Turned := EulerToMat3(Vec3(90, 0, 90)).Apply(Vec3(0, 1, 0));
  AssertVecNear('X then Z', Vec3(0, 0, 1), Turned);
  Turned := EulerToMat3(Vec3(0, 90, 90)).Apply(Vec3(0, 0, 1));
  AssertVecNear('Y then Z', Vec3(0, 1, 0), Turned);
end;

procedure TTestGeometry3.TestEulerRoundTrip;
var
  Index, Row, Col: integer;
  Angles, Back: TVec3;
  Original, Again: TMat3;
begin
  for Index := 0 to High(SAMPLE_TURNS) do
  begin
    Angles := Vec3(SAMPLE_TURNS[Index, 0], SAMPLE_TURNS[Index, 1], SAMPLE_TURNS[Index, 2]);
    Original := EulerToMat3(Angles);
    Back := Mat3ToEuler(Original);
    Again := EulerToMat3(Back);
    for Row := 0 to 2 do
      for Col := 0 to 2 do
        AssertNear(Format('turn %d at %d,%d', [Index, Row, Col]), Original.M[Row, Col], Again.M[Row, Col], 1e-9);
    if Abs(Angles.Y) < 90 then
      AssertVecNear(Format('angles %d', [Index]), Angles, Back, 1e-6);
  end;
end;

procedure TTestGeometry3.TestEulerGimbalLock;
var
  Original, Again: TMat3;
  Row, Col: integer;
begin
  Original := EulerToMat3(Vec3(25, 90, 40));
  Again := EulerToMat3(Mat3ToEuler(Original));
  for Row := 0 to 2 do
    for Col := 0 to 2 do
      AssertNear(Format('at %d,%d', [Row, Col]), Original.M[Row, Col], Again.M[Row, Col], 1e-9);
end;

{ TTestDrapePlacement }

procedure TTestDrapePlacement.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestDrapePlacement.TearDown;
begin
  FreeAndNil(FPattern);
end;

procedure TTestDrapePlacement.AssertVecNear(const Msg: string; const Expected, Actual: TVec3; Tolerance: double);
begin
  if not PointsNear3(Expected, Actual, Tolerance) then
    Fail(Format('%s: expected (%.4f, %.4f, %.4f) but was (%.4f, %.4f, %.4f)', [Msg, Expected.X, Expected.Y, Expected.Z, Actual.X,
      Actual.Y, Actual.Z]));
end;

function TTestDrapePlacement.Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
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

function TTestDrapePlacement.EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
var
  Index: integer;
  Edge: TEdgeObject;
  Start, Finish: TVec2;
begin
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Piece.Path[Index].EdgeKey));
    Start := Edge.PointAtLength(0);
    Finish := Edge.PointAtLength(Edge.Length);
    if (PointsNear(Start, A) and PointsNear(Finish, B)) or (PointsNear(Start, B) and PointsNear(Finish, A)) then
      Exit(Edge.Key);
  end;
  Fail('No edge');
  Result := '';
end;

procedure TTestDrapePlacement.TestAnchorIsGrainlineMiddle;
var
  Piece: TPieceObject;
begin
  // The default grainline runs up through the middle of the extent
  Piece := Shape('Front', [0, 100, 100, 0], [0, 0, 300, 300]);
  AssertPointsNear('anchor', Piece.Grainline.PointAt(0.5), PieceAnchor(Piece));
  AssertNear('anchor x', 50, PieceAnchor(Piece).X, 1e-6);
end;

procedure TTestDrapePlacement.TestAnchorWithoutGrainline;
var
  Piece: TPieceObject;
begin
  Piece := Shape('Front', [0, 120, 120, 0], [10, 10, 50, 90]);
  Piece.SetGrainKind(gkNone);
  FPattern.Evaluate;
  AssertPointsNear('extent middle', Vec2(60, 50), PieceAnchor(Piece));
end;

procedure TTestDrapePlacement.TestUprightPieceFacesViewer;
var
  Placement: TDrapePlacement;
  Anchor: TVec2;
begin
  Anchor := Vec2(50, 100);
  Placement := UprightPlacement(Vec3(0, -200, 1200));
  AssertVecNear('anchor', Vec3(0, -200, 1200), PlacePoint(Anchor, Anchor, False, Placement));
  // Right on the canvas is X; down on the canvas is down
  AssertVecNear('right and down', Vec3(10, -200, 1180), PlacePoint(Vec2(60, 120), Anchor, False, Placement));
  AssertVecNear('mirrored', Vec3(-10, -200, 1180), PlacePoint(Vec2(60, 120), Anchor, True, Placement));
end;

procedure TTestDrapePlacement.TestTurnedPiece;
var
  Placement: TDrapePlacement;
  Points: TVec3Array;
begin
  // A quarter turn about Z puts the piece on the body's left, facing out
  Placement.Position := Vec3(200, 0, 1000);
  Placement.Rotation := Vec3(0, 0, 90);
  Points := PlacePoints([Vec2(0, 0), Vec2(10, 0), Vec2(0, 10)], Vec2(0, 0), False, Placement);
  AssertVecNear('anchor', Vec3(200, 0, 1000), Points[0]);
  AssertVecNear('across goes back', Vec3(200, 10, 1000), Points[1]);
  AssertVecNear('down stays down', Vec3(200, 0, 990), Points[2]);
  AssertVecNear('faces out', Vec3(1, 0, 0), PlacedNormal(Placement));
end;

procedure TTestDrapePlacement.TestNormal;
var
  Placement: TDrapePlacement;
begin
  Placement := UprightPlacement(Vec3(0, 0, 0));
  AssertVecNear('front faces viewer', Vec3(0, -1, 0), PlacedNormal(Placement));
  Placement.Rotation := Vec3(0, 0, 180);
  AssertVecNear('back faces away', Vec3(0, 1, 0), PlacedNormal(Placement));
end;

procedure TTestDrapePlacement.TestMirroredCopyIsMirrorImage;
var
  Placement, Other: TDrapePlacement;
  Index: integer;
  Anchor, Point: TVec2;
  Original, Copied: TVec3;
begin
  Anchor := Vec2(40, 60);
  Point := Vec2(95, -30);
  for Index := 0 to High(SAMPLE_TURNS) do
  begin
    Placement.Position := Vec3(120, -80, 900);
    Placement.Rotation := Vec3(SAMPLE_TURNS[Index, 0], SAMPLE_TURNS[Index, 1], SAMPLE_TURNS[Index, 2]);
    Other := MirroredPlacement(Placement);
    Original := PlacePoint(Point, Anchor, False, Placement);
    Copied := PlacePoint(Point, Anchor, True, Other);
    AssertVecNear(Format('turn %d', [Index]), Vec3(-Original.X, Original.Y, Original.Z), Copied, 1e-6);
  end;
end;

procedure TTestDrapePlacement.TestFoldOpensOut;
var
  Piece: TPieceObject;
  Whole: TVec2Array;
  Point: TVec2;
begin
  Piece := Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, EdgeBetween(Piece, Vec2(0, 0), Vec2(0, 200))));
  FPattern.Evaluate;
  Whole := PlacedSeamLine(Piece);
  AssertEquals('points', 6, Length(Whole));
  AssertNear('area doubles', 2 * Abs(SignedArea(Piece.Outline)), Abs(SignedArea(Whole)), 1e-6);
  for Point in Whole do
    AssertTrue('within the opened extent', (Point.X >= -100 - 1e-6) and (Point.X <= 100 + 1e-6));
  // Not on a fold: the seam line as it is
  FPattern.SetFoldEdge(Piece, '');
  FPattern.Evaluate;
  AssertEquals('unfolded', Length(Piece.Outline), Length(PlacedSeamLine(Piece)));
end;

procedure TTestDrapePlacement.TestFrontCamera;
var
  Camera: TDrapeCamera;
  Screen: TVec2;
  Depth, Nearer: double;
begin
  Camera := DefaultDrapeCamera;
  Camera.Target := Vec3(0, 0, 1000);
  Camera.Scale := 2;
  AssertTrue('visible', Camera.Project(Vec3(10, 0, 1020), Screen, Depth));
  AssertPointsNear('left of the body is right on screen, up is up', Vec2(20, -40), Screen);
  Camera.Project(Vec3(0, -100, 1000), Screen, Nearer);
  AssertTrue('front is nearer', Nearer < Depth);
end;

procedure TTestDrapePlacement.TestSideAndTopCameras;
var
  Camera: TDrapeCamera;
  Screen: TVec2;
  Depth: double;
begin
  Camera := DefaultDrapeCamera;
  Camera.Target := Vec3(0, 0, 0);
  Camera.Scale := 1;
  // From the body's left side its front is on the left of the screen
  Camera := CameraForView(Camera, tvLeft);
  Camera.Project(Vec3(0, -50, 0), Screen, Depth);
  AssertPointsNear('left view', Vec2(-50, 0), Screen);
  Camera := CameraForView(Camera, tvBack);
  Camera.Project(Vec3(30, 0, 0), Screen, Depth);
  AssertPointsNear('back view', Vec2(-30, 0), Screen);
  // From above the front is at the bottom of the screen
  Camera := CameraForView(Camera, tvTop);
  Camera.Project(Vec3(0, -50, 0), Screen, Depth);
  AssertPointsNear('top view', Vec2(0, 50), Screen);
  Camera.Project(Vec3(0, 0, 100), Screen, Depth);
  AssertTrue('top is nearest from above', Depth < 0);
end;

procedure TTestDrapePlacement.TestDragFollowsScreen;
var
  Camera: TDrapeCamera;
  Moved: TVec3;
  Screen, Before: TVec2;
  Depth: double;
begin
  Camera := DefaultDrapeCamera;
  Camera := CameraForView(Camera, tvThreeQuarter);
  Camera.Project(Vec3(40, -30, 900), Before, Depth);
  Moved := Vec3(40, -30, 900) + Camera.ScreenToWorld(Vec2(25, -12));
  Camera.Project(Moved, Screen, Depth);
  AssertPointsNear('follows the pointer', Before + Vec2(25, -12), Screen, 1e-6);
end;

procedure TTestDrapePlacement.TestPerspectiveShrinksFarPoints;
var
  Camera: TDrapeCamera;
  Near, Far: TVec2;
  Depth: double;
begin
  Camera := DefaultDrapeCamera;
  Camera.Perspective := True;
  Camera.Project(Camera.Target + Vec3(100, -200, 0), Near, Depth);
  Camera.Project(Camera.Target + Vec3(100, 200, 0), Far, Depth);
  AssertTrue('far is smaller', Abs(Far.X) < Abs(Near.X));
  AssertFalse('behind the camera', Camera.Project(Camera.Target - Camera.Forward * (Camera.Distance + 1), Near, Depth));
end;

procedure TTestDrapePlacement.TestAlignedPlacementBesideItsPartner;
var
  Partner, Placement: TDrapePlacement;
  Anchor: TVec2;
begin
  // A 100 mm square upright at the origin; its right edge, top to bottom
  Anchor := Vec2(50, 50);
  Partner := UprightPlacement(Vec3(0, 0, 0));
  // Another square's left edge, top to bottom, goes beside it, 20 mm across
  Placement := AlignedPlacement(PlacePoint(Vec2(100, 0), Anchor, False, Partner), PlacePoint(Vec2(100, 100), Anchor, False, Partner),
    Vec3(0, 0, 0), PlacedNormal(Partner), Vec2(0, 0), Vec2(0, 100), Anchor, Anchor, False, 20, False);
  AssertVecNear('beside', Vec3(120, 0, 0), Placement.Position, 1e-6);
  AssertVecNear('not turned', Vec3(0, 0, 0), Placement.Rotation, 1e-6);
  // Folded over, it lies on its partner, facing the other way, 20 mm off it
  Placement := AlignedPlacement(PlacePoint(Vec2(100, 0), Anchor, False, Partner), PlacePoint(Vec2(100, 100), Anchor, False, Partner),
    Vec3(0, 0, 0), PlacedNormal(Partner), Vec2(0, 0), Vec2(0, 100), Anchor, Anchor, False, 20, True);
  AssertVecNear('over it', Vec3(0, 20, 0), Placement.Position, 1e-6);
  AssertVecNear('faces back', Vec3(0, 1, 0), PlacedNormal(Placement), 1e-6);
end;

{ TTestDrapeFile }

procedure TTestDrapeFile.SetUp;
begin
  FDrape := TDrape.Create;
  FSource := FDrape.AddSource('dress.sloper', '', '');
  FPattern := TPattern.Create;
  FSource.Pattern := FPattern;
  // Clockwise, as drafted: the side seam runs down both edges
  FFront := Shape('Front', [0, 120, 120, 0], [0, 0, 200, 200]);
  FBack := Shape('Back', [200, 300, 300, 200], [0, 0, 200, 200]);
  FSideSeam := FPattern.AddSeam('Side', Side(FFront, EdgeBetween(FFront, Vec2(120, 0), Vec2(120, 200))),
    Side(FBack, EdgeBetween(FBack, Vec2(200, 0), Vec2(200, 200))));
  AssertNotNull(FPattern.LastError, FSideSeam);
  FPattern.Evaluate;
end;

procedure TTestDrapeFile.TearDown;
begin
  // The source owns the pattern
  FreeAndNil(FDrape);
end;

function TTestDrapeFile.Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
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

function TTestDrapeFile.EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
var
  Index: integer;
  Edge: TEdgeObject;
  Start, Finish: TVec2;
begin
  for Index := 0 to High(Piece.Path) do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Piece.Path[Index].EdgeKey));
    Start := Edge.PointAtLength(0);
    Finish := Edge.PointAtLength(Edge.Length);
    if (PointsNear(Start, A) and PointsNear(Finish, B)) or (PointsNear(Start, B) and PointsNear(Finish, A)) then
      Exit(Edge.Key);
  end;
  Fail('No edge');
  Result := '';
end;

function TTestDrapeFile.Side(Piece: TPieceObject; const EdgeKey: string): TSeamSide;
begin
  Result := nil;
  SetLength(Result, 1);
  Result[0].PieceKey := Piece.Key;
  Result[0].EdgeKey := EdgeKey;
end;

function TTestDrapeFile.FrontCopy: TDrapePieceCopy;
begin
  Result := DrapePieceCopy(FSource.Id, FFront.Key, 1);
end;

function TTestDrapeFile.BackCopy(Copy: integer): TDrapePieceCopy;
begin
  Result := DrapePieceCopy(FSource.Id, FBack.Key, Copy);
end;

procedure TTestDrapeFile.PlacedExtent(const Copy: TDrapePieceCopy; out Low, High: TVec3);
var
  Points: TVec3Array;
  Point: TVec3;
begin
  AssertTrue('placed', FDrape.PlacedOutline(Copy, Points));
  Low := Points[0];
  High := Points[0];
  for Point in Points do
  begin
    Low := Vec3(Min(Low.X, Point.X), Min(Low.Y, Point.Y), Min(Low.Z, Point.Z));
    High := Vec3(Max(High.X, Point.X), Max(High.Y, Point.Y), Max(High.Z, Point.Z));
  end;
end;

procedure TTestDrapeFile.AssertVecNear3(const Msg: string; const Expected, Actual: TVec3);
begin
  if not PointsNear3(Expected, Actual, 1e-6) then
    Fail(Format('%s: expected (%.4f, %.4f, %.4f) but was (%.4f, %.4f, %.4f)', [Msg, Expected.X, Expected.Y, Expected.Z, Actual.X,
      Actual.Y, Actual.Z]));
end;

procedure TTestDrapeFile.TestSaveAndLoad;
var
  Loaded: TDrape;
  Placement: TDrapePlacement;
  Text, Err: string;
begin
  FDrape.Name := 'Dress';
  FDrape.Body.Size := '38';
  FDrape.Gap := 15;
  Placement.Position := Vec3(10.5, -170, 1100);
  Placement.Rotation := Vec3(5, -10, 90);
  FDrape.Place(BackCopy, Placement);
  Text := FDrape.SaveToText;
  Loaded := TDrape.Create;
  try
    AssertTrue(Err, Loaded.LoadFromText(Text, Err));
    AssertEquals('name', 'Dress', Loaded.Name);
    AssertEquals('sources', 1, Loaded.Sources.Count);
    AssertEquals('pattern', 'dress.sloper', Loaded.Sources[0].PatternFile);
    AssertEquals('size', '38', Loaded.Body.Size);
    AssertTrue('body', Loaded.Body.Kind = bkMeasurements);
    AssertNear('gap', 15, Loaded.Gap);
    AssertEquals('placements', 1, Length(Loaded.Items));
    AssertEquals('piece', FBack.Key, Loaded.Items[0].Piece.PieceKey);
    AssertEquals('copy', 1, Loaded.Items[0].Piece.Copy);
    AssertNear('position', 10.5, Loaded.Items[0].Placement.Position.X);
    AssertNear('rotation', 90, Loaded.Items[0].Placement.Rotation.Z);
    AssertEquals('the same again', Text, Loaded.SaveToText);
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestDrapeFile.TestRefusesBadFiles;

  procedure Refused(const Msg, Text, Expected: string);
  var
    Loaded: TDrape;
    Err: string;
  begin
    Loaded := TDrape.Create;
    try
      AssertFalse(Msg, Loaded.LoadFromText(Text, Err));
      AssertEquals(Msg, Expected, Err);
      AssertEquals(Msg + ' cleared', 0, Loaded.Sources.Count);
    finally
      FreeAndNil(Loaded);
    end;
  end;

const
  HEAD = '{"format": "drape", "version": 1, "sources": [{"id": 1, "pattern": "a"}], ';
begin
  Refused('format', '{"format": "layout", "version": 1, "sources": []}', rsDrapeWrongFormat);
  Refused('sources', '{"format": "drape", "version": 1}', rsPatternSourcesList);
  Refused('body', HEAD + '"body": {"kind": "statue"}}', rsDrapeBadBody);
  Refused('gap', HEAD + '"gap": -1}', rsDrapeBadGap);
  Refused('position', HEAD + '"placements": [{"source": 1, "piece": 3, "position": [0, 0], "rotation": [0, 0, 0]}]}',
    Format(rsDrapeBadPlacement, [1]));
  Refused('source', HEAD + '"placements": [{"source": 2, "piece": 3, "position": [0, 0, 0], "rotation": [0, 0, 0]}]}',
    Format(rsDrapeUnknownSource, [1, 2]));
  Refused('repeated', HEAD + '"placements": [{"source": 1, "piece": 3, "position": [0, 0, 0], "rotation": [0, 0, 0]}, ' +
    '{"source": 1, "piece": 3, "copy": 1, "position": [1, 0, 0], "rotation": [0, 0, 0]}]}', Format(rsDrapeRepeatedPlacement, [2]));
end;

procedure TTestDrapeFile.TestUnplacedAndPlace;
begin
  AssertEquals('all unplaced', 2, Length(FDrape.Unplaced));
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, 0, 0)));
  AssertEquals('one left', 1, Length(FDrape.Unplaced));
  AssertEquals('index', 0, FDrape.IndexOf(FrontCopy));
  // Placing again moves it
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(5, 0, 0)));
  AssertEquals('still one item', 1, Length(FDrape.Items));
  AssertNear('moved', 5, FDrape.Items[0].Placement.Position.X);
  FDrape.Unplace(FrontCopy);
  AssertEquals('unplaced again', 2, Length(FDrape.Unplaced));
end;

procedure TTestDrapeFile.TestRemoveSourceDropsPlacements;
begin
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, 0, 0)));
  FDrape.RemoveSource(FSource);
  FSource := nil;
  AssertEquals('placements gone', 0, Length(FDrape.Items));
  AssertEquals('source gone', 0, FDrape.Sources.Count);
end;

procedure TTestDrapeFile.TestAlignToSeamFlat;
var
  Placement: TDrapePlacement;
  FrontLow, FrontHigh, BackLow, BackHigh: TVec3;
begin
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, -170, 1100)));
  AssertTrue('aligned', FDrape.AlignToSeam(BackCopy, FSideSeam, False, Placement));
  FDrape.Place(BackCopy, Placement);
  PlacedExtent(FrontCopy, FrontLow, FrontHigh);
  PlacedExtent(BackCopy, BackLow, BackHigh);
  AssertNear('beside, the gap across', FrontHigh.X + FDrape.Gap, BackLow.X, 1e-6);
  AssertNear('same plane', FrontLow.Y, BackLow.Y, 1e-6);
  AssertNear('flat', BackLow.Y, BackHigh.Y, 1e-6);
  AssertNear('tops level', FrontHigh.Z, BackHigh.Z, 1e-6);
  AssertVecNear3('same facing', Vec3(0, -1, 0), PlacedNormal(Placement));
end;

procedure TTestDrapeFile.TestAlignToSeamFolded;
var
  Placement: TDrapePlacement;
  FrontLow, FrontHigh, BackLow, BackHigh: TVec3;
begin
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, -170, 1100)));
  AssertTrue('aligned', FDrape.AlignToSeam(BackCopy, FSideSeam, True, Placement));
  FDrape.Place(BackCopy, Placement);
  PlacedExtent(FrontCopy, FrontLow, FrontHigh);
  PlacedExtent(BackCopy, BackLow, BackHigh);
  AssertNear('folded back over', FrontHigh.X, BackHigh.X, 1e-6);
  AssertNear('behind, the gap away', FrontLow.Y + FDrape.Gap, BackLow.Y, 1e-6);
  AssertVecNear3('faces back', Vec3(0, 1, 0), PlacedNormal(Placement));
end;

procedure TTestDrapeFile.TestGuessPlacesEverything;
var
  FrontLow, FrontHigh, BackLow, BackHigh: TVec3;
begin
  AssertEquals('placed', 2, FDrape.GuessPlacements);
  AssertEquals('none left', 0, Length(FDrape.Unplaced));
  // The front is the larger piece, so it goes first, in front of the body
  PlacedExtent(FrontCopy, FrontLow, FrontHigh);
  PlacedExtent(BackCopy, BackLow, BackHigh);
  AssertNear('front centred', 0, (FrontLow.X + FrontHigh.X) / 2, 1e-6);
  AssertTrue('in front of the body', FrontLow.Y < 0);
  AssertNear('back sewn beside it', FrontHigh.X + FDrape.Gap, BackLow.X, 1e-6);
  AssertEquals('nothing more to guess', 0, FDrape.GuessPlacements);
end;

procedure TTestDrapeFile.TestGuessMirrorsPair;
var
  Low, High, OtherLow, OtherHigh: TVec3;
begin
  AssertTrue(FPattern.LastError, FPattern.SetCut(FBack, 2, True));
  FPattern.Evaluate;
  AssertEquals('placed', 3, FDrape.GuessPlacements);
  PlacedExtent(BackCopy(1), Low, High);
  PlacedExtent(BackCopy(2), OtherLow, OtherHigh);
  AssertNear('mirror image', -High.X, OtherLow.X, 1e-6);
  AssertNear('mirror image far side', -Low.X, OtherHigh.X, 1e-6);
end;

procedure TTestDrapeFile.TestProblems;
var
  Problems: TDrapeProblemArray;
begin
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, 0, 0)));
  FDrape.Place(DrapePieceCopy(FSource.Id, '9999', 1), UprightPlacement(Vec3(0, 0, 0)));
  Problems := FDrape.Problems;
  AssertEquals('gone and unplaced', 2, Length(Problems));
  AssertEquals('gone', Format(rsDrapePieceGone, ['dress.sloper', '9999']), Problems[0].Text);
  AssertEquals('gone item', 1, Problems[0].Item);
  AssertEquals('unplaced', Format(rsDrapeUnplaced, ['dress.sloper', 'Back', 1, 1]), Problems[1].Text);
end;

initialization
  RegisterTest(TTestGeometry3);
  RegisterTest(TTestDrapePlacement);
  RegisterTest(TTestDrapeFile);
end.
