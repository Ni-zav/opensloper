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

// The cutting line of a piece: its seam line moved outwards by a seam
// allowance that can differ along the way. Clipper2's own offset takes one
// width for a whole path, so the raw offset is built here the way Clipper2
// builds its own, one width per segment, and Clipper2's union then removes
// the loops it leaves in tight concave places. A dart can have a cap: the
// allowance across its opening shaped as the dart folds, so it can be sewn
// into the seam. An edge can have mirrored ends, as a hem's: where it meets
// its neighbour the cutting line is the neighbour's reflected in it, so the
// allowance lies along the neighbour's when it is turned up. No LCL
// dependency.
unit Sloper.Core.SeamAllowance;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Numeric;

type
  // A dart in an outline, by the indices of its points: where the first leg
  // leaves the edge, the apex, and where the second leg comes back to it, in
  // the order the outline runs
  TDartCap = record
    LegStart, Apex, LegEnd: integer;
    // Pressed towards the outline before LegStart, rather than after LegEnd
    TowardsBefore: boolean;
  end;

  TDartCapArray = array of TDartCap;

  // One flag per segment of an outline: the segment is part of an edge whose
  // allowance ends mirror its neighbours' (see OffsetOutline)
  TMirrorFlags = array of boolean;

// Outline is a closed polygon without a repeated last point, either way
// round; Allowances[Index] is the width of the segment leaving
// Outline[Index]. CutLine runs clockwise. False when no line results.
function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; out CutLine: TVec2Array): boolean;
// The same, with a cap at each dart in place of an allowance along its legs:
// the cutting line the edge has with the dart folded closed and pressed to
// one side, opened out again (see FoldDart).
function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; const Caps: TDartCapArray;
  out CutLine: TVec2Array): boolean;
// The same, where a segment flagged in Mirrors meets one that is not at a
// convex corner: the neighbour's cutting line runs on to the flagged
// segment's line, and from there back as its reflection in that line to the
// flagged segment's own cutting line. Turned up along that line, as a hem is,
// the allowance then lies along the neighbour's. At a right angle it is the
// ordinary corner. Mirrors may be empty.
function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; const Caps: TDartCapArray;
  const Mirrors: TMirrorFlags; out CutLine: TVec2Array): boolean;
// The cap's points in the order the outline runs, from over the first leg to
// over the second (see OffsetOutline); empty when it cannot be worked out
function DartCapPoints(const Outline: TVec2Array; const Allowances: TDoubleArray; const Cap: TDartCap): TVec2Array;

implementation

uses
  Math, Clipper, Clipper.Core;

const
  // Clipper2 rounds to this many decimals of a millimetre
  CUT_LINE_DECIMALS = 3;
  // A corner sharper than this, as a multiple of the wider allowance, is cut
  // off rather than running out to a long spike
  MITRE_LIMIT = 4;
  // Sine of the turn below which two segments count as one straight line
  STRAIGHT_TURN = 1e-9;

// Right of the direction of travel on screen: outwards on an anticlockwise path
function Outwards(const Direction: TVec2): TVec2;
begin
  Result := -LeftOf(Direction);
end;

// Adds the offset of one corner to Raw
procedure OffsetVertex(const Vertex, Incoming, Outgoing: TVec2; WidthIn, WidthOut: double; var Raw: TPathD);
var
  Before, After, Mitre: TVec2;
  Turn: double;
  Count: integer;

  procedure Add(const Point: TVec2);
  begin
    Raw[Count].X := Point.X;
    Raw[Count].Y := Point.Y;
    Inc(Count);
  end;

begin
  Count := Length(Raw);
  SetLength(Raw, Count + 3);
  Before := Vertex + Outwards(Incoming) * WidthIn;
  After := Vertex + Outwards(Outgoing) * WidthOut;
  // Positive for a turn to the left on screen; with y down the plain cross
  // product has the opposite sign
  Turn := -Cross(Incoming, Outgoing);
  if Turn > STRAIGHT_TURN then
  begin
    // A convex corner: the two offset lines meet at a point
    Mitre := Before + Incoming * (Cross(After - Before, Outgoing) / Cross(Incoming, Outgoing));
    if Distance(Mitre, Vertex) <= MITRE_LIMIT * Max(WidthIn, WidthOut) then
      Add(Mitre)
    else
    begin
      Add(Before);
      Add(After);
    end;
  end
  else if Turn < -STRAIGHT_TURN then
  begin
    // A concave corner: going through the vertex keeps the winding right, so
    // the union drops the overlap
    Add(Before);
    Add(Vertex);
    Add(After);
  end
  else
  begin
    Add(Before);
    Add(After);
  end;
  SetLength(Raw, Count);
end;

// Where the line through Point along Direction meets the line through
// Origin along Along; False when they are near parallel
function MeetLine(const Point, Direction, Origin, Along: TVec2; out Meeting: TVec2): boolean;
var
  Denominator: double;
begin
  Denominator := Cross(Direction, Along);
  Result := Abs(Denominator) > STRAIGHT_TURN;
  if Result then
    Meeting := Point + Direction * (Cross(Origin - Point, Along) / Denominator);
end;

// The corner where the hem, a segment with mirrored ends, meets its
// neighbour: OnHemLine where the neighbour's cutting line meets the hem's
// line, and OnHemCut where its reflection in the hem's line meets the hem's
// cutting line. False, to use the ordinary corner, when the corner is not convex or the
// lines meet too far out.
function MirrorCorner(const Vertex, Hem, Neighbour: TVec2; HemWidth, NeighbourWidth: double; HemOutgoing: boolean;
  var Raw: TPathD): boolean;
var
  NeighbourStart, HemStart, Reflected, OnHemLine, OnHemCut: TVec2;
  Turn, Limit: double;
  Count: integer;
begin
  if HemOutgoing then
    Turn := -Cross(Neighbour, Hem)
  else
    Turn := -Cross(Hem, Neighbour);
  if Turn <= STRAIGHT_TURN then
    Exit(False);
  NeighbourStart := Vertex + Outwards(Neighbour) * NeighbourWidth;
  HemStart := Vertex + Outwards(Hem) * HemWidth;
  Reflected := Hem * (2 * Dot(Neighbour, Hem)) - Neighbour;
  if not MeetLine(NeighbourStart, Neighbour, Vertex, Hem, OnHemLine) or not MeetLine(OnHemLine, Reflected, HemStart, Hem, OnHemCut) then
    Exit(False);
  Limit := MITRE_LIMIT * Max(HemWidth, NeighbourWidth);
  if (Distance(OnHemLine, Vertex) > Limit) or (Distance(OnHemCut, Vertex) > Limit) then
    Exit(False);
  Count := Length(Raw);
  SetLength(Raw, Count + 2);
  if HemOutgoing then
  begin
    Raw[Count].X := OnHemLine.X;
    Raw[Count].Y := OnHemLine.Y;
    Raw[Count + 1].X := OnHemCut.X;
    Raw[Count + 1].Y := OnHemCut.Y;
  end
  else
  begin
    Raw[Count].X := OnHemCut.X;
    Raw[Count].Y := OnHemCut.Y;
    Raw[Count + 1].X := OnHemLine.X;
    Raw[Count + 1].Y := OnHemLine.Y;
  end;
  Result := True;
end;

function LargestPath(const Paths: TPathsD): TPathD;
var
  Path: TPathD;
  Size, Best: double;
begin
  Result := nil;
  Best := 0;
  for Path in Paths do
  begin
    Size := Abs(Area(Path));
    if Size > Best then
    begin
      Best := Size;
      Result := Path;
    end;
  end;
end;

// Where the closed path of Points crosses the ray from Ray.P1 through
// Ray.P2, furthest out along it; At counts segments, so 1.5 is halfway along
// the second
function CrossRay(const Points: TVec2Array; const Ray: TLine2; out Point: TVec2; out At: double): boolean;
var
  Index: integer;
  Hit: TIntersection;
  Furthest: double;
begin
  Result := False;
  Furthest := 0;
  for Index := 0 to High(Points) do
    if IntersectLines(Line2(Points[Index], Points[(Index + 1) mod Length(Points)]), Ray, False, True, Hit) and (Hit.T2 > Furthest) then
    begin
      Furthest := Hit.T2;
      Point := Hit.Point;
      At := Index + Hit.T1;
      Result := True;
    end;
end;

// The closed path of Points from one place on it to another, both ends
// included, going up through the points or down
function ArcOf(const Points: TVec2Array; FromAt, ToAt: double; Up: boolean): TVec2Array;
var
  Count, Index, Last: integer;
  Point: TVec2;
begin
  Count := Length(Points);
  Result := nil;
  Insert(Points[Trunc(FromAt)] + (Points[(Trunc(FromAt) + 1) mod Count] - Points[Trunc(FromAt)]) * Frac(FromAt), Result, 0);
  if Up then
  begin
    Index := (Trunc(FromAt) + 1) mod Count;
    Last := (Trunc(ToAt) + 1) mod Count;
    // On one segment with the end ahead there is nothing between
    if not ((Trunc(FromAt) = Trunc(ToAt)) and (ToAt >= FromAt)) then
      repeat
        Insert(Points[Index], Result, Length(Result));
        Index := (Index + 1) mod Count;
      until Index = Last;
  end
  else
  begin
    Index := Trunc(FromAt);
    Last := Trunc(ToAt);
    if not ((Trunc(FromAt) = Trunc(ToAt)) and (ToAt <= FromAt)) then
      repeat
        Insert(Points[Index], Result, Length(Result));
        Index := (Index + Count - 1) mod Count;
      until Index = Last;
  end;
  Point := Points[Trunc(ToAt)] + (Points[(Trunc(ToAt) + 1) mod Count] - Points[Trunc(ToAt)]) * Frac(ToAt);
  Insert(Point, Result, Length(Result));
end;

function Reversed(const Points: TVec2Array): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Points[High(Points) - Index];
end;

function Turned(const Points: TVec2Array; const Pivot: TVec2; Angle: double): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := RotatePoint(Points[Index], Pivot, Angle);
end;

function Mirrored(const Points: TVec2Array; const LineStart, LineEnd: TVec2): TVec2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := MirrorPoint(Points[Index], LineStart, LineEnd);
end;

// The outline round the dart with the dart closed, as far as it matters to
// the cap: from back along the edge before the dart, through the closed
// legs, on along the edge after it, and back to the apex. The side the dart
// is not pressed to turns about the apex onto the other. Widths as for
// OffsetOutline; the way back to the apex has none.
procedure CloseDart(const Outline: TVec2Array; const Allowances: TDoubleArray; const Cap: TDartCap; Turn: double; out Points: TVec2Array;
  out Widths: TDoubleArray);
var
  Count, Index, Budget, Steps: integer;
  Apex, Point: TVec2;
  Reach, Along: double;

  procedure Add(const APoint: TVec2; Width: double);
  begin
    if (Length(Points) > 0) and PointsNear(Points[High(Points)], APoint) then
    begin
      Widths[High(Widths)] := Width;
      Exit;
    end;
    Insert(APoint, Points, Length(Points));
    Insert(Width, Widths, Length(Widths));
  end;

  function Placed(Index: integer; Turning: boolean): TVec2;
  begin
    Result := Outline[Index];
    if Turning then
      Result := RotatePoint(Result, Apex, Turn);
  end;

begin
  Points := nil;
  Widths := nil;
  Count := Length(Outline);
  Apex := Outline[Cap.Apex];
  Reach := 2 * Max(Distance(Apex, Outline[Cap.LegStart]), Distance(Apex, Outline[Cap.LegEnd])) + 4 * MaxValue(Allowances);
  // The points off the dart, shared between the two sides
  Budget := (Cap.LegStart - Cap.LegEnd + Count) mod Count div 2;
  Index := Cap.LegStart;
  Along := 0;
  Steps := 0;
  while (Steps < Budget) and (Along < Reach) do
  begin
    Point := Outline[(Index + Count - 1) mod Count];
    Along := Along + Distance(Point, Outline[Index]);
    Index := (Index + Count - 1) mod Count;
    Inc(Steps);
  end;
  while Index <> Cap.LegStart do
  begin
    Add(Placed(Index, not Cap.TowardsBefore), Allowances[Index]);
    Index := (Index + 1) mod Count;
  end;
  Add(Placed(Cap.LegStart, not Cap.TowardsBefore), Allowances[Cap.LegEnd]);
  Index := Cap.LegEnd;
  Along := 0;
  Steps := 0;
  repeat
    Add(Placed(Index, Cap.TowardsBefore), Allowances[Index]);
    Along := Along + Distance(Outline[Index], Outline[(Index + 1) mod Count]);
    Index := (Index + 1) mod Count;
    Inc(Steps);
  until (Steps > Budget) or (Along >= Reach);
  Widths[High(Widths)] := 0;
  Add(Apex, 0);
end;

// The dart's cap, from over the first leg to over the second, and the fan
// from the apex that covers the dart's opening, the cap and the cutting line
// either side of it as the folded dart has it. Closing the dart turns one
// side about the apex until its leg lies on the other; folded on its centre
// line, the dart then lies over the side it is pressed to. The closed edge's
// cutting line over the folded dart is the cap: reflected in the leg it lies
// on for the half beside that leg, and turned back with the other half.
function FoldDart(const Outline: TVec2Array; const Allowances: TDoubleArray; const Cap: TDartCap; out CapPoints, Fan: TVec2Array): boolean;
var
  Apex, StayLeg, TurnLeg, Centre, FoldCross, LegCross, BeyondCross: TVec2;
  Turn, FoldAt, LegAt, BeyondAt: double;
  Points, Closed, Over, Beyond, Folded, Unturned: TVec2Array;
  Widths: TDoubleArray;
  Up: boolean;
begin
  CapPoints := nil;
  Fan := nil;
  Apex := Outline[Cap.Apex];
  if Cap.TowardsBefore then
  begin
    StayLeg := Outline[Cap.LegStart];
    TurnLeg := Outline[Cap.LegEnd];
  end
  else
  begin
    StayLeg := Outline[Cap.LegEnd];
    TurnLeg := Outline[Cap.LegStart];
  end;
  Turn := AngleBetween(Apex, StayLeg) - AngleBetween(Apex, TurnLeg);
  CloseDart(Outline, Allowances, Cap, Turn, Points, Widths);
  if not OffsetOutline(Points, Widths, Closed) then
    Exit(False);

  // The centre line lies over the side pressed to, as far from the leg as
  // it was; as far the other way is the turned side
  Centre := ((StayLeg - Apex).Normalized + (TurnLeg - Apex).Normalized).Normalized;
  if not CrossRay(Closed, Line2(Apex, Apex + RotatePoint(Centre, Vec2(0, 0), Turn)), FoldCross, FoldAt) or not
    CrossRay(Closed, Line2(Apex, StayLeg), LegCross, LegAt) or not CrossRay(Closed, Line2(Apex, Apex + Centre), BeyondCross, BeyondAt) then
    Exit(False);
  // The short way round, past the leg and on beyond it
  Up := PolylineLength(ArcOf(Closed, FoldAt, LegAt, True)) <= PolylineLength(ArcOf(Closed, FoldAt, LegAt, False));
  Over := ArcOf(Closed, FoldAt, LegAt, Up);
  Beyond := ArcOf(Closed, LegAt, BeyondAt, Up);
  Folded := Mirrored(Reversed(Over), Apex, StayLeg);
  Unturned := Turned(Over, Apex, -Turn);
  CapPoints := Concat(Folded, Copy(Unturned, 1, Length(Unturned) - 1));
  Insert(Apex, Fan, 0);
  Fan := Concat(Fan, Over, Copy(CapPoints, 1, Length(CapPoints) - 1), Copy(Turned(Beyond, Apex, -Turn), 1, Length(Beyond) - 1));
  if not Cap.TowardsBefore then
    CapPoints := Reversed(CapPoints);
  Result := True;
end;

function DartCapPoints(const Outline: TVec2Array; const Allowances: TDoubleArray; const Cap: TDartCap): TVec2Array;
var
  Fan: TVec2Array;
begin
  if not FoldDart(Outline, Allowances, Cap, Result, Fan) then
    Result := nil;
end;

// The fan as a path anticlockwise on screen, as the outline's offset is;
// empty when the cap cannot be worked out
function CapArea(const Outline: TVec2Array; const Allowances: TDoubleArray; const Cap: TDartCap): TPathD;
var
  Index: integer;
  Points, Fan: TVec2Array;
begin
  Result := nil;
  if not FoldDart(Outline, Allowances, Cap, Points, Fan) then
    Exit;
  if SignedArea(Fan) < 0 then
    Fan := Reversed(Fan);
  SetLength(Result, Length(Fan));
  for Index := 0 to High(Fan) do
  begin
    Result[Index].X := Fan[Index].X;
    Result[Index].Y := Fan[Index].Y;
  end;
end;

function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; out CutLine: TVec2Array): boolean;
begin
  Result := OffsetOutline(Outline, Allowances, nil, CutLine);
end;

function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; const Caps: TDartCapArray;
  out CutLine: TVec2Array): boolean;
begin
  Result := OffsetOutline(Outline, Allowances, Caps, nil, CutLine);
end;

function OffsetOutline(const Outline: TVec2Array; const Allowances: TDoubleArray; const Caps: TDartCapArray;
  const Mirrors: TMirrorFlags; out CutLine: TVec2Array): boolean;
var
  Count, Index, Before, Source: integer;
  Points, Directions: TVec2Array;
  Widths, Given: TDoubleArray;
  Mirrored: TMirrorFlags;
  Raw: TPathsD;
  Cleaned, Area: TPathD;
  Swap: TVec2;
  Cap: TDartCap;
begin
  CutLine := nil;
  Count := Length(Outline);
  if Count < 3 then
    Exit(False);
  // A capped dart's legs have no allowance of their own
  Given := Copy(Allowances);
  for Cap in Caps do
  begin
    Index := Cap.LegStart;
    while Index <> Cap.LegEnd do
    begin
      Given[Index] := 0;
      Index := (Index + 1) mod Count;
    end;
  end;
  Points := nil;
  Widths := nil;
  Mirrored := nil;
  SetLength(Points, Count);
  SetLength(Widths, Count);
  SetLength(Mirrored, Count);
  // Anticlockwise, so the segment from a point to the next keeps its width
  // when it runs the other way: reversed, it leaves the point before it
  for Index := 0 to Count - 1 do
  begin
    if SignedArea(Outline) > 0 then
    begin
      Points[Index] := Outline[Index];
      Source := Index;
    end
    else
    begin
      Points[Index] := Outline[Count - 1 - Index];
      Source := (2 * Count - 2 - Index) mod Count;
    end;
    Widths[Index] := Given[Source];
    Mirrored[Index] := (Source < Length(Mirrors)) and Mirrors[Source];
  end;

  Directions := nil;
  SetLength(Directions, Count);
  for Index := 0 to Count - 1 do
    Directions[Index] := (Points[(Index + 1) mod Count] - Points[Index]).Normalized;
  Raw := nil;
  SetLength(Raw, 1);
  for Index := 0 to Count - 1 do
  begin
    Before := (Index + Count - 1) mod Count;
    if Mirrored[Index] and not Mirrored[Before] and MirrorCorner(Points[Index], Directions[Index], Directions[Before],
      Widths[Index], Widths[Before], True, Raw[0]) then
      Continue;
    if Mirrored[Before] and not Mirrored[Index] and MirrorCorner(Points[Index], Directions[Before], Directions[Index],
      Widths[Before], Widths[Index], False, Raw[0]) then
      Continue;
    OffsetVertex(Points[Index], Directions[Before], Directions[Index], Widths[Before], Widths[Index], Raw[0]);
  end;
  for Cap in Caps do
  begin
    Area := CapArea(Outline, Allowances, Cap);
    if Length(Area) = 0 then
      Exit(False);
    SetLength(Raw, Length(Raw) + 1);
    Raw[High(Raw)] := Area;
  end;

  // Clipper counts winding in y-up axes, where a path anticlockwise on screen
  // winds negatively; the loops at concave corners wind the other way
  Cleaned := LargestPath(Union(Raw, frNegative, CUT_LINE_DECIMALS));
  Result := Length(Cleaned) >= 3;
  if not Result then
    Exit;
  SetLength(CutLine, Length(Cleaned));
  for Index := 0 to High(Cleaned) do
    CutLine[Index] := Vec2(Cleaned[Index].X, Cleaned[Index].Y);
  if not IsClockwise(CutLine) then
    for Index := 0 to High(CutLine) div 2 do
    begin
      Swap := CutLine[Index];
      CutLine[Index] := CutLine[High(CutLine) - Index];
      CutLine[High(CutLine) - Index] := Swap;
    end;
end;

end.
