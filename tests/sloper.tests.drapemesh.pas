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

// Seam pairing for draping: a drape's placed pieces meshed with both sides of
// each seam on paired vertices.
unit Sloper.Tests.DrapeMesh;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.Draft, Sloper.Core.Pattern,
  Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.PatternSources, Sloper.Core.DrapePlacement, Sloper.Core.DrapeFile,
  Sloper.Core.Mesher, Sloper.Core.DrapeMesh;

type
  TTestDrapeMesh = class(TOSTestCase)
  private
    FDrape: TDrape;
    FPattern: TPattern;
    FSource: TPatternSource;
    // A piece with straight edges between the points, as drafted
    function Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
    function EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
    function Side(const Pieces: array of TPieceObject; const EdgeKeys: array of string): TSeamSide;
    function Place(Piece: TPieceObject; Copy: integer; X: double): integer;
    // A front and a back, joined by a side seam 200 long
    procedure FrontAndBack(out Front, Back: TPieceObject; BackHeight: double = 200);
    function Vertex(const Meshing: TDrapeMeshing; Item, Index: integer): TVec2;
    procedure AssertMeshesWhole(const Meshing: TDrapeMeshing);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSideSeamPairsEvenly;
    procedure TestEaseSpreadsEvenly;
    procedure TestDartPairsFromTheApex;
    procedure TestSideOnTwoPieces;
    procedure TestMirroredCopiesSewnByPlacement;
    procedure TestFoldHalvesEachSewn;
    procedure TestOpenSeamIsAProblem;
  end;

implementation

const
  SPACING = 10;
  // Mesh area compared with the piece's, in mm²
  AREA_TOLERANCE = 1e-6;

procedure TTestDrapeMesh.SetUp;
begin
  FDrape := TDrape.Create;
  FSource := FDrape.AddSource('dress.sloper', '', '');
  FPattern := TPattern.Create;
  FSource.Pattern := FPattern;
end;

procedure TTestDrapeMesh.TearDown;
begin
  // The source owns the pattern
  FreeAndNil(FDrape);
end;

function TTestDrapeMesh.Shape(const AName: string; const Xs, Ys: array of double): TPieceObject;
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

function TTestDrapeMesh.EdgeBetween(Piece: TPieceObject; const A, B: TVec2): string;
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

function TTestDrapeMesh.Side(const Pieces: array of TPieceObject; const EdgeKeys: array of string): TSeamSide;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Pieces));
  for Index := 0 to High(Pieces) do
  begin
    Result[Index].PieceKey := Pieces[Index].Key;
    Result[Index].EdgeKey := EdgeKeys[Index];
  end;
end;

function TTestDrapeMesh.Place(Piece: TPieceObject; Copy: integer; X: double): integer;
begin
  FDrape.Place(DrapePieceCopy(FSource.Id, Piece.Key, Copy), UprightPlacement(Vec3(X, 0, 1000)));
  Result := FDrape.IndexOf(DrapePieceCopy(FSource.Id, Piece.Key, Copy));
end;

procedure TTestDrapeMesh.FrontAndBack(out Front, Back: TPieceObject; BackHeight: double);
begin
  // Clockwise, as drafted: the side seam runs down both edges
  Front := Shape('Front', [0, 120, 120, 0], [0, 0, 200, 200]);
  Back := Shape('Back', [200, 300, 300, 200], [0, 0, BackHeight, BackHeight]);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Side', Side([Front], [EdgeBetween(Front, Vec2(120, 0), Vec2(120, 200))]),
    Side([Back], [EdgeBetween(Back, Vec2(200, 0), Vec2(200, BackHeight))])));
  FPattern.Evaluate;
end;

function TTestDrapeMesh.Vertex(const Meshing: TDrapeMeshing; Item, Index: integer): TVec2;
begin
  Result := Meshing.Meshes[Item].Points[Index];
end;

procedure TTestDrapeMesh.AssertMeshesWhole(const Meshing: TDrapeMeshing);
var
  Item: integer;
  Pair: TDrapeSeamPair;
  Piece: TPieceObject;
begin
  AssertEquals('a mesh per item', Length(FDrape.Items), Length(Meshing.Meshes));
  for Item := 0 to High(FDrape.Items) do
  begin
    AssertTrue('found', FDrape.FindPiece(FDrape.Items[Item].Piece, Piece));
    AssertNear('area', Abs(SignedArea(PlacedSeamLine(Piece))), MeshArea(Meshing.Meshes[Item]), AREA_TOLERANCE);
  end;
  for Pair in Meshing.Pairs do
  begin
    AssertTrue('first on the outline', (Pair.FirstVertex >= 0) and (Pair.FirstVertex < Meshing.Meshes[Pair.FirstItem].OutlineCount));
    AssertTrue('second on the outline', (Pair.SecondVertex >= 0) and (Pair.SecondVertex < Meshing.Meshes[Pair.SecondItem].OutlineCount));
  end;
end;

procedure TTestDrapeMesh.TestSideSeamPairsEvenly;
var
  Front, Back: TPieceObject;
  FrontItem, BackItem, Index: integer;
  Meshing: TDrapeMeshing;
  Pair: TDrapeSeamPair;
  Heights: array of double;
  Own, Theirs: TVec2;
begin
  FrontAndBack(Front, Back);
  FrontItem := Place(Front, 1, -150);
  BackItem := Place(Back, 1, 150);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertMeshesWhole(Meshing);
  AssertEquals('problems', 0, Length(Meshing.Problems));
  AssertEquals('a pair every 10 mm, both ends', 21, Length(Meshing.Pairs));
  Heights := nil;
  for Pair in Meshing.Pairs do
  begin
    AssertEquals('side A on the front', FrontItem, Pair.FirstItem);
    AssertEquals('side B on the back', BackItem, Pair.SecondItem);
    Own := Vertex(Meshing, Pair.FirstItem, Pair.FirstVertex);
    Theirs := Vertex(Meshing, Pair.SecondItem, Pair.SecondVertex);
    AssertNear('front side seam', 120, Own.X);
    AssertNear('back side seam', 200, Theirs.X);
    AssertNear('level', Own.Y, Theirs.Y);
    Insert(Own.Y, Heights, Length(Heights));
  end;
  for Index := 0 to High(Heights) do
    AssertNear('from the top down', 10 * Index, Heights[Index]);
end;

procedure TTestDrapeMesh.TestEaseSpreadsEvenly;
var
  Front, Back: TPieceObject;
  Meshing: TDrapeMeshing;
  Pair: TDrapeSeamPair;
begin
  FrontAndBack(Front, Back, 220);
  Place(Front, 1, -150);
  Place(Back, 1, 150);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertMeshesWhole(Meshing);
  AssertEquals('steps no longer than the spacing on the longer side', 23, Length(Meshing.Pairs));
  for Pair in Meshing.Pairs do
    AssertNear('same share of each side', Vertex(Meshing, Pair.FirstItem, Pair.FirstVertex).Y / 200,
      Vertex(Meshing, Pair.SecondItem, Pair.SecondVertex).Y / 220);
end;

procedure TTestDrapeMesh.TestDartPairsFromTheApex;
var
  Piece: TPieceObject;
  Meshing: TDrapeMeshing;
  Pair: TDrapeSeamPair;
  Apex, Own, Theirs: TVec2;
begin
  Apex := Vec2(50, 60);
  Piece := Shape('Skirt', [0, 40, Apex.X, 60, 100, 100, 0], [0, 0, Apex.Y, 0, 0, 150, 150]);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Dart', Side([Piece], [EdgeBetween(Piece, Vec2(40, 0), Apex)]),
    Side([Piece], [EdgeBetween(Piece, Apex, Vec2(60, 0))])));
  FPattern.Evaluate;
  Place(Piece, 1, 0);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertMeshesWhole(Meshing);
  // Legs about 61 long: seven steps, the apex not sewn to itself
  AssertEquals('pairs', 7, Length(Meshing.Pairs));
  for Pair in Meshing.Pairs do
  begin
    Own := Vertex(Meshing, Pair.FirstItem, Pair.FirstVertex);
    Theirs := Vertex(Meshing, Pair.SecondItem, Pair.SecondVertex);
    AssertTrue('left leg', Own.X < Apex.X);
    AssertTrue('right leg', Theirs.X > Apex.X);
    AssertNear('as far from the apex', Distance(Own, Apex), Distance(Theirs, Apex));
  end;
end;

procedure TTestDrapeMesh.TestSideOnTwoPieces;
var
  Cap, Front, Back: TPieceObject;
  CapItem, FrontItem, BackItem: integer;
  Meshing: TDrapeMeshing;
  Pair: TDrapeSeamPair;
  AtMiddle: integer;
  Theirs: TVec2;
begin
  // A cap 200 long sewn to two edges 100 long, one after the other
  Cap := Shape('Cap', [0, 200, 200, 0], [300, 300, 400, 400]);
  Front := Shape('Front', [0, 100, 100, 0], [0, 0, 100, 100]);
  Back := Shape('Back', [300, 400, 400, 300], [0, 0, 100, 100]);
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Armhole', Side([Cap], [EdgeBetween(Cap, Vec2(0, 300), Vec2(200, 300))]),
    Side([Front, Back], [EdgeBetween(Front, Vec2(0, 100), Vec2(100, 100)), EdgeBetween(Back, Vec2(300, 100), Vec2(400, 100))])));
  FPattern.Evaluate;
  CapItem := Place(Cap, 1, 0);
  FrontItem := Place(Front, 1, -100);
  BackItem := Place(Back, 1, 100);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertMeshesWhole(Meshing);
  AssertEquals('one more at the break', 22, Length(Meshing.Pairs));
  AtMiddle := 0;
  for Pair in Meshing.Pairs do
  begin
    AssertEquals('cap first', CapItem, Pair.FirstItem);
    Theirs := Vertex(Meshing, Pair.SecondItem, Pair.SecondVertex);
    if PointsNear(Vertex(Meshing, Pair.FirstItem, Pair.FirstVertex), Vec2(100, 300)) then
    begin
      Inc(AtMiddle);
      if Pair.SecondItem = FrontItem then
        AssertPointsNear('front ends', Vec2(100, 100), Theirs)
      else
      begin
        AssertEquals('back', BackItem, Pair.SecondItem);
        AssertPointsNear('back starts', Vec2(300, 100), Theirs);
      end;
    end;
  end;
  AssertEquals('the cap''s middle sewn to both', 2, AtMiddle);
end;

procedure TTestDrapeMesh.TestMirroredCopiesSewnByPlacement;
var
  Front, Back: TPieceObject;
  Left, Right, BackLeft, BackRight: integer;
  Meshing: TDrapeMeshing;
  Pair: TDrapeSeamPair;
begin
  FrontAndBack(Front, Back);
  AssertTrue(FPattern.LastError, FPattern.SetCut(Front, 2, True));
  AssertTrue(FPattern.LastError, FPattern.SetCut(Back, 2, True));
  FPattern.Evaluate;
  // Each back placed by the other side's front: the side seams of the first
  // front and the second back, turned round, lie at X = -140
  Left := Place(Front, 1, -200);
  Right := Place(Front, 2, 600);
  BackRight := Place(Back, 1, 590);
  BackLeft := Place(Back, 2, -190);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertMeshesWhole(Meshing);
  AssertEquals('both seams', 42, Length(Meshing.Pairs));
  for Pair in Meshing.Pairs do
    if Pair.FirstItem = Left then
      AssertEquals('left with left', BackLeft, Pair.SecondItem)
    else
    begin
      AssertEquals('front', Right, Pair.FirstItem);
      AssertEquals('right with right', BackRight, Pair.SecondItem);
    end;
end;

procedure TTestDrapeMesh.TestFoldHalvesEachSewn;
var
  Front, Back: TPieceObject;
  FrontItem, Plain, Turned: integer;
  Meshing: TDrapeMeshing;
  Pair: TDrapeSeamPair;
  Own: TVec2;
  Counts: array[boolean] of integer;
begin
  FrontAndBack(Front, Back);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Front, EdgeBetween(Front, Vec2(0, 0), Vec2(0, 200))));
  AssertTrue(FPattern.LastError, FPattern.SetCut(Back, 2, True));
  FPattern.Evaluate;
  FrontItem := Place(Front, 1, 0);
  Plain := Place(Back, 1, 400);
  Turned := Place(Back, 2, -400);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertMeshesWhole(Meshing);
  AssertEquals('both halves', 42, Length(Meshing.Pairs));
  Counts[False] := 0;
  Counts[True] := 0;
  for Pair in Meshing.Pairs do
  begin
    AssertEquals('front first', FrontItem, Pair.FirstItem);
    // The half as drafted is on the right once placed, nearer the first back
    Own := Vertex(Meshing, FrontItem, Pair.FirstVertex);
    AssertNear('a side seam', 120, Abs(Own.X));
    if Own.X > 0 then
      AssertEquals('the half nearer', Plain, Pair.SecondItem)
    else
      AssertEquals('the mirrored half', Turned, Pair.SecondItem);
    Inc(Counts[Own.X > 0]);
  end;
  AssertEquals('one half', 21, Counts[False]);
  AssertEquals('other half', 21, Counts[True]);
end;

procedure TTestDrapeMesh.TestOpenSeamIsAProblem;
var
  Front, Back: TPieceObject;
  Meshing: TDrapeMeshing;
begin
  FrontAndBack(Front, Back);
  AssertTrue(FPattern.LastError, FPattern.SetCut(Front, 2, True));
  FPattern.Evaluate;
  Place(Front, 1, -200);
  Place(Front, 2, 200);
  Place(Back, 1, 300);
  Meshing := MeshDrape(FDrape, SPACING);
  AssertEquals('one front sewn', 21, Length(Meshing.Pairs));
  AssertEquals('problems', 1, Length(Meshing.Problems));
  AssertEquals('open', Format(rsDrapeSeamOpen, ['dress.sloper', 'Side', 'Front', 'Back']), Meshing.Problems[0].Text);
end;

initialization
  RegisterTest(TTestDrapeMesh);

end.
