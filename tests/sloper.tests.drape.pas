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
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.DrapePlacement;

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
  end;

implementation

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

initialization
  RegisterTest(TTestGeometry3);
  RegisterTest(TTestDrapePlacement);
end.
