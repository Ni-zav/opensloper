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

// Triangle meshes of flat pieces for cloth simulation, which needs evenly
// sized, well shaped triangles: plain ear clipping gives slivers that make
// cloth crease and jitter. The outline is resampled at an even spacing,
// keeping its corners and any points asked for (seam ends); the inside is
// filled with a hexagonal grid of points at the same spacing; the points are
// triangulated by Delaunay's rule (Bowyer-Watson), and an outline edge the
// triangulation misses is split at its middle until it appears, so the
// outline is kept exactly; then the inner points are smoothed. Triangles run
// anticlockwise on screen, so a piece placed by Sloper.Core.DrapePlacement
// faces its right side out. Drafted coordinates, mm. No LCL dependency.
unit Sloper.Core.Mesher;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Piece;

const
  // The spacing of a piece's mesh when nothing else is asked for, in mm
  DEFAULT_MESH_SPACING = 10;
  // Rounds of smoothing the inner points
  DEFAULT_SMOOTHING = 3;

type
  TMeshTriangle = record
    First, Second, Third: integer;
  end;

  TMeshTriangleArray = array of TMeshTriangle;
  TBooleanArray = array of boolean;

  TFlatMesh = record
    Points: TVec2Array;
    Triangles: TMeshTriangleArray;
    // Points[0 .. OutlineCount - 1] are the outline given, in its order; then
    // come the points added to split outline edges, which are on the outline
    // too, then the inner points
    OutlineCount: integer;
    // Every point on the outline, those given and those added to split it
    BoundaryCount: integer;
  end;

// The outline resampled so no step is longer than Spacing: each run between
// kept points is divided evenly. A point is kept when Keep says so (Keep may
// be nil or shorter) or when the outline turns there by more than a corner.
// Closed, without repeating its first point.
function ResampleOutline(const Points: TVec2Array; const Keep: TBooleanArray; Spacing: double): TVec2Array;
// A mesh of the inside of a closed outline, used as it is (resample it first),
// in either direction. Empty when it has fewer than three points or no area.
function MeshPolygon(const Outline: TVec2Array; Spacing: double; Smoothing: integer = DEFAULT_SMOOTHING): TFlatMesh;
// A piece's seam line, opened out on a fold, resampled and meshed
function MeshPiece(Piece: TPieceObject; Spacing: double = DEFAULT_MESH_SPACING): TFlatMesh;
// The area the triangles cover
function MeshArea(const Mesh: TFlatMesh): double;

implementation

uses
  Math, Generics.Collections, Sloper.Core.Numeric, Sloper.Core.DrapePlacement;

const
  // The outline turning by more than this (degrees) at a point keeps it
  CORNER_ANGLE = 20;
  // Inner points closer than this share of the spacing to the outline are left out
  MIN_INNER_DISTANCE_SHARE = 0.5;
  // Outline edges shorter than this share of the spacing are not split again
  MIN_SPLIT_SHARE = 1 / 64;
  // How many times the outline edges are checked and split
  MAX_SPLIT_ROUNDS = 12;
  // A smoothed triangle keeps at least this share of its area before the move
  MIN_KEPT_AREA_SHARE = 0.1;
  // The enclosing triangle reaches this many times the outline's size
  SUPER_TRIANGLE_SCALE = 20;
  // A triangle whose circle covers more cells than this is listed as big
  BIG_CELL_LIMIT = 64;
  // Cells are this many times the spacing
  CELL_SPACINGS = 2;
  // Room for this many triangles at first
  MIN_CAPACITY = 64;

type
  TWorkTriangle = record
    First, Second, Third: integer;
    CentreX, CentreY, RadiusSquared: double;
    Alive: boolean;
  end;

  TEdgeCounts = specialize TDictionary<int64, integer>;

  TIndexArray = array of integer;
  TIndexList = specialize TList<integer>;

  // Bowyer-Watson over a growing point list. A point's cavity is found from a
  // grid of cells, each listing the triangles whose circles reach it; a
  // triangle whose circle covers many cells (those of the enclosing triangle)
  // is listed once as big and always checked.
  TDelaunay = class
  private
    FPoints: TVec2Array;
    // Points in use in FPoints, which grows by doubling
    FPointCount: integer;
    FTriangles: array of TWorkTriangle;
    // Triangles in use in FTriangles and FSeen, which grow by doubling
    FTriangleCount: integer;
    FOrigin: TVec2;
    FCellSize: double;
    FColumns, FRows: integer;
    FCells: array of TIndexList;
    FBig: TIndexList;
    // The insertion that last looked at each triangle, so it is looked at once
    FSeen: TIndexArray;
    FStamp: integer;
    // Kept between insertions, to spare allocations
    FBoundary: TEdgeCounts;
    FCavity: TIndexList;
    procedure AddTriangle(First, Second, Third: integer);
    function CellOf(const APoint: TVec2; out Column, Row: integer): boolean;
    procedure Consider(Index: integer; const APoint: TVec2);
  public
    constructor Create(const Low, High: TVec2; CellSize: double);
    destructor Destroy; override;
    // Adds the point and returns its index
    function Insert(const APoint: TVec2): integer;
    function HasEdge(Edges: TEdgeCounts; From, Onto: integer): boolean;
    function Edges: TEdgeCounts;
    function Point(Index: integer): TVec2;
    property PointCount: integer read FPointCount;
  end;

function EdgeKey(From, Onto: integer): int64;
begin
  if From > Onto then
    Result := int64(Onto) shl 32 or int64(From)
  else
    Result := int64(From) shl 32 or int64(Onto);
end;

constructor TDelaunay.Create(const Low, High: TVec2; CellSize: double);
var
  Middle: TVec2;
  Size: double;
begin
  FCellSize := Max(CellSize, EPSILON);
  FOrigin := Low;
  FColumns := Max(1, Ceil((High.X - Low.X) / FCellSize) + 1);
  FRows := Max(1, Ceil((High.Y - Low.Y) / FCellSize) + 1);
  SetLength(FCells, FColumns * FRows);
  FBig := TIndexList.Create;
  FBoundary := TEdgeCounts.Create;
  FCavity := TIndexList.Create;
  Middle := (Low + High) * 0.5;
  Size := Max(Max(High.X - Low.X, High.Y - Low.Y), 1) * SUPER_TRIANGLE_SCALE;
  FPoints := [Vec2(Middle.X - Size, Middle.Y - Size), Vec2(Middle.X + Size, Middle.Y - Size), Vec2(Middle.X, Middle.Y + Size)];
  FPointCount := 3;
  AddTriangle(0, 1, 2);
end;

destructor TDelaunay.Destroy;
var
  Index: integer;
begin
  for Index := 0 to High(FCells) do
    FreeAndNil(FCells[Index]);
  FreeAndNil(FBig);
  FreeAndNil(FBoundary);
  FreeAndNil(FCavity);
  inherited Destroy;
end;

function TDelaunay.CellOf(const APoint: TVec2; out Column, Row: integer): boolean;
begin
  Column := Floor((APoint.X - FOrigin.X) / FCellSize);
  Row := Floor((APoint.Y - FOrigin.Y) / FCellSize);
  Result := (Column >= 0) and (Column < FColumns) and (Row >= 0) and (Row < FRows);
end;

procedure TDelaunay.AddTriangle(First, Second, Third: integer);
var
  Triangle: TWorkTriangle;
  PA, PB, PC: TVec2;
  Denominator, LengthA, LengthB, LengthC, Radius: double;
  Index, FirstColumn, LastColumn, FirstRow, LastRow, Column, Row: integer;
begin
  PA := FPoints[First];
  PB := FPoints[Second];
  PC := FPoints[Third];
  Triangle.First := First;
  Triangle.Second := Second;
  Triangle.Third := Third;
  Triangle.Alive := True;
  Denominator := 2 * (PA.X * (PB.Y - PC.Y) + PB.X * (PC.Y - PA.Y) + PC.X * (PA.Y - PB.Y));
  LengthA := Sqr(PA.X) + Sqr(PA.Y);
  LengthB := Sqr(PB.X) + Sqr(PB.Y);
  LengthC := Sqr(PC.X) + Sqr(PC.Y);
  if Abs(Denominator) < EPSILON then
  begin
    // A flat triangle: its circle takes in everything, so the next point clears it
    Triangle.CentreX := PA.X;
    Triangle.CentreY := PA.Y;
    Triangle.RadiusSquared := Infinity;
  end
  else
  begin
    Triangle.CentreX := (LengthA * (PB.Y - PC.Y) + LengthB * (PC.Y - PA.Y) + LengthC * (PA.Y - PB.Y)) / Denominator;
    Triangle.CentreY := (LengthA * (PC.X - PB.X) + LengthB * (PA.X - PC.X) + LengthC * (PB.X - PA.X)) / Denominator;
    Triangle.RadiusSquared := Sqr(PA.X - Triangle.CentreX) + Sqr(PA.Y - Triangle.CentreY);
  end;
  Index := FTriangleCount;
  if Index >= Length(FTriangles) then
  begin
    SetLength(FTriangles, Max(MIN_CAPACITY, 2 * Length(FTriangles)));
    SetLength(FSeen, Length(FTriangles));
  end;
  FTriangles[Index] := Triangle;
  FSeen[Index] := 0;
  Inc(FTriangleCount);
  if IsInfinite(Triangle.RadiusSquared) then
  begin
    FBig.Add(Index);
    Exit;
  end;
  Radius := Sqrt(Triangle.RadiusSquared);
  FirstColumn := Max(0, Floor((Triangle.CentreX - Radius - FOrigin.X) / FCellSize));
  LastColumn := Min(FColumns - 1, Floor((Triangle.CentreX + Radius - FOrigin.X) / FCellSize));
  FirstRow := Max(0, Floor((Triangle.CentreY - Radius - FOrigin.Y) / FCellSize));
  LastRow := Min(FRows - 1, Floor((Triangle.CentreY + Radius - FOrigin.Y) / FCellSize));
  if (LastColumn < FirstColumn) or (LastRow < FirstRow) then
    Exit;
  if (LastColumn - FirstColumn + 1) * (LastRow - FirstRow + 1) > BIG_CELL_LIMIT then
  begin
    FBig.Add(Index);
    Exit;
  end;
  for Row := FirstRow to LastRow do
    for Column := FirstColumn to LastColumn do
    begin
      if not Assigned(FCells[Row * FColumns + Column]) then
        FCells[Row * FColumns + Column] := TIndexList.Create;
      FCells[Row * FColumns + Column].Add(Index);
    end;
end;

procedure TDelaunay.Consider(Index: integer; const APoint: TVec2);
begin
  if (FSeen[Index] = FStamp) or not FTriangles[Index].Alive then
    Exit;
  FSeen[Index] := FStamp;
  if Sqr(APoint.X - FTriangles[Index].CentreX) + Sqr(APoint.Y - FTriangles[Index].CentreY) < FTriangles[Index].RadiusSquared then
    FCavity.Add(Index);
end;

// Drops the dead triangles from a list
procedure Prune(List: TIndexList; const Triangles: array of TWorkTriangle);
var
  Index, Kept: integer;
begin
  if not Assigned(List) then
    Exit;
  Kept := 0;
  for Index := 0 to List.Count - 1 do
    if Triangles[List[Index]].Alive then
    begin
      List[Kept] := List[Index];
      Inc(Kept);
    end;
  List.Count := Kept;
end;

function TDelaunay.Insert(const APoint: TVec2): integer;
var
  Index, Count, Column, Row, Side: integer;
  Pair: specialize TPair<int64, integer>;
  Corners: array[0..2] of integer;
begin
  Result := FPointCount;
  if Result >= Length(FPoints) then
    SetLength(FPoints, Max(MIN_CAPACITY, 2 * Length(FPoints)));
  FPoints[Result] := APoint;
  Inc(FPointCount);
  Inc(FStamp);
  FCavity.Clear;
  // Points outside the grid are never more than the outline's own, which the
  // big list and a full look cover
  if CellOf(APoint, Column, Row) then
  begin
    Prune(FCells[Row * FColumns + Column], FTriangles);
    if Assigned(FCells[Row * FColumns + Column]) then
      for Index in FCells[Row * FColumns + Column] do
        Consider(Index, APoint);
  end
  else
    for Index := 0 to FTriangleCount - 1 do
      Consider(Index, APoint);
  Prune(FBig, FTriangles);
  for Index in FBig do
    Consider(Index, APoint);
  // The cavity's edges seen once are its boundary, kept in the triangles'
  // turning direction
  FBoundary.Clear;
  for Index in FCavity do
  begin
    FTriangles[Index].Alive := False;
    Corners[0] := FTriangles[Index].First;
    Corners[1] := FTriangles[Index].Second;
    Corners[2] := FTriangles[Index].Third;
    for Side := 0 to 2 do
      if FBoundary.TryGetValue(EdgeKey(Corners[(Side + 1) mod 3], Corners[Side]), Count) then
        FBoundary.Remove(EdgeKey(Corners[(Side + 1) mod 3], Corners[Side]))
      else
        FBoundary.Add(EdgeKey(Corners[Side], Corners[(Side + 1) mod 3]), Corners[Side]);
  end;
  for Pair in FBoundary do
    AddTriangle(Pair.Value, integer(Pair.Key and $FFFFFFFF) xor integer(Pair.Key shr 32) xor Pair.Value, Result);
end;

function TDelaunay.Point(Index: integer): TVec2;
begin
  Result := FPoints[Index];
end;

function TDelaunay.Edges: TEdgeCounts;
var
  Index: integer;
  Triangle: TWorkTriangle;
begin
  Result := TEdgeCounts.Create;
  for Index := 0 to FTriangleCount - 1 do
  begin
    Triangle := FTriangles[Index];
    if Triangle.Alive then
    begin
      Result.AddOrSetValue(EdgeKey(Triangle.First, Triangle.Second), 1);
      Result.AddOrSetValue(EdgeKey(Triangle.Second, Triangle.Third), 1);
      Result.AddOrSetValue(EdgeKey(Triangle.Third, Triangle.First), 1);
    end;
  end;
end;

function TDelaunay.HasEdge(Edges: TEdgeCounts; From, Onto: integer): boolean;
begin
  Result := Edges.ContainsKey(EdgeKey(From, Onto));
end;

function TurnAt(const Previous, Point, Next: TVec2): double;
var
  Incoming, Outgoing: TVec2;
begin
  Incoming := (Point - Previous).Normalized;
  Outgoing := (Next - Point).Normalized;
  Result := RadToDeg(ArcCos(EnsureRange(Dot(Incoming, Outgoing), -1, 1)));
end;

function ResampleOutline(const Points: TVec2Array; const Keep: TBooleanArray; Spacing: double): TVec2Array;
var
  Count, Index, Start, Next, Step, Pieces, Walk: integer;
  Kept: array of boolean;
  Run: TVec2Array;
  Length, Along, Wanted, Segment: double;
  Found: boolean;
begin
  Result := nil;
  Count := System.Length(Points);
  if (Count < 3) or (Spacing <= 0) then
    Exit(Copy(Points));
  Kept := nil;
  SetLength(Kept, Count);
  Found := False;
  for Index := 0 to Count - 1 do
  begin
    Kept[Index] := ((Index < System.Length(Keep)) and Keep[Index]) or
      (TurnAt(Points[(Index + Count - 1) mod Count], Points[Index], Points[(Index + 1) mod Count]) > CORNER_ANGLE);
    Found := Found or Kept[Index];
  end;
  // A smooth closed outline, such as a circle, starts anywhere
  if not Found then
    Kept[0] := True;
  Start := 0;
  while not Kept[Start] do
    Inc(Start);
  Index := Start;
  repeat
    // The run from this kept point to the next, as a polyline
    Run := [Points[Index]];
    Next := (Index + 1) mod Count;
    while True do
    begin
      System.Insert(Points[Next], Run, System.Length(Run));
      if Kept[Next] then
        Break;
      Next := (Next + 1) mod Count;
    end;
    Length := PolylineLength(Run);
    Pieces := Max(1, Ceil(Length / Spacing - 1e-9));
    System.Insert(Run[0], Result, System.Length(Result));
    Walk := 0;
    Along := 0;
    for Step := 1 to Pieces - 1 do
    begin
      Wanted := Length * Step / Pieces;
      Segment := Distance(Run[Walk], Run[Walk + 1]);
      while (Along + Segment < Wanted) and (Walk < System.High(Run) - 1) do
      begin
        Along := Along + Segment;
        Inc(Walk);
        Segment := Distance(Run[Walk], Run[Walk + 1]);
      end;
      if Segment > EPSILON then
        System.Insert(Lerp(Run[Walk], Run[Walk + 1], (Wanted - Along) / Segment), Result, System.Length(Result))
      else
        System.Insert(Run[Walk], Result, System.Length(Result));
    end;
    Index := Next;
  until Index = Start;
end;

// The outline's edges by grid cell, each listed in the cells within Reach of it
type
  TEdgeGrid = record
    Origin: TVec2;
    CellSize: double;
    Columns, Rows: integer;
    Cells: array of TIndexArray;
  end;

function BuildEdgeGrid(const Outline: TVec2Array; const Low, High: TVec2; Reach: double): TEdgeGrid;
var
  Index, Column, Row, FirstColumn, LastColumn, FirstRow, LastRow: integer;
  Start, Finish: TVec2;
begin
  Result.Origin := Low;
  Result.CellSize := Max(Reach, EPSILON);
  Result.Columns := Max(1, Ceil((High.X - Low.X) / Result.CellSize) + 1);
  Result.Rows := Max(1, Ceil((High.Y - Low.Y) / Result.CellSize) + 1);
  Result.Cells := nil;
  SetLength(Result.Cells, Result.Columns * Result.Rows);
  for Index := 0 to System.High(Outline) do
  begin
    Start := Outline[Index];
    Finish := Outline[(Index + 1) mod Length(Outline)];
    FirstColumn := Max(0, Floor((Min(Start.X, Finish.X) - Reach - Low.X) / Result.CellSize));
    LastColumn := Min(Result.Columns - 1, Floor((Max(Start.X, Finish.X) + Reach - Low.X) / Result.CellSize));
    FirstRow := Max(0, Floor((Min(Start.Y, Finish.Y) - Reach - Low.Y) / Result.CellSize));
    LastRow := Min(Result.Rows - 1, Floor((Max(Start.Y, Finish.Y) + Reach - Low.Y) / Result.CellSize));
    for Row := FirstRow to LastRow do
      for Column := FirstColumn to LastColumn do
        Insert(Index, Result.Cells[Row * Result.Columns + Column], Length(Result.Cells[Row * Result.Columns + Column]));
  end;
end;

function NearOutline(const Grid: TEdgeGrid; const Outline: TVec2Array; const Point: TVec2; Reach: double): boolean;
var
  Column, Row, Index: integer;
  Edge: TLine2;
begin
  Column := EnsureRange(Floor((Point.X - Grid.Origin.X) / Grid.CellSize), 0, Grid.Columns - 1);
  Row := EnsureRange(Floor((Point.Y - Grid.Origin.Y) / Grid.CellSize), 0, Grid.Rows - 1);
  for Index in Grid.Cells[Row * Grid.Columns + Column] do
  begin
    Edge := Line2(Outline[Index], Outline[(Index + 1) mod Length(Outline)]);
    if Distance(Point, Edge.ClosestPoint(Point, False)) < Reach then
      Exit(True);
  end;
  Result := False;
end;

// Where the outline crosses the row at Y, sorted; inside lies between the
// first and second, the third and fourth, and so on
function RowCrossings(const Outline: TVec2Array; Y: double): TDoubleArray;
var
  Index, Sorted: integer;
  Start, Finish: TVec2;
  X, Swap: double;
begin
  Result := nil;
  for Index := 0 to System.High(Outline) do
  begin
    Start := Outline[Index];
    Finish := Outline[(Index + 1) mod Length(Outline)];
    // Half open, so a row through a corner counts it once
    if (Start.Y <= Y) <> (Finish.Y <= Y) then
    begin
      X := Start.X + (Y - Start.Y) / (Finish.Y - Start.Y) * (Finish.X - Start.X);
      Insert(X, Result, Length(Result));
    end;
  end;
  for Index := 1 to System.High(Result) do
  begin
    Swap := Result[Index];
    Sorted := Index - 1;
    while (Sorted >= 0) and (Result[Sorted] > Swap) do
    begin
      Result[Sorted + 1] := Result[Sorted];
      Dec(Sorted);
    end;
    Result[Sorted + 1] := Swap;
  end;
end;

// A hexagonal grid at the spacing over the outline's extent, inside it and
// clear of it
function InnerPoints(const Outline: TVec2Array; Spacing: double): TVec2Array;
var
  Low, High, Point: TVec2;
  RowStep, Reach: double;
  Row, Crossing, Count: integer;
  Crossings: TDoubleArray;
  Grid: TEdgeGrid;
begin
  Result := nil;
  Low := Outline[0];
  High := Outline[0];
  for Point in Outline do
  begin
    Low := Vec2(Min(Low.X, Point.X), Min(Low.Y, Point.Y));
    High := Vec2(Max(High.X, Point.X), Max(High.Y, Point.Y));
  end;
  Reach := Spacing * MIN_INNER_DISTANCE_SHARE;
  Grid := BuildEdgeGrid(Outline, Low, High, Reach);
  RowStep := Spacing * Sqrt(3) / 2;
  Row := 0;
  Count := 0;
  Point.Y := Low.Y + RowStep / 2;
  while Point.Y < High.Y do
  begin
    Crossings := RowCrossings(Outline, Point.Y);
    Crossing := 0;
    Point.X := Low.X + Spacing / 2 * (1 + Ord(Odd(Row)));
    while Point.X < High.X do
    begin
      while (Crossing <= System.High(Crossings)) and (Crossings[Crossing] <= Point.X) do
        Inc(Crossing);
      // An odd number of crossings to the left is inside
      if Odd(Crossing) and not NearOutline(Grid, Outline, Point, Reach) then
      begin
        if Count >= Length(Result) then
          SetLength(Result, Max(MIN_CAPACITY, 2 * Length(Result)));
        Result[Count] := Point;
        Inc(Count);
      end;
      Point.X := Point.X + Spacing;
    end;
    Point.Y := Point.Y + RowStep;
    Inc(Row);
  end;
  SetLength(Result, Count);
end;

function SignedTriangleArea(const First, Second, Third: TVec2): double;
begin
  Result := -Cross(Second - First, Third - First) / 2;
end;

// Moves each inner point towards the middle of its neighbours, unless that
// would fold or squash a triangle round it
procedure Smooth(var Mesh: TFlatMesh; Rounds: integer);
type
  TIntegerList = specialize TList<integer>;
var
  Neighbours: array of array of integer;
  Around: array of TIntegerList;
  Pass, Index, Corner: integer;
  Triangle: TMeshTriangle;
  Moved, Before: TVec2;
  Sum: TVec2;
  Good: boolean;
  Corners: array[0..2] of integer;

  function TriangleArea(const Each: TMeshTriangle): double;
  begin
    Result := SignedTriangleArea(Mesh.Points[Each.First], Mesh.Points[Each.Second], Mesh.Points[Each.Third]);
  end;

  procedure Link(From, Onto: integer);
  var
    Known: integer;
  begin
    for Known in Neighbours[From] do
      if Known = Onto then
        Exit;
    System.Insert(Onto, Neighbours[From], Length(Neighbours[From]));
  end;

var
  Areas: array of double;
  TriangleIndex: integer;
begin
  if Rounds <= 0 then
    Exit;
  Neighbours := nil;
  SetLength(Neighbours, Length(Mesh.Points));
  Around := nil;
  SetLength(Around, Length(Mesh.Points));
  try
    for TriangleIndex := 0 to High(Mesh.Triangles) do
    begin
      Triangle := Mesh.Triangles[TriangleIndex];
      Corners[0] := Triangle.First;
      Corners[1] := Triangle.Second;
      Corners[2] := Triangle.Third;
      for Corner := 0 to 2 do
      begin
        Link(Corners[Corner], Corners[(Corner + 1) mod 3]);
        Link(Corners[Corner], Corners[(Corner + 2) mod 3]);
        if not Assigned(Around[Corners[Corner]]) then
          Around[Corners[Corner]] := TIntegerList.Create;
        Around[Corners[Corner]].Add(TriangleIndex);
      end;
    end;
    Areas := nil;
    SetLength(Areas, Length(Mesh.Triangles));
    for Pass := 1 to Rounds do
      for Index := Mesh.BoundaryCount to High(Mesh.Points) do
      begin
        if (Length(Neighbours[Index]) = 0) or not Assigned(Around[Index]) then
          Continue;
        Sum := Vec2(0, 0);
        for Corner in Neighbours[Index] do
          Sum := Sum + Mesh.Points[Corner];
        Moved := Sum * (1 / Length(Neighbours[Index]));
        Before := Mesh.Points[Index];
        for TriangleIndex in Around[Index] do
          Areas[TriangleIndex] := TriangleArea(Mesh.Triangles[TriangleIndex]);
        Mesh.Points[Index] := Moved;
        Good := True;
        for TriangleIndex in Around[Index] do
          Good := Good and (TriangleArea(Mesh.Triangles[TriangleIndex]) > Areas[TriangleIndex] * MIN_KEPT_AREA_SHARE);
        if not Good then
          Mesh.Points[Index] := Before;
      end;
  finally
    for Index := 0 to High(Around) do
      FreeAndNil(Around[Index]);
  end;
end;

function MeshPolygon(const Outline: TVec2Array; Spacing: double; Smoothing: integer): TFlatMesh;
var
  Ring: TVec2Array;
  Order: array of integer;
  Delaunay: TDelaunay;
  Edges: TEdgeCounts;
  Lowest, Highest, Point: TVec2;
  Index, OuterCount, Remap, Corner: integer;
  Splits: array of integer;
  Triangle: TWorkTriangle;
  Kept: TMeshTriangle;
  Corners: array[0..2] of integer;
  Map: array of integer;
  Inner: TVec2Array;
  Middle: TVec2;

// Splits each outline edge the triangulation misses at its middle, round by
// round, until all are there; Order walks the outline with the splits in
// place
  procedure SplitMissingEdges;
  var
    Pass, Step, Following, Added: integer;
    Missing: boolean;
  begin
    for Pass := 1 to MAX_SPLIT_ROUNDS do
    begin
      FreeAndNil(Edges);
      Edges := Delaunay.Edges;
      Missing := False;
      Step := 0;
      while Step < Length(Order) do
      begin
        Following := (Step + 1) mod Length(Order);
        if not Delaunay.HasEdge(Edges, Order[Step], Order[Following]) and
          (Distance(Delaunay.Point(Order[Step]), Delaunay.Point(Order[Following])) > Spacing * MIN_SPLIT_SHARE) then
        begin
          Added := Delaunay.Insert(Lerp(Delaunay.Point(Order[Step]), Delaunay.Point(Order[Following]), 0.5));
          System.Insert(Added, Order, Step + 1);
          System.Insert(Added, Splits, Length(Splits));
          Missing := True;
          Inc(Step);
        end;
        Inc(Step);
      end;
      if not Missing then
        Exit;
    end;
  end;

begin
  Result := Default(TFlatMesh);
  if (Length(Outline) < 3) or (Abs(SignedArea(Outline)) < EPSILON) or (Spacing <= 0) then
    Exit;
  Ring := Copy(Outline);
  Lowest := Ring[0];
  Highest := Ring[0];
  for Point in Ring do
  begin
    Lowest := Vec2(Min(Lowest.X, Point.X), Min(Lowest.Y, Point.Y));
    Highest := Vec2(Max(Highest.X, Point.X), Max(Highest.Y, Point.Y));
  end;
  Inner := InnerPoints(Ring, Spacing);
  Delaunay := TDelaunay.Create(Lowest, Highest, Spacing * CELL_SPACINGS);
  Edges := nil;
  try
    // The super triangle's corners are 0 to 2; the outline goes in first so its
    // points keep their order after them
    Order := nil;
    Splits := nil;
    for Point in Ring do
      System.Insert(Delaunay.Insert(Point), Order, Length(Order));
    OuterCount := Length(Order);
    SplitMissingEdges;
    for Point in Inner do
      Delaunay.Insert(Point);
    // Inner points can take outline edges away again
    SplitMissingEdges;
    // The points in their new order: the outline given, the splits, the rest;
    // the super triangle's corners are dropped
    Map := nil;
    SetLength(Map, Delaunay.PointCount);
    for Index := 0 to High(Map) do
      Map[Index] := -1;
    Remap := 0;
    for Index := 3 to 3 + OuterCount - 1 do
    begin
      Map[Index] := Remap;
      Inc(Remap);
    end;
    for Index in Splits do
    begin
      Map[Index] := Remap;
      Inc(Remap);
    end;
    for Index := 3 to High(Map) do
      if Map[Index] < 0 then
      begin
        Map[Index] := Remap;
        Inc(Remap);
      end;
    SetLength(Result.Points, Remap);
    for Index := 3 to High(Map) do
      Result.Points[Map[Index]] := Delaunay.Point(Index);
    Result.OutlineCount := OuterCount;
    Result.BoundaryCount := OuterCount + Length(Splits);
    // Inside triangles only, all turned anticlockwise on screen. With every
    // outline edge in the triangulation, a triangle is wholly in or out.
    for Index := 0 to Delaunay.FTriangleCount - 1 do
    begin
      Triangle := Delaunay.FTriangles[Index];
      if not Triangle.Alive or (Triangle.First < 3) or (Triangle.Second < 3) or (Triangle.Third < 3) then
        Continue;
      Corners[0] := Map[Triangle.First];
      Corners[1] := Map[Triangle.Second];
      Corners[2] := Map[Triangle.Third];
      Middle := (Result.Points[Corners[0]] + Result.Points[Corners[1]] + Result.Points[Corners[2]]) * (1 / 3);
      if not PointInPolygon(Middle, Ring) then
        Continue;
      if SignedTriangleArea(Result.Points[Corners[0]], Result.Points[Corners[1]], Result.Points[Corners[2]]) < 0 then
      begin
        Corner := Corners[1];
        Corners[1] := Corners[2];
        Corners[2] := Corner;
      end;
      Kept.First := Corners[0];
      Kept.Second := Corners[1];
      Kept.Third := Corners[2];
      System.Insert(Kept, Result.Triangles, Length(Result.Triangles));
    end;
  finally
    FreeAndNil(Edges);
    FreeAndNil(Delaunay);
  end;
  Smooth(Result, Smoothing);
end;

function MeshPiece(Piece: TPieceObject; Spacing: double): TFlatMesh;
begin
  Result := MeshPolygon(ResampleOutline(PlacedSeamLine(Piece), nil, Spacing), Spacing);
end;

function MeshArea(const Mesh: TFlatMesh): double;
var
  Triangle: TMeshTriangle;
begin
  Result := 0;
  for Triangle in Mesh.Triangles do
    Result := Result + Abs(SignedTriangleArea(Mesh.Points[Triangle.First], Mesh.Points[Triangle.Second], Mesh.Points[Triangle.Third]));
end;

end.
