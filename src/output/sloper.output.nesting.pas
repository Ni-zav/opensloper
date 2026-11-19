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

// True-shape nesting for Pack Pieces: each piece goes as near the top, then as far
// left, as its cutting line fits, at least a gap clear of the others. Where
// a piece cannot go is worked out as no-fit polygons, the Minkowski sums of
// the pieces' outlines grown by half the gap, kept for each pair of shapes
// as copies share them.
unit Sloper.Output.Nesting;

{$mode ObjFPC}{$H+}

interface

uses
  Generics.Collections, Clipper.Core, Sloper.Core.Geometry;

type
  // One way round of a shape, with the top left of its own bounds at 0, 0
  TNestOrientation = record
    // Grown by half the gap, in Clipper's whole units
    Grown: TPath64;
    // How far the grown outline reaches below the shape's top, in units
    GrownBottom: int64;
    // The shape itself, in mm
    Width, Height: double;
  end;

  TNestOrientations = array[boolean] of TNestOrientation;
  TNoFitCache = specialize TDictionary<int64, TPaths64>;

  // The shapes to nest, as they lie and a quarter turn from that, and the
  // no-fit polygons worked out between them so far
  TNestShapes = class
  private
    FGap: double;
    FOutlines: array of TVec2Array;
    FOrientations: array of TNestOrientations;
    FNoFits: TNoFitCache;
    function NoFit(Fixed: integer; FixedTurned: boolean; Moving: integer; MovingTurned: boolean): TPaths64;
  public
    constructor Create(AGap: double);
    destructor Destroy; override;
    // The shape of a piece's cutting line as it lies, its bounds' top left at
    // 0, 0; the same outline twice gives the same shape
    function Add(const Outline: TVec2Array): integer;
    function Width(Shape: integer; Turned: boolean): double;
    function Height(Shape: integer; Turned: boolean): double;
  end;

  TNestPlaced = record
    Shape: integer;
    Turned: boolean;
    X, Y: int64;
  end;

  // One sheet being packed, Limit across and Depth down (Infinity for none)
  TNestSheet = class
  private
    FShapes: TNestShapes;
    FLimit, FDepth: double;
    FPlaced: array of TNestPlaced;
    // How far down the grown outlines reach, in units
    FLowest: int64;
    function FindTurned(Shape: integer; Turned: boolean; out X, Y: int64): boolean;
  public
    constructor Create(AShapes: TNestShapes; ALimit, ADepth: double);
    // A shape's top left at X, Y, which others then keep clear of
    procedure Put(Shape: integer; Turned: boolean; X, Y: double);
    // The topmost, then leftmost, spot for the shape's top left, on the drag
    // grid, as it lies or, with Turns, a quarter turn round; it is not put
    function Find(Shape: integer; Turns: boolean; out X, Y: double; out Turned: boolean): boolean;
  end;

implementation

uses
  SysUtils, Math, Clipper, Clipper.Offset;

const
  // Clipper works in whole numbers: hundredths of a millimetre
  UNITS_PER_MM = 100;
  // The window's drag grid, so packed pieces can be lined up by hand, in units
  GRID_UNITS = 50;
  // Mitred corners lie outside the round ones the gap really asks for, so
  // pieces are never closer than it, and are exact along straight edges;
  // past this many times the offset a sharp corner is squared off
  MITRE_LIMIT = 2;
  // A pair of shapes' no-fit polygon is kept under both their indices, the
  // fixed one's in the high half of the key
  KEY_SHIFT = 32;
  // Room for rounding when a shape is exactly as wide as the sheet, in mm
  FIT_TOLERANCE = 1e-6;
  // The grid points round a corner of the free space
  GRID_NEIGHBOURS = 4;

function ToUnits(Value: double): int64;
begin
  Result := Round(Value * UNITS_PER_MM);
end;

function ToPath(const Points: TVec2Array): TPath64;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Point64(ToUnits(Points[Index].X), ToUnits(Points[Index].Y));
end;

function Positive(const Path: TPath64): TPath64;
begin
  if IsPositive(Path) then
    Result := Path
  else
    Result := ReversePath(Path);
end;

// The path of the largest area, the outline itself rather than any loop or
// sliver a self-crossing outline leaves
function Largest(const Paths: TPaths64): TPath64;
var
  Path: TPath64;
begin
  Result := nil;
  for Path in Paths do
    if Abs(Area(Path)) > Abs(Area(Result)) then
      Result := Path;
end;

function Grown(const Outline: TVec2Array; Gap: double): TNestOrientation;
var
  Clean: TPath64;
begin
  Result := Default(TNestOrientation);
  Result.Width := PointsExtent(Outline).X;
  Result.Height := PointsExtent(Outline).Y;
  Clean := Largest(Union(TPaths64.Create(ToPath(Outline)), frNonZero));
  Result.Grown := Positive(Largest(InflatePaths(TPaths64.Create(Clean), Gap / 2 * UNITS_PER_MM, jtMiter, etPolygon, MITRE_LIMIT)));
  Result.GrownBottom := GetBounds(Result.Grown).Bottom;
end;

// The outline a quarter turn round, as a placement's rotation turns it, its
// top left back at 0, 0
function TurnedOutline(const Outline: TVec2Array): TVec2Array;
var
  Index: integer;
  Least: TVec2;
begin
  Result := nil;
  SetLength(Result, Length(Outline));
  Least := Vec2(Infinity, Infinity);
  for Index := 0 to High(Outline) do
  begin
    Result[Index] := RotatePoint(Outline[Index], Vec2(0, 0), 90);
    Least.X := Min(Least.X, Result[Index].X);
    Least.Y := Min(Least.Y, Result[Index].Y);
  end;
  for Index := 0 to High(Result) do
    Result[Index] := Result[Index] - Least;
end;

// Unions Parts pairwise, so each union is of two simple regions rather than
// one of thousands of overlapping ones, which Clipper's sweep is slow at
function UnionAll(Parts: array of TPaths64): TPaths64;
var
  Count, Index: integer;
begin
  Count := Length(Parts);
  if Count = 0 then
    Exit(nil);
  while Count > 1 do
  begin
    for Index := 0 to Count div 2 - 1 do
      Parts[Index] := Union(Parts[2 * Index], Parts[2 * Index + 1], frNonZero);
    if Odd(Count) then
      Parts[Count div 2] := Parts[Count - 1];
    Count := (Count + 1) div 2;
  end;
  Result := Parts[0];
end;

// Every point of Fixed's outline less every point of Moving's: for each edge
// of Fixed, the parallelograms it sweeps with each edge of Moving
function EdgeDifference(const Fixed, Moving: TPath64): TPaths64;
var
  Rows: array of TPaths64;
  Quad: TPath64;
  Row: TPaths64;
  Edge, Other, Last, Previous: integer;
begin
  Rows := nil;
  SetLength(Rows, Length(Fixed));
  Previous := High(Fixed);
  for Edge := 0 to High(Fixed) do
  begin
    Row := nil;
    SetLength(Row, Length(Moving));
    Last := High(Moving);
    for Other := 0 to High(Moving) do
    begin
      Quad := nil;
      SetLength(Quad, 4);
      Quad[0] := Point64(Fixed[Previous].X - Moving[Last].X, Fixed[Previous].Y - Moving[Last].Y);
      Quad[1] := Point64(Fixed[Edge].X - Moving[Last].X, Fixed[Edge].Y - Moving[Last].Y);
      Quad[2] := Point64(Fixed[Edge].X - Moving[Other].X, Fixed[Edge].Y - Moving[Other].Y);
      Quad[3] := Point64(Fixed[Previous].X - Moving[Other].X, Fixed[Previous].Y - Moving[Other].Y);
      Row[Other] := Positive(Quad);
      Last := Other;
    end;
    Rows[Edge] := Union(Row, frNonZero);
    Previous := Edge;
  end;
  Result := UnionAll(Rows);
end;

function SameOutline(const First, Second: TVec2Array): boolean;
var
  Index: integer;
begin
  if Length(First) <> Length(Second) then
    Exit(False);
  for Index := 0 to High(First) do
    if Distance(First[Index], Second[Index]) > 1 / UNITS_PER_MM then
      Exit(False);
  Result := True;
end;

// Whether Point is inside Region, not on its edge: inside an outer path and
// not in a hole, or on a hole's edge
function Inside(const Region: TPaths64; const Point: TPoint64): boolean;
var
  Path: TPath64;
  Depth: integer;
  Where: TPointInPolygonResult;
begin
  Depth := 0;
  for Path in Region do
  begin
    Where := PointInPolygon(Point, Path);
    if IsPositive(Path) then
    begin
      if Where = pipInside then
        Inc(Depth);
    end
    else if Where <> pipOutside then
      Dec(Depth);
  end;
  Result := Depth > 0;
end;

{ TNestShapes }

constructor TNestShapes.Create(AGap: double);
begin
  inherited Create;
  FGap := AGap;
  FNoFits := TNoFitCache.Create;
end;

destructor TNestShapes.Destroy;
begin
  FreeAndNil(FNoFits);
  inherited Destroy;
end;

function TNestShapes.Add(const Outline: TVec2Array): integer;
var
  Ways: TNestOrientations;
begin
  for Result := 0 to High(FOutlines) do
    if SameOutline(FOutlines[Result], Outline) then
      Exit;
  Result := Length(FOutlines);
  Ways[False] := Grown(Outline, FGap);
  Ways[True] := Grown(TurnedOutline(Outline), FGap);
  Insert(Copy(Outline), FOutlines, Result);
  Insert(Ways, FOrientations, Result);
end;

function TNestShapes.Width(Shape: integer; Turned: boolean): double;
begin
  Result := FOrientations[Shape][Turned].Width;
end;

function TNestShapes.Height(Shape: integer; Turned: boolean): double;
begin
  Result := FOrientations[Shape][Turned].Height;
end;

// Where the moving shape's top left cannot go with the fixed one's at 0, 0:
// the Minkowski sum of the fixed outline and the moving one turned through a
// half turn. Clipper sums the edges; the two outlines moved by a corner of
// the other fill in the middle.
function TNestShapes.NoFit(Fixed: integer; FixedTurned: boolean; Moving: integer; MovingTurned: boolean): TPaths64;
var
  Key: int64;
  Still, Mover, Flipped: TPath64;
  Index: integer;
begin
  Key := (int64(2 * Fixed + Ord(FixedTurned)) shl KEY_SHIFT) or (2 * Moving + Ord(MovingTurned));
  if FNoFits.TryGetValue(Key, Result) then
    Exit;
  Still := FOrientations[Fixed][FixedTurned].Grown;
  Mover := FOrientations[Moving][MovingTurned].Grown;
  Result := EdgeDifference(Still, Mover);
  Insert(TranslatePath(Still, -Mover[0].X, -Mover[0].Y), Result, Length(Result));
  Flipped := nil;
  SetLength(Flipped, Length(Mover));
  for Index := 0 to High(Mover) do
    Flipped[Index] := Point64(Still[0].X - Mover[Index].X, Still[0].Y - Mover[Index].Y);
  Insert(Flipped, Result, Length(Result));
  Result := Union(Result, frNonZero);
  FNoFits.Add(Key, Result);
end;

{ TNestSheet }

constructor TNestSheet.Create(AShapes: TNestShapes; ALimit, ADepth: double);
begin
  inherited Create;
  FShapes := AShapes;
  FLimit := ALimit;
  FDepth := ADepth;
end;

procedure TNestSheet.Put(Shape: integer; Turned: boolean; X, Y: double);
var
  Placed: TNestPlaced;
begin
  Placed.Shape := Shape;
  Placed.Turned := Turned;
  Placed.X := ToUnits(X);
  Placed.Y := ToUnits(Y);
  Insert(Placed, FPlaced, Length(FPlaced));
  FLowest := Max(FLowest, Placed.Y + FShapes.FOrientations[Shape][Turned].GrownBottom);
end;

// Free space is what the sheet leaves for the top left less every no-fit
// polygon. Its topmost, then leftmost, corner is the best spot; that is moved
// to a grid point near it, which must still be free.
function TNestSheet.FindTurned(Shape: integer; Turned: boolean; out X, Y: int64): boolean;
var
  Way: TNestOrientation;
  Placed: TNestPlaced;
  Blocked, Room: TPaths64;
  Path: TPath64;
  Corners: array of TPoint64;
  Corner, Spot: TPoint64;
  MostX, MostY: int64;
  Index, Step: integer;

// Higher on the sheet first, then further left
  function Before(const First, Second: TPoint64): boolean;
  begin
    if First.Y <> Second.Y then
      Exit(First.Y < Second.Y);
    Result := First.X < Second.X;
  end;

  function IsFree(const Point: TPoint64): boolean;
  begin
    Result := (Point.X >= 0) and (Point.X <= MostX) and (Point.Y >= 0) and (Point.Y <= MostY) and not Inside(Blocked, Point);
  end;

  function Floored(Value: int64): int64;
  begin
    Result := Floor64(Value / GRID_UNITS) * GRID_UNITS;
  end;

begin
  Result := False;
  X := 0;
  Y := 0;
  Way := FShapes.FOrientations[Shape][Turned];
  MostX := Floor64((FLimit - Way.Width + FIT_TOLERANCE) * UNITS_PER_MM);
  if IsInfinite(FDepth) then
    // Below everything there is always room
    MostY := FLowest - GetBounds(Way.Grown).Top + 2 * GRID_UNITS
  else
    MostY := Floor64((FDepth - Way.Height + FIT_TOLERANCE) * UNITS_PER_MM);
  if (MostX < 0) or (MostY < 0) then
    Exit;
  Blocked := nil;
  for Placed in FPlaced do
    Blocked := Concat(Blocked, TranslatePaths(FShapes.NoFit(Placed.Shape, Placed.Turned, Shape, Turned), Placed.X, Placed.Y));
  Blocked := Union(Blocked, frNonZero);
  // A sheet only as wide as the shape leaves a line, which Clipper drops
  Room := Difference(TPaths64.Create(MakePath([-1, -1, MostX + 1, -1, MostX + 1, MostY + 1, -1, MostY + 1])), Blocked, frNonZero);
  Corners := nil;
  for Path in Room do
    Corners := Concat(Corners, Path);
  // Topmost, then leftmost, first
  for Index := 1 to High(Corners) do
  begin
    Corner := Corners[Index];
    Step := Index;
    while (Step > 0) and Before(Corner, Corners[Step - 1]) do
    begin
      Corners[Step] := Corners[Step - 1];
      Dec(Step);
    end;
    Corners[Step] := Corner;
  end;
  for Corner in Corners do
  begin
    // The grid points round the corner: down to the grid, and one step on
    for Index := 0 to GRID_NEIGHBOURS - 1 do
    begin
      Spot.X := Floored(Corner.X) + GRID_UNITS * (Index mod 2);
      Spot.Y := Floored(Corner.Y) + GRID_UNITS * (Index div 2);
      if IsFree(Spot) and (not Result or Before(Spot, Point64(X, Y))) then
      begin
        Result := True;
        X := Spot.X;
        Y := Spot.Y;
      end;
    end;
    if Result then
      Exit;
  end;
end;

function TNestSheet.Find(Shape: integer; Turns: boolean; out X, Y: double; out Turned: boolean): boolean;
var
  FlatX, FlatY, TurnedX, TurnedY: int64;
  Flat, Quarter: boolean;
  FlatBottom, TurnedBottom: int64;
begin
  TurnedX := 0;
  TurnedY := 0;
  Flat := FindTurned(Shape, False, FlatX, FlatY);
  Quarter := Turns and FindTurned(Shape, True, TurnedX, TurnedY);
  Result := Flat or Quarter;
  Turned := False;
  X := 0;
  Y := 0;
  if not Result then
    Exit;
  // By how far down its bottom comes, then how far left; as it lies on a tie
  FlatBottom := FlatY + ToUnits(FShapes.Height(Shape, False));
  TurnedBottom := TurnedY + ToUnits(FShapes.Height(Shape, True));
  Turned := Quarter and (not Flat or (TurnedBottom < FlatBottom) or ((TurnedBottom = FlatBottom) and (TurnedX < FlatX)));
  if Turned then
  begin
    X := TurnedX / UNITS_PER_MM;
    Y := TurnedY / UNITS_PER_MM;
  end
  else
  begin
    X := FlatX / UNITS_PER_MM;
    Y := FlatY / UNITS_PER_MM;
  end;
end;

end.
