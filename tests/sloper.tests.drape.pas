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
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.PatternSources, Sloper.Core.DrapePlacement,
  Sloper.Core.DrapeFile, Sloper.Core.Measurements,
  Sloper.Core.BodyForm, Sloper.Core.DrapeScene, Sloper.Document.DrapeDocument, Sloper.Core.Mesher;

type
  TTestGeometry3 = class(TOSTestCase)
  private
    procedure AssertVecNear(const Msg: string; const Expected, Actual: TVec3; Tolerance: double = DEFAULT_TOLERANCE);
  published
    procedure TestTurnsFollowBlender;
    procedure TestEulerOrderIsXYZ;
    procedure TestEulerRoundTrip;
    procedure TestEulerGimbalLock;
    procedure TestTurnAboutAxis;
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
    procedure TestMeshPieceOnFold;
    procedure TestFrontCamera;
    procedure TestSideAndTopCameras;
    procedure TestDragFollowsScreen;
    procedure TestPerspectiveShrinksFarPoints;
    procedure TestAlignedPlacementBesideItsPartner;
    procedure TestTurnedPlacementKeepsAnchor;
    procedure TestRoundBodyKeepsFacingOut;
    procedure TestSnappedAngle;
  end;

  TTestBodyForm = class(TOSTestCase)
  private
    function SampleSet: TMeasurementSet;
  published
    procedure TestDefaultFormIsWhole;
    procedure TestTakesMeasurements;
    procedure TestRingsMatchCircumferences;
    procedure TestRingsGoUp;
    procedure TestMeshIsClosedAndFacesOut;
    procedure TestFigureStandsFacingForwards;
    procedure TestHeadIsPlain;
    procedure TestSizeOfATable;
    procedure TestBackLengthPlacesTheWaist;
    procedure TestFigureWithoutArms;
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
    procedure TestGuessUsesTheBody;
    procedure TestMissingBodyFile;
    procedure TestSceneBackToFront;
    procedure TestScenePicksPieces;
    procedure TestSceneWrongSide;
    procedure TestAlignableSeams;
    procedure TestSeamLinks;
    procedure TestSceneWithoutBody;
    procedure TestAttachEdges;
    procedure TestAttachedEdgeGone;
  end;

  TTestDrapeDocument = class(TOSTestCase)
  published
    procedure TestUndoAndRedo;
    procedure TestCancelRestores;
    procedure TestSkirtFrontDrawnOverForm;
  end;

implementation

uses
  Classes, Math;

function PolylineLength3(const Points: TVec3Array): double;
var
  Index: integer;
begin
  Result := 0;
  for Index := 0 to High(Points) do
    Result := Result + Distance3(Points[Index], Points[(Index + 1) mod Length(Points)]);
end;

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

procedure TTestGeometry3.TestTurnAboutAxis;
var
  Index: integer;
  Turn, Expected: TMat3;
  Row, Col: integer;
begin
  for Index := -2 to 2 do
  begin
    Turn := Mat3TurnAbout(Vec3(0, 0, 5), Index * 40);
    Expected := Mat3TurnZ(Index * 40);
    for Row := 0 to 2 do
      for Col := 0 to 2 do
        AssertNear('about Z', Expected.M[Row, Col], Turn.M[Row, Col], 1e-12);
  end;
  AssertVecNear('about the diagonal, a third turn', Vec3(0, 1, 0), Mat3TurnAbout(Vec3(1, 1, 1), 120).Apply(Vec3(1, 0, 0)), 1e-9);
  AssertVecNear('no axis', Vec3(1, 2, 3), Mat3TurnAbout(Vec3(0, 0, 0), 30).Apply(Vec3(1, 2, 3)));
end;

{ TTestDrapePlacement }

procedure TTestDrapePlacement.TestTurnedPlacementKeepsAnchor;
var
  Placement, Turned: TDrapePlacement;
begin
  Placement := UprightPlacement(Vec3(100, -200, 900));
  Turned := TurnedPlacement(Placement, Vec3(0, 0, 1), 90);
  AssertVecNear('anchor stays', Placement.Position, Turned.Position);
  AssertVecNear('faces the body''s left', Vec3(1, 0, 0), PlacedNormal(Turned), 1e-9);
  // Turning about the view's right tips it back
  Turned := TurnedPlacement(Placement, Vec3(1, 0, 0), 30);
  AssertNear('tipped', 30, Turned.Rotation.X, 1e-9);
end;

procedure TTestDrapePlacement.TestRoundBodyKeepsFacingOut;
var
  Placement, Moved: TDrapePlacement;
begin
  Placement := UprightPlacement(Vec3(0, -200, 900));
  Moved := RoundBodyPlacement(Placement, 90);
  AssertVecNear('to the body''s left', Vec3(200, 0, 900), Moved.Position, 1e-9);
  AssertVecNear('facing out', Vec3(1, 0, 0), PlacedNormal(Moved), 1e-9);
  Moved := RoundBodyPlacement(Placement, 180);
  AssertVecNear('behind', Vec3(0, 200, 900), Moved.Position, 1e-9);
  AssertVecNear('facing the back', Vec3(0, 1, 0), PlacedNormal(Moved), 1e-9);
end;

procedure TTestDrapePlacement.TestSnappedAngle;
begin
  AssertNear('down', 30, SnappedAngle(37, 15));
  AssertNear('up', 45, SnappedAngle(38, 15));
  AssertNear('negative', -15, SnappedAngle(-16, 15));
  AssertNear('no step', 37, SnappedAngle(37, 0));
end;

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

procedure TTestDrapePlacement.TestMeshPieceOnFold;
var
  Piece: TPieceObject;
  Mesh: TFlatMesh;
begin
  Piece := Shape('Front', [0, 100, 100, 0], [0, 0, 200, 200]);
  AssertNear('flat', Abs(SignedArea(Piece.Outline)), MeshArea(MeshPiece(Piece)), 1e-6);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, EdgeBetween(Piece, Vec2(0, 0), Vec2(0, 200))));
  FPattern.Evaluate;
  Mesh := MeshPiece(Piece);
  AssertNear('opened out', 2 * Abs(SignedArea(Piece.Outline)), MeshArea(Mesh), 1e-6);
  AssertTrue('inner points', Length(Mesh.Points) > Mesh.BoundaryCount);
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

{ TTestBodyForm }

function TTestBodyForm.SampleSet: TMeasurementSet;
begin
  Result := TMeasurementSet.Create;
  Result.Add('height', 1700);
  Result.Add('bust_circumference', 920);
  Result.Add('waist_circumference', 740);
  Result.Add('hip_circumference', 1000);
  Result.Add('height_waist', 1060);
  Result.Add('neck_circumference', 370);
end;

// A set with the back length but no heights, as a bodice block's often has,
// puts the waist that far below the neck
procedure TTestBodyForm.TestBackLengthPlacesTheWaist;
var
  BodySet: TMeasurementSet;
  Measures: TBodyMeasures;
begin
  BodySet := TMeasurementSet.Create;
  try
    BodySet.Add('height', 1700);
    BodySet.Add('neck_back_to_waist', 410);
    Measures := BodyMeasuresFrom(BodySet);
    AssertNear('the neck by its share', 1700 * 0.845, Measures.NeckHeight);
    AssertNear('the waist below it', 1700 * 0.845 - 410, Measures.WaistHeight);
    BodySet.Add('height_back_neck', 1450);
    AssertNear('below the measured neck', 1040, BodyMeasuresFrom(BodySet).WaistHeight);
    BodySet.Add('height_waist', 1060);
    Measures := BodyMeasuresFrom(BodySet);
    AssertNear('both measured: the waist as measured', 1060, Measures.WaistHeight);
    AssertNear('and the neck', 1450, Measures.NeckHeight);
  finally
    FreeAndNil(BodySet);
  end;
  BodySet := SampleSet;
  try
    BodySet.Add('neck_back_to_waist', 420);
    AssertNear('the neck above the measured waist', 1480, BodyMeasuresFrom(BodySet).NeckHeight);
  finally
    FreeAndNil(BodySet);
  end;
end;

procedure TTestBodyForm.TestDefaultFormIsWhole;
var
  Measures: TBodyMeasures;
begin
  Measures := DefaultBodyMeasures;
  AssertTrue('height', Measures.Height > 0);
  AssertTrue('all estimated', Length(Measures.Estimated) > 10);
  AssertTrue('waist below bust', Measures.WaistHeight < Measures.BustHeight);
  AssertTrue('mesh', Length(BuildBodyForm(Measures).Triangles) > 0);
end;

procedure TTestBodyForm.TestTakesMeasurements;
var
  BodySet: TMeasurementSet;
  Measures: TBodyMeasures;
  Key: string;
begin
  BodySet := SampleSet;
  try
    Measures := BodyMeasuresFrom(BodySet);
  finally
    FreeAndNil(BodySet);
  end;
  AssertNear('bust', 920, Measures.BustCircumference);
  AssertNear('waist height', 1060, Measures.WaistHeight);
  // Missing ones are shares of the given height
  AssertNear('hip height', 1700 * 0.52, Measures.HipHeight);
  for Key in Measures.Estimated do
    AssertTrue('not estimated: ' + Key, (Key <> 'height') and (Key <> 'bust_circumference'));
  AssertTrue('hip height estimated', Pos('height_hip', string.Join(',', Measures.Estimated)) > 0);
end;

procedure TTestBodyForm.TestRingsMatchCircumferences;
var
  BodySet: TMeasurementSet;
  Measures: TBodyMeasures;
  Ring: TBodyRing;
  Found: integer;
begin
  BodySet := SampleSet;
  try
    Measures := BodyMeasuresFrom(BodySet);
  finally
    FreeAndNil(BodySet);
  end;
  Found := 0;
  for Ring in TorsoRings(Measures) do
  begin
    if SameValue(Ring.Height, Measures.WaistHeight) then
    begin
      AssertNear('waist', 740, PolylineLength3(RingPoints(Ring)), 1e-6);
      Inc(Found);
    end;
    if SameValue(Ring.Height, Measures.BustHeight) then
    begin
      AssertNear('bust', 920, PolylineLength3(RingPoints(Ring)), 1e-6);
      Inc(Found);
    end;
    if SameValue(Ring.Height, Measures.HipHeight) then
    begin
      AssertNear('hip', 1000, PolylineLength3(RingPoints(Ring)), 1e-6);
      Inc(Found);
    end;
  end;
  AssertEquals('rings found', 3, Found);
end;

procedure TTestBodyForm.TestRingsGoUp;
var
  Measures: TBodyMeasures;
  Rings: TBodyRingArray;
  Index: integer;
begin
  Measures := DefaultBodyMeasures;
  // Heights out of order cannot fold the torso
  Measures.WaistHeight := Measures.BustHeight + 50;
  Rings := TorsoRings(Measures);
  for Index := 1 to High(Rings) do
    AssertTrue(Format('ring %d above the one below', [Index]), Rings[Index].Height > Rings[Index - 1].Height);
end;

procedure TTestBodyForm.TestMeshIsClosedAndFacesOut;
var
  Mesh: TBodyMesh;
  Edges: TStringList;
  Triangle: TBodyTriangle;

  procedure AddEdge(From, Onto: integer);
  begin
    // Each edge is used once each way in a closed, consistently turned mesh
    AssertTrue(Format('edge %d-%d used once', [From, Onto]), Edges.IndexOf(Format('%d-%d', [From, Onto])) < 0);
    Edges.Add(Format('%d-%d', [From, Onto]));
  end;

var
  Edge: string;
  Ends: TStringArray;
begin
  Mesh := BuildBodyForm(DefaultBodyMeasures);
  Edges := TStringList.Create;
  try
    Edges.Sorted := True;
    for Triangle in Mesh.Triangles do
    begin
      AddEdge(Triangle.First, Triangle.Second);
      AddEdge(Triangle.Second, Triangle.Third);
      AddEdge(Triangle.Third, Triangle.First);
    end;
    for Edge in Edges do
    begin
      Ends := Edge.Split(['-']);
      AssertTrue('edge ' + Edge + ' has its twin', Edges.IndexOf(Ends[1] + '-' + Ends[0]) >= 0);
    end;
  finally
    FreeAndNil(Edges);
  end;
  AssertTrue('faces out', MeshVolume(Mesh) > 0);
end;

procedure TTestBodyForm.TestFigureStandsFacingForwards;
const
  // The crown is the top of an ellipsoid drawn with rings, a little under it
  CROWN_TOLERANCE = 10;
var
  Measures: TBodyMeasures;
  Mesh: TBodyMesh;
  Point, Low, High: TVec3;
begin
  Measures := DefaultBodyMeasures;
  Mesh := BuildBodyForm(Measures);
  Low := Mesh.Vertices[0];
  High := Low;
  for Point in Mesh.Vertices do
  begin
    Low := Vec3(Min(Low.X, Point.X), Min(Low.Y, Point.Y), Min(Low.Z, Point.Z));
    High := Vec3(Max(High.X, Point.X), Max(High.Y, Point.Y), Max(High.Z, Point.Z));
  end;
  AssertNear('on the floor', 0, Low.Z, 1e-6);
  AssertNear('as tall as the height', Measures.Height, High.Z, CROWN_TOLERANCE);
  AssertTrue('no higher', High.Z <= Measures.Height + 1e-6);
  AssertTrue('feet point forwards, past the torso', Low.Y < -BodyFrontDepth(Measures) - Measures.FootLength / 4);
  AssertTrue('arms out past the shoulders', High.X > Measures.ShoulderWidth / 2 + Measures.ArmLength * Sin(DegToRad(ARM_ANGLE)) / 2);
  AssertNear('left and right alike', -Low.X, High.X, 1e-6);
  AssertTrue('arms hang out and down', (ArmDirection(1).X > 0) and (ArmDirection(1).Z < 0) and (ArmDirection(-1).X < 0));
end;

// A full skirt does not catch on the arms: without them the figure is no wider
// than its shoulders, bust or hips
procedure TTestBodyForm.TestFigureWithoutArms;
var
  Measures: TBodyMeasures;
  Whole, Bare: TBodyMesh;
  Point: TVec3;
  Widest: double;
begin
  Measures := DefaultBodyMeasures;
  Whole := BuildBodyForm(Measures);
  Bare := BuildBodyForm(Measures, False);
  AssertTrue('fewer points', Length(Bare.Vertices) < Length(Whole.Vertices));
  Widest := 0;
  for Point in Bare.Vertices do
    Widest := Max(Widest, Abs(Point.X));
  AssertTrue('no wider than the shoulders, bust or hips', Widest <= Max(Measures.ShoulderWidth / 2,
    Max(Measures.BustCircumference, Measures.HipCircumference) / 4) + 1e-6);
  AssertTrue('still closed', MeshVolume(Bare) > 0);
  AssertTrue('smaller', MeshVolume(Bare) < MeshVolume(Whole));
end;

// Issue #70: no nose, as the feet show which way the figure faces; the head
// reaches as far forwards as backwards
procedure TTestBodyForm.TestHeadIsPlain;
var
  Measures: TBodyMeasures;
  Point: TVec3;
  Front, Back: double;
begin
  Measures := DefaultBodyMeasures;
  Front := 0;
  Back := 0;
  for Point in BuildBodyForm(Measures).Vertices do
    if Point.Z > Measures.Height - Measures.HeadLength * 0.75 then
    begin
      Front := Min(Front, Point.Y);
      Back := Max(Back, Point.Y);
    end;
  AssertNear('as deep in front as behind', Back, -Front, 1e-6);
end;

procedure TTestBodyForm.TestSizeOfATable;
var
  Table: TMeasurementSet;
  Measures: TBodyMeasures;
  Err: string;
begin
  Table := TMeasurementSet.Create;
  try
    AssertTrue(Err, Table.LoadFromText('{"format": "measurements", "version": 1, "units": "mm", "name": "Sizes", "notes": "",' +
      ' "sizes": ["36", "38"], "measurements": [{"key": "waist_circumference", "values": [700, 740]}]}', Err));
    Measures := BodyMeasuresFrom(Table, 1);
    AssertNear('second size', 740, Measures.WaistCircumference);
    Measures := BodyMeasuresFrom(Table, 0);
    AssertNear('first size', 700, Measures.WaistCircumference);
  finally
    FreeAndNil(Table);
  end;
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

// An edge is attached to the body by its key, the fold left out, and let go
procedure TTestDrapeFile.TestAttachEdges;
var
  Top, Fold: string;
begin
  Top := EdgeBetween(FFront, Vec2(0, 0), Vec2(120, 0));
  Fold := EdgeBetween(FFront, Vec2(0, 0), Vec2(0, 200));
  AssertEquals('every edge', 4, Length(FDrape.AttachableEdges(FrontCopy)));
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(FFront, Fold));
  FPattern.Evaluate;
  AssertEquals('not the fold', 3, Length(FDrape.AttachableEdges(FrontCopy)));
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, 0, 0)));
  FDrape.SetAttached(0, Top, True);
  FDrape.SetAttached(0, Top, True);
  AssertEquals('once', 1, Length(FDrape.Items[0].Attached));
  AssertTrue('attached', FDrape.IsAttached(0, Top));
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(100, 0, 0)));
  AssertTrue('kept as it moves', FDrape.IsAttached(0, Top));
  FDrape.SetAttached(0, Top, False);
  AssertFalse('let go', FDrape.IsAttached(0, Top));
  AssertFalse('no such item', FDrape.IsAttached(5, Top));
end;

procedure TTestDrapeFile.TestAttachedEdgeGone;
var
  Problem: TDrapeProblem;
  Found: integer;
begin
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, 0, 0)));
  FDrape.Place(BackCopy, UprightPlacement(Vec3(300, 0, 0)));
  FDrape.SetAttached(0, '9999', True);
  Found := 0;
  for Problem in FDrape.Problems do
    if Problem.Text = Format(rsDrapeAttachedGone, ['dress.sloper', 'Front', '9999']) then
    begin
      Inc(Found);
      AssertEquals('on the front', 0, Problem.Item);
    end;
  AssertEquals('listed', 1, Found);
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
  FDrape.Body.NoArms := True;
  FDrape.SetAttached(0, EdgeBetween(FBack, Vec2(200, 0), Vec2(300, 0)), True);
  Text := FDrape.SaveToText;
  Loaded := TDrape.Create;
  try
    AssertTrue(Err, Loaded.LoadFromText(Text, Err));
    AssertTrue('without arms', Loaded.Body.NoArms);
    AssertEquals('attached', 1, Length(Loaded.Items[0].Attached));
    AssertTrue('the top', Loaded.IsAttached(0, EdgeBetween(FBack, Vec2(200, 0), Vec2(300, 0))));
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
  Refused('attached', HEAD + '"placements": [{"source": 1, "piece": 3, "position": [0, 0, 0], "rotation": [0, 0, 0], ' +
    '"attached": ["waist"]}]}', Format(rsDrapeBadAttached, [1]));
  Refused('arms', HEAD + '"body": {"kind": "measurements", "arms": "no"}}', rsDrapeBadBody);
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

procedure TTestDrapeFile.TestGuessUsesTheBody;
var
  Low, High: TVec3;
  Measures: TBodyMeasures;
begin
  FSource.Measurements := TMeasurementSet.Create;
  FSource.Measurements.Add('height_waist', 1040);
  FDrape.GuessPlacements;
  AssertTrue('a body', FDrape.BodyMeasures(Measures));
  PlacedExtent(FrontCopy, Low, High);
  AssertNear('middle at the waist', 1040, (Low.Z + High.Z) / 2, 1e-6);
  AssertNear('the gap in front of the form', -(BodyFrontDepth(Measures) + FDrape.Gap), Low.Y, 1e-6);
  FDrape.Body.Kind := bkNone;
  AssertFalse('no body', FDrape.BodyMeasures(Measures));
end;

procedure TTestDrapeFile.TestMissingBodyFile;
var
  Problem: TDrapeProblem;
  Found: boolean;
  Measures: TBodyMeasures;
begin
  FDrape.FileName := ConcatPaths([GetTempDir, 'drape-test.sdrape']);
  FDrape.Body.MeasurementFile := 'no-such-file.slm';
  FDrape.LoadBody;
  Found := False;
  for Problem in FDrape.Problems do
    Found := Found or (Pos('no-such-file.slm', Problem.Text) > 0);
  AssertTrue('said', Found);
  // Still a whole form to place pieces on
  AssertTrue('a body', FDrape.BodyMeasures(Measures));
  AssertTrue('the default form', Measures.Height > 0);
end;

procedure TTestDrapeFile.TestSceneBackToFront;
var
  Faces: TDrapeFaceArray;
  Index, Last: integer;
  Camera: TDrapeCamera;
  Screen: TVec2;
  Depth: double;
begin
  FDrape.GuessPlacements;
  Faces := BuildDrapeScene(FDrape, DefaultDrapeCamera);
  AssertTrue('body and pieces', Length(Faces) > 2);
  for Index := 1 to High(Faces) do
    AssertTrue('back to front', Faces[Index].Depth <= Faces[Index - 1].Depth);
  // The front hangs in front of the form, so it is drawn over it
  Camera := DefaultDrapeCamera;
  Camera.Project(FDrape.Items[FDrape.IndexOf(FrontCopy)].Placement.Position, Screen, Depth);
  Last := -1;
  for Index := 0 to High(Faces) do
    if PointInPolygon(Screen, Faces[Index].Points) then
      Last := Index;
  AssertTrue('covers something', Last >= 0);
  AssertEquals('the front on top', FDrape.IndexOf(FrontCopy), Faces[Last].Item);
end;

procedure TTestDrapeFile.TestScenePicksPieces;
var
  Camera: TDrapeCamera;
  Screen: TVec2;
  Depth: double;
  Faces: TDrapeFaceArray;
begin
  FDrape.GuessPlacements;
  Camera := DefaultDrapeCamera;
  Faces := BuildDrapeScene(FDrape, Camera);
  Camera.Project(FDrape.Items[FDrape.IndexOf(FrontCopy)].Placement.Position, Screen, Depth);
  AssertEquals('the front', FDrape.IndexOf(FrontCopy), DrapePieceAt(Faces, Screen));
  // Above the pieces there is only the form, which is not picked
  Camera.Project(Vec3(0, 0, DefaultBodyMeasures.ShoulderHeight), Screen, Depth);
  AssertEquals('nothing', -1, DrapePieceAt(Faces, Screen));
end;

procedure TTestDrapeFile.TestAlignableSeams;
begin
  AssertEquals('nothing placed', 0, Length(FDrape.AlignableSeams(BackCopy)));
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, -170, 1000)));
  AssertEquals('the side seam', 1, Length(FDrape.AlignableSeams(BackCopy)));
  AssertSame('it', FSideSeam, FDrape.AlignableSeams(BackCopy)[0]);
end;

procedure TTestDrapeFile.TestSeamLinks;
var
  Links: TDrapeSeamLinkArray;
  Link: TDrapeSeamLink;
begin
  AssertEquals('none before placing', 0, Length(FDrape.SeamLinks));
  FDrape.Body.Kind := bkNone;
  FDrape.GuessPlacements;
  Links := FDrape.SeamLinks;
  AssertEquals('start, middle and end', 3, Length(Links));
  // Laid flat beside each other, each side's point is the gap from the other's
  for Link in Links do
    AssertNear('the gap', FDrape.Gap, Distance3(Link.From, Link.Onto), 1e-6);
  AssertNear('middle halfway down', (Links[0].From.Z + Links[2].From.Z) / 2, Links[1].From.Z, 1e-6);
  AssertEquals('on screen', 3, Length(DrapeSceneLines(FDrape, DefaultDrapeCamera)));
end;

procedure TTestDrapeFile.TestSceneWrongSide;
var
  Face: TDrapeFace;
  Faces: TDrapeFaceArray;
begin
  FDrape.Body.Kind := bkNone;
  FDrape.Place(FrontCopy, UprightPlacement(Vec3(0, -200, 1000)));
  for Face in BuildDrapeScene(FDrape, DefaultDrapeCamera) do
    AssertFalse('right side from the front', Face.WrongSide);
  Faces := BuildDrapeScene(FDrape, CameraForView(DefaultDrapeCamera, tvBack));
  AssertEquals('one piece', 1, Length(Faces));
  AssertTrue('wrong side from the back', Faces[0].WrongSide);
end;

procedure TTestDrapeFile.TestSceneWithoutBody;
begin
  FDrape.Body.Kind := bkNone;
  AssertEquals('nothing placed, nothing drawn', 0, Length(BuildDrapeScene(FDrape, DefaultDrapeCamera)));
end;

{ TTestDrapeDocument }

procedure TTestDrapeDocument.TestUndoAndRedo;
var
  Document: TDrapeDocument;
  Source: TPatternSource;
begin
  Document := TDrapeDocument.Create;
  try
    AssertFalse('new', Document.Modified);
    Document.BeginChange('Add');
    Source := Document.Drape.AddSource('a.sloper', '', '');
    Document.Drape.Place(DrapePieceCopy(Source.Id, '3', 1), UprightPlacement(Vec3(1, 2, 3)));
    Document.EndChange;
    AssertTrue('modified', Document.Modified);
    AssertEquals('undo named', 'Add', Document.UndoDescription);
    Document.BeginChange('Move');
    Document.Drape.Place(DrapePieceCopy(Source.Id, '3', 1), UprightPlacement(Vec3(5, 2, 3)));
    Document.EndChange;
    Document.Undo;
    AssertNear('moved back', 1, Document.Drape.Items[0].Placement.Position.X);
    Document.Redo;
    AssertNear('moved again', 5, Document.Drape.Items[0].Placement.Position.X);
    Document.Undo;
    Document.Undo;
    AssertEquals('nothing', 0, Length(Document.Drape.Items));
    AssertFalse('as saved', Document.Modified);
  finally
    FreeAndNil(Document);
  end;
end;

// The skirt block example, guessed and seen from low down to the form's right,
// as it first showed wrongly: the front lies wholly in front of the form, so
// it is on top all over
procedure TTestDrapeDocument.TestSkirtFrontDrawnOverForm;
var
  Document: TDrapeDocument;
  Camera: TDrapeCamera;
  Faces: TDrapeFaceArray;
  Points: TVec3Array;
  Anchor: TVec3;
  Screen: TVec2;
  Depth: double;
  Item, Index, Last, Corner, Step: integer;
  Front: TDrapePieceCopy;
begin
  Document := TDrapeDocument.Create;
  try
    Document.NewForPattern(ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs', 'examples', 'skirt-block',
      'skirt-block.sloper']));
    AssertTrue('placed', Length(Document.Drape.Items) > 0);
    // The first guess is the largest piece, in front of the form
    Front := Document.Drape.Items[0].Piece;
    Item := Document.Drape.IndexOf(Front);
    Camera := DefaultDrapeCamera;
    Camera.Target := Vec3(-400, 0, 750);
    Camera.Yaw := -44;
    Camera.Pitch := -16;
    Faces := BuildDrapeScene(Document.Drape, Camera);
    AssertTrue(Document.Drape.PlacedOutline(Front, Points));
    Anchor := Document.Drape.Items[Item].Placement.Position;
    for Corner := 0 to High(Points) do
      for Step := 1 to 9 do
      begin
        Camera.Project(Anchor + (Points[Corner] - Anchor) * (Step / 10), Screen, Depth);
        Last := -1;
        for Index := 0 to High(Faces) do
          if PointInPolygon(Screen, Faces[Index].Points) then
            Last := Index;
        AssertTrue('covers something', Last >= 0);
        AssertEquals(Format('the front on top towards corner %d at %d tenths', [Corner, Step]), Item, Faces[Last].Item);
      end;
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestDrapeDocument.TestCancelRestores;
var
  Document: TDrapeDocument;
begin
  Document := TDrapeDocument.Create;
  try
    Document.BeginChange('Gap');
    Document.Drape.Gap := 50;
    Document.CancelChange;
    AssertNear('gap back', DEFAULT_DRAPE_GAP, Document.Drape.Gap);
    AssertFalse('no step', Document.CanUndo);
  finally
    FreeAndNil(Document);
  end;
end;

initialization
  RegisterTest(TTestDrapeDocument);
  RegisterTest(TTestGeometry3);
  RegisterTest(TTestDrapePlacement);
  RegisterTest(TTestBodyForm);
  RegisterTest(TTestDrapeFile);
end.
