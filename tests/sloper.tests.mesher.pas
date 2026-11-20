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

// Meshing flat pieces for the drape app: resampling outlines, and meshes that
// cover the outline exactly with well shaped triangles.
unit Sloper.Tests.Mesher;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Mesher;

type
  TTestMesher = class(TOSTestCase)
  private
    function Polygon(const Xs, Ys: array of double): TVec2Array;
    // Area, every triangle inside and turning anticlockwise, every outline
    // edge in the mesh, every point in a triangle, the outline kept in order
    procedure CheckMesh(const Name: string; const Outline: TVec2Array; const Mesh: TFlatMesh);
    function SmallestAngle(const Mesh: TFlatMesh): double;
  published
    procedure TestResampleKeepsCorners;
    procedure TestResampleKeepsAskedPoints;
    procedure TestResampleCircle;
    procedure TestRectangle;
    procedure TestRectangleTrianglesAreWellShaped;
    procedure TestConcaveShape;
    procedure TestDartNotch;
    procedure TestClockwiseOutline;
    procedure TestTooSmall;
    procedure TestLargePiece;
  end;

implementation

uses
  Math, Generics.Collections;

const
  SPACING = 10;
  // The worst angle a mesh of a plain shape may have, in degrees
  MIN_GOOD_ANGLE = 25;

function TTestMesher.Polygon(const Xs, Ys: array of double): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Xs));
  for Index := 0 to High(Xs) do
    Result[Index] := Vec2(Xs[Index], Ys[Index]);
end;

function EdgeName(A, B: integer): string;
begin
  Result := Format('%d-%d', [Min(A, B), Max(A, B)]);
end;

procedure TTestMesher.CheckMesh(const Name: string; const Outline: TVec2Array; const Mesh: TFlatMesh);
var
  Triangle: TMeshTriangle;
  Edges: specialize THashSet<string>;
  Used: array of boolean;
  Index: integer;
  Middle: TVec2;
  Area: double;
  Order: TVec2Array;
begin
  AssertTrue(Name + ': triangles', Length(Mesh.Triangles) > 0);
  AssertNear(Name + ': area', Abs(SignedArea(Outline)), MeshArea(Mesh), 1e-6 * Abs(SignedArea(Outline)) + 1e-6);
  Order := Copy(Mesh.Points, 0, Mesh.OutlineCount);
  AssertEquals(Name + ': outline count', Length(Outline), Mesh.OutlineCount);
  for Index := 0 to High(Outline) do
    AssertPointsNear(Name + ': outline kept', Outline[Index], Order[Index]);
  Edges := specialize THashSet<string>.Create;
  try
    Used := nil;
    SetLength(Used, Length(Mesh.Points));
    for Triangle in Mesh.Triangles do
    begin
      Area := Cross(Mesh.Points[Triangle.Second] - Mesh.Points[Triangle.First], Mesh.Points[Triangle.Third] - Mesh.Points[Triangle.First]);
      AssertTrue(Name + ': anticlockwise on screen', Area < 0);
      Middle := (Mesh.Points[Triangle.First] + Mesh.Points[Triangle.Second] + Mesh.Points[Triangle.Third]) * (1 / 3);
      AssertTrue(Name + ': inside', PointInPolygon(Middle, Outline));
      Edges.Add(EdgeName(Triangle.First, Triangle.Second));
      Edges.Add(EdgeName(Triangle.Second, Triangle.Third));
      Edges.Add(EdgeName(Triangle.Third, Triangle.First));
      Used[Triangle.First] := True;
      Used[Triangle.Second] := True;
      Used[Triangle.Third] := True;
    end;
    for Index := 0 to High(Used) do
      AssertTrue(Format('%s: point %d in a triangle', [Name, Index]), Used[Index]);
    // Splits come after the outline given, so walk the boundary by position:
    // every outline edge given is in the mesh, or split into edges that are
    AssertEquals(Name + ': no splits needed', Mesh.OutlineCount, Mesh.BoundaryCount);
    for Index := 0 to Mesh.OutlineCount - 1 do
      AssertTrue(Format('%s: outline edge %d', [Name, Index]), Edges.Contains(EdgeName(Index, (Index + 1) mod Mesh.OutlineCount)));
  finally
    FreeAndNil(Edges);
  end;
end;

function TTestMesher.SmallestAngle(const Mesh: TFlatMesh): double;
var
  Triangle: TMeshTriangle;
  Corners: array[0..2] of TVec2;
  Corner: integer;
  Toward, Away: TVec2;
begin
  Result := 180;
  for Triangle in Mesh.Triangles do
  begin
    Corners[0] := Mesh.Points[Triangle.First];
    Corners[1] := Mesh.Points[Triangle.Second];
    Corners[2] := Mesh.Points[Triangle.Third];
    for Corner := 0 to 2 do
    begin
      Toward := (Corners[(Corner + 1) mod 3] - Corners[Corner]).Normalized;
      Away := (Corners[(Corner + 2) mod 3] - Corners[Corner]).Normalized;
      Result := Min(Result, RadToDeg(ArcCos(EnsureRange(Dot(Toward, Away), -1, 1))));
    end;
  end;
end;

procedure TTestMesher.TestResampleKeepsCorners;
var
  Points: TVec2Array;
  Index: integer;
begin
  Points := ResampleOutline(Polygon([0, 100, 100, 0], [0, 0, 50, 50]), nil, SPACING);
  AssertEquals('steps', 30, Length(Points));
  AssertPointsNear('first corner', Vec2(0, 0), Points[0]);
  AssertPointsNear('second corner', Vec2(100, 0), Points[10]);
  AssertPointsNear('third corner', Vec2(100, 50), Points[15]);
  AssertPointsNear('fourth corner', Vec2(0, 50), Points[25]);
  for Index := 0 to High(Points) do
    AssertNear('even steps', SPACING, Distance(Points[Index], Points[(Index + 1) mod Length(Points)]), 1e-9);
end;

procedure TTestMesher.TestResampleKeepsAskedPoints;
var
  Points: TVec2Array;
  Found: boolean;
  Point: TVec2;
begin
  // A seam's end at 33 along the top edge stays a point
  Points := ResampleOutline(Polygon([0, 33, 100, 100, 0], [0, 0, 0, 50, 50]), [False, True], SPACING);
  Found := False;
  for Point in Points do
    Found := Found or PointsNear(Point, Vec2(33, 0));
  AssertTrue('kept', Found);
  // Without asking, a point on a straight run is not kept
  Points := ResampleOutline(Polygon([0, 33, 100, 100, 0], [0, 0, 0, 50, 50]), nil, SPACING);
  Found := False;
  for Point in Points do
    Found := Found or PointsNear(Point, Vec2(33, 0));
  AssertFalse('not kept', Found);
end;

procedure TTestMesher.TestResampleCircle;
var
  Circle, Points: TVec2Array;
  Index: integer;
begin
  Circle := nil;
  SetLength(Circle, 360);
  for Index := 0 to 359 do
    Circle[Index] := PolarPoint(Vec2(0, 0), 100, Index);
  Points := ResampleOutline(Circle, nil, SPACING);
  Insert(Circle[0], Circle, Length(Circle));
  AssertEquals('steps round', Ceil(PolylineLength(Circle) / SPACING), Length(Points));
end;

procedure TTestMesher.TestRectangle;
var
  Outline: TVec2Array;
begin
  Outline := ResampleOutline(Polygon([0, 200, 200, 0], [0, 0, 100, 100]), nil, SPACING);
  CheckMesh('rectangle', Outline, MeshPolygon(Outline, SPACING));
end;

procedure TTestMesher.TestRectangleTrianglesAreWellShaped;
var
  Outline: TVec2Array;
  Mesh: TFlatMesh;
  Triangle: TMeshTriangle;
  Longest, Edge: double;
begin
  Outline := ResampleOutline(Polygon([0, 200, 200, 0], [0, 0, 100, 100]), nil, SPACING);
  Mesh := MeshPolygon(Outline, SPACING);
  AssertTrue(Format('smallest angle %.1f', [SmallestAngle(Mesh)]), SmallestAngle(Mesh) >= MIN_GOOD_ANGLE);
  // Evenly sized: no edge much longer than the spacing
  Longest := 0;
  for Triangle in Mesh.Triangles do
  begin
    Edge := Max(Distance(Mesh.Points[Triangle.First], Mesh.Points[Triangle.Second]),
      Max(Distance(Mesh.Points[Triangle.Second], Mesh.Points[Triangle.Third]), Distance(Mesh.Points[Triangle.Third],
      Mesh.Points[Triangle.First])));
    Longest := Max(Longest, Edge);
  end;
  AssertTrue(Format('longest edge %.1f', [Longest]), Longest < 2 * SPACING);
end;

procedure TTestMesher.TestConcaveShape;
var
  Outline: TVec2Array;
begin
  // An L
  Outline := ResampleOutline(Polygon([0, 150, 150, 60, 60, 0], [0, 0, 60, 60, 200, 200]), nil, SPACING);
  CheckMesh('L', Outline, MeshPolygon(Outline, SPACING));
end;

procedure TTestMesher.TestDartNotch;
var
  Outline: TVec2Array;
  Mesh: TFlatMesh;
begin
  // A 200 mm square with a narrow dart in its top edge, apex 80 mm down
  Outline := ResampleOutline(Polygon([0, 95, 100, 105, 200, 200, 0], [0, 0, 80, 0, 0, 200, 200]), nil, SPACING);
  Mesh := MeshPolygon(Outline, SPACING);
  AssertNear('area', Abs(SignedArea(Outline)), MeshArea(Mesh), 1e-6 * Abs(SignedArea(Outline)));
  AssertTrue('splits keep the outline', Mesh.BoundaryCount >= Mesh.OutlineCount);
end;

procedure TTestMesher.TestClockwiseOutline;
var
  Outline: TVec2Array;
  Reversed: TVec2Array;
  Index: integer;
begin
  Outline := ResampleOutline(Polygon([0, 200, 200, 0], [0, 0, 100, 100]), nil, SPACING);
  Reversed := nil;
  SetLength(Reversed, Length(Outline));
  for Index := 0 to High(Outline) do
    Reversed[Index] := Outline[High(Outline) - Index];
  CheckMesh('either way round', Reversed, MeshPolygon(Reversed, SPACING));
end;

procedure TTestMesher.TestTooSmall;
begin
  AssertEquals('two points', 0, Length(MeshPolygon(Polygon([0, 10], [0, 0]), SPACING).Triangles));
  AssertEquals('no area', 0, Length(MeshPolygon(Polygon([0, 10, 20], [0, 0, 0]), SPACING).Triangles));
  // Smaller than the spacing: the outline's own triangles
  AssertEquals('one triangle', 1, Length(MeshPolygon(Polygon([0, 4, 0], [0, 0, 3]), SPACING).Triangles));
end;

procedure TTestMesher.TestLargePiece;
var
  Outline: TVec2Array;
  Mesh: TFlatMesh;
begin
  // About a skirt front: thousands of points
  Outline := ResampleOutline(Polygon([0, 600, 560, 40], [0, 0, 700, 700]), nil, SPACING);
  Mesh := MeshPolygon(Outline, SPACING);
  AssertTrue('many points', Length(Mesh.Points) > 3000);
  CheckMesh('large', Outline, Mesh);
end;

initialization
  RegisterTest(TTestMesher);
end.
