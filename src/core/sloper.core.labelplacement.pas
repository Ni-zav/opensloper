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
// Where the names of points, lines and pieces go, so that they cover neither
// notes nor one another (issue #77). Notes stay where they are put; a label
// moves to the first of its places that is clear. The canvas works in screen
// pixels and the draft SVG in mm, both with y down, so nothing here knows the
// unit. No LCL dependency.
unit Sloper.Core.LabelPlacement;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Sloper.Core.Geometry;

type
  TRect2Array = array of TRect2;

  // One label: its size, and the top-left corners it may be put at, best first
  TLabelRequest = record
    Width, Height: double;
    Places: TVec2Array;
  end;

  TLabelRequestArray = array of TLabelRequest;

const
  // How far along a line its name is tried, as fractions of its length,
  // middle first
  LABEL_ALONG_FRACTIONS: array[0..6] of double = (0.5, 0.4, 0.6, 0.3, 0.7, 0.2, 0.8);

// The places round a point, nearest first: above right of it (where a label
// goes when nothing is in the way), below right, above left, below left,
// above, below, right and left, Gap from it, then the same again a line
// further out for each of Rings more
function PlacesAround(const At: TVec2; Width, Height, Gap: double; Rings: integer): TVec2Array;
// For a line's name: round each of the line's places in turn, Along best
// first, with no further rings
function PlacesAlong(const Along: TVec2Array; Width, Height, Gap: double): TVec2Array;
// For a piece's name: TopLeft, then a line further up or down, then half its
// width to either side, for Rings lines each way
function PlacesStacked(const TopLeft: TVec2; Width, Height: double; Rings: integer): TVec2Array;
// The points a line's name is tried at: its middle, then out towards its
// ends, as fractions of its length
function PolylinePlaces(const Line: TVec2Array): TVec2Array;
// Each request's chosen top-left corner, in their order: the first of its
// places that overlaps no obstacle, no label placed before it, and stays
// inside Within when HasWithin; when none does, the one overlapping least.
// Earlier requests get the better places.
function PlaceLabels(const Requests: TLabelRequestArray; const Obstacles: TRect2Array; HasWithin: boolean; const Within: TRect2): TVec2Array;
function Rect2(MinX, MinY, MaxX, MaxY: double): TRect2;
// The square of side 2 Radius round Centre
function RectAround(const Centre: TVec2; Radius: double): TRect2;

implementation

uses
  Math;

const
  // Labels per grid cell side, so a cell holds a few labels
  CELL_LABELS = 4;
  // Most cells along either side of the grid
  MAX_CELLS = 128;

type
  TIntegerArray = array of integer;

  // Rectangles by the grid cells they touch, so that a place is checked only
  // against what is near it
  TRectGrid = record
    Left, Top, CellSize: double;
    Columns, Rows: integer;
    Cells: array of TIntegerArray;
    Rects: TRect2Array;
    Count: integer;
    // The query each rectangle was last counted in, so one spanning several
    // cells counts once
    Seen: TIntegerArray;
    Query: integer;
    procedure Start(const Extent: TRect2; ACellSize: double; Capacity: integer);
    procedure Add(const Rect: TRect2);
    function Overlap(const Rect: TRect2): double;
  end;

function Rect2(MinX, MinY, MaxX, MaxY: double): TRect2;
begin
  Result.MinX := MinX;
  Result.MinY := MinY;
  Result.MaxX := MaxX;
  Result.MaxY := MaxY;
end;

function RectAround(const Centre: TVec2; Radius: double): TRect2;
begin
  Result := Rect2(Centre.X - Radius, Centre.Y - Radius, Centre.X + Radius, Centre.Y + Radius);
end;

function OverlapArea(const First, Second: TRect2): double;
var
  Across, Down: double;
begin
  Across := Min(First.MaxX, Second.MaxX) - Max(First.MinX, Second.MinX);
  Down := Min(First.MaxY, Second.MaxY) - Max(First.MinY, Second.MinY);
  if (Across <= 0) or (Down <= 0) then
    Exit(0);
  Result := Across * Down;
end;

// How much of Rect lies outside Within
function OutsideArea(const Rect, Within: TRect2): double;
begin
  Result := (Rect.MaxX - Rect.MinX) * (Rect.MaxY - Rect.MinY) - OverlapArea(Rect, Within);
end;

procedure Grow(var Extent: TRect2; const Rect: TRect2);
begin
  Extent.MinX := Min(Extent.MinX, Rect.MinX);
  Extent.MinY := Min(Extent.MinY, Rect.MinY);
  Extent.MaxX := Max(Extent.MaxX, Rect.MaxX);
  Extent.MaxY := Max(Extent.MaxY, Rect.MaxY);
end;

function PlacesAround(const At: TVec2; Width, Height, Gap: double; Rings: integer): TVec2Array;
var
  Ring, Count: integer;
  Away: double;

  procedure Put(X, Y: double);
  begin
    Result[Count] := Vec2(X, Y);
    Inc(Count);
  end;

begin
  Result := nil;
  SetLength(Result, 8 * (Rings + 1));
  Count := 0;
  for Ring := 0 to Rings do
  begin
    Away := Gap + Ring * Height;
    Put(At.X + Away, At.Y - Away - Height);
    Put(At.X + Away, At.Y + Away);
    Put(At.X - Away - Width, At.Y - Away - Height);
    Put(At.X - Away - Width, At.Y + Away);
    Put(At.X - Width / 2, At.Y - Away - Height);
    Put(At.X - Width / 2, At.Y + Away);
    Put(At.X + Away, At.Y - Height / 2);
    Put(At.X - Away - Width, At.Y - Height / 2);
  end;
end;

function PlacesAlong(const Along: TVec2Array; Width, Height, Gap: double): TVec2Array;
var
  At: TVec2;
begin
  Result := nil;
  for At in Along do
    Result := Concat(Result, PlacesAround(At, Width, Height, Gap, 0));
end;

function PlacesStacked(const TopLeft: TVec2; Width, Height: double; Rings: integer): TVec2Array;
var
  Ring: integer;
begin
  Result := nil;
  Insert(TopLeft, Result, 0);
  for Ring := 1 to Rings do
  begin
    Insert(Vec2(TopLeft.X, TopLeft.Y - Ring * Height), Result, Length(Result));
    Insert(Vec2(TopLeft.X, TopLeft.Y + Ring * Height), Result, Length(Result));
  end;
  for Ring := 0 to Rings do
  begin
    Insert(Vec2(TopLeft.X - Width / 2, TopLeft.Y + Ring * Height), Result, Length(Result));
    Insert(Vec2(TopLeft.X + Width / 2, TopLeft.Y + Ring * Height), Result, Length(Result));
  end;
end;

function PolylinePointAt(const Line: TVec2Array; Total, Fraction: double): TVec2;
var
  Index: integer;
  Remaining, Step: double;
begin
  Remaining := Total * Fraction;
  for Index := 1 to High(Line) do
  begin
    Step := Distance(Line[Index - 1], Line[Index]);
    if (Step > 0) and (Remaining <= Step) then
      Exit(Lerp(Line[Index - 1], Line[Index], Remaining / Step));
    Remaining := Remaining - Step;
  end;
  Result := Line[High(Line)];
end;

function PolylinePlaces(const Line: TVec2Array): TVec2Array;
var
  Index: integer;
  Total: double;
begin
  Result := nil;
  if Length(Line) = 0 then
    Exit;
  Total := PolylineLength(Line);
  SetLength(Result, Length(LABEL_ALONG_FRACTIONS));
  for Index := 0 to High(LABEL_ALONG_FRACTIONS) do
    Result[Index] := PolylinePointAt(Line, Total, LABEL_ALONG_FRACTIONS[Index]);
end;

{ TRectGrid }

procedure TRectGrid.Start(const Extent: TRect2; ACellSize: double; Capacity: integer);
begin
  Left := Extent.MinX;
  Top := Extent.MinY;
  CellSize := Max(ACellSize, Max(Extent.MaxX - Extent.MinX, Extent.MaxY - Extent.MinY) / MAX_CELLS);
  if CellSize <= 0 then
    CellSize := 1;
  Columns := Floor((Extent.MaxX - Left) / CellSize) + 1;
  Rows := Floor((Extent.MaxY - Top) / CellSize) + 1;
  Cells := nil;
  SetLength(Cells, Columns * Rows);
  // No more than Capacity rectangles are added
  Rects := nil;
  SetLength(Rects, Capacity);
  Seen := nil;
  SetLength(Seen, Capacity);
  Count := 0;
  Query := 0;
end;

procedure TRectGrid.Add(const Rect: TRect2);
var
  Index, Column, Row, Cell: integer;
begin
  Index := Count;
  Inc(Count);
  Rects[Index] := Rect;
  Seen[Index] := -1;
  for Row := EnsureRange(Floor((Rect.MinY - Top) / CellSize), 0, Rows - 1) to EnsureRange(Floor((Rect.MaxY - Top) / CellSize), 0, Rows - 1) do
    for Column := EnsureRange(Floor((Rect.MinX - Left) / CellSize), 0, Columns - 1) to EnsureRange(Floor((Rect.MaxX - Left) / CellSize), 0, Columns - 1) do
    begin
      Cell := Row * Columns + Column;
      Insert(Index, Cells[Cell], Length(Cells[Cell]));
    end;
end;

function TRectGrid.Overlap(const Rect: TRect2): double;
var
  Column, Row, Index: integer;
begin
  Result := 0;
  Inc(Query);
  for Row := EnsureRange(Floor((Rect.MinY - Top) / CellSize), 0, Rows - 1) to EnsureRange(Floor((Rect.MaxY - Top) / CellSize), 0, Rows - 1) do
    for Column := EnsureRange(Floor((Rect.MinX - Left) / CellSize), 0, Columns - 1) to EnsureRange(Floor((Rect.MaxX - Left) / CellSize), 0, Columns - 1) do
      for Index in Cells[Row * Columns + Column] do
        if Seen[Index] <> Query then
        begin
          Seen[Index] := Query;
          Result := Result + OverlapArea(Rect, Rects[Index]);
        end;
end;

function PlaceLabels(const Requests: TLabelRequestArray; const Obstacles: TRect2Array; HasWithin: boolean; const Within: TRect2): TVec2Array;
var
  Grid: TRectGrid;
  Extent, Box, BestBox: TRect2;
  Index, PlaceIndex: integer;
  Found: boolean;
  Cost, BestCost, TotalHeight: double;
  Place: TVec2;
begin
  Result := nil;
  SetLength(Result, Length(Requests));
  if Length(Requests) = 0 then
    Exit;
  // The grid covers every place and obstacle, with cells a few labels high
  Found := False;
  Extent := Default(TRect2);
  TotalHeight := 0;
  for Index := 0 to High(Requests) do
  begin
    TotalHeight := TotalHeight + Requests[Index].Height;
    for Place in Requests[Index].Places do
    begin
      Box := Rect2(Place.X, Place.Y, Place.X + Requests[Index].Width, Place.Y + Requests[Index].Height);
      if Found then
        Grow(Extent, Box)
      else
        Extent := Box;
      Found := True;
    end;
  end;
  for Box in Obstacles do
    if Found then
      Grow(Extent, Box)
    else
    begin
      Extent := Box;
      Found := True;
    end;
  Grid := Default(TRectGrid);
  Grid.Start(Extent, CELL_LABELS * TotalHeight / Length(Requests), Length(Obstacles) + Length(Requests));
  for Box in Obstacles do
    Grid.Add(Box);
  for Index := 0 to High(Requests) do
  begin
    Result[Index] := Vec2(0, 0);
    BestCost := Infinity;
    BestBox := Default(TRect2);
    for PlaceIndex := 0 to High(Requests[Index].Places) do
    begin
      Place := Requests[Index].Places[PlaceIndex];
      Box := Rect2(Place.X, Place.Y, Place.X + Requests[Index].Width, Place.Y + Requests[Index].Height);
      Cost := Grid.Overlap(Box);
      if HasWithin then
        Cost := Cost + OutsideArea(Box, Within);
      if Cost < BestCost then
      begin
        BestCost := Cost;
        BestBox := Box;
        Result[Index] := Place;
        if Cost <= 0 then
          Break;
      end;
    end;
    if Length(Requests[Index].Places) > 0 then
      Grid.Add(BestBox);
  end;
end;

end.
