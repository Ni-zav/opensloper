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

// The extent of what a pattern draws, in model millimetres. Objects that are
// failing count at their last good result; objects never computed do not
// count. No LCL dependency.
unit Sloper.Core.Bounds;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

const
  // The space, in mm, Move Copy leaves between the originals and their copies
  MOVE_ASIDE_GAP = 20;

// Extent of everything shown, notes too unless WithNotes is False; False when
// nothing is
function PatternBounds(Pattern: TPattern; out Bounds: TRect2; WithNotes: boolean = True): boolean;
// Widens Bounds to take in DraftObject. Start with Empty True.
procedure IncludeObject(var Bounds: TRect2; var Empty: boolean; DraftObject: TDraftObject);
// How far Move Copy moves the points and edges in Keys to the right, so the
// copies start beside them with a gap: their width and MOVE_ASIDE_GAP mm, as a
// number in the pattern's unit rounded up to a round one. Other objects in
// Keys are left out; with nothing computed it is the gap alone.
function MoveAsideText(Pattern: TPattern; const Keys: TStringArray): string;
// How far Move Copy moves something Width mm wide, as MoveAsideText works it out
function MoveAsideWidthText(Pattern: TPattern; Width: double): string;

implementation

uses
  Math, Sloper.Core.Evaluator, Sloper.Core.Units, Sloper.Core.Bezier, Sloper.Core.Piece, Sloper.Core.Note, Sloper.Core.TextFields;

procedure Include(var Bounds: TRect2; var Empty: boolean; const Point: TVec2);
begin
  if Empty then
  begin
    Bounds.MinX := Point.X;
    Bounds.MaxX := Point.X;
    Bounds.MinY := Point.Y;
    Bounds.MaxY := Point.Y;
    Empty := False;
    Exit;
  end;
  Bounds.MinX := Min(Bounds.MinX, Point.X);
  Bounds.MaxX := Max(Bounds.MaxX, Point.X);
  Bounds.MinY := Min(Bounds.MinY, Point.Y);
  Bounds.MaxY := Max(Bounds.MaxY, Point.Y);
end;

procedure IncludeObject(var Bounds: TRect2; var Empty: boolean; DraftObject: TDraftObject);
var
  Segment: TEdgeSegment;
  CurveBounds, Box: TRect2;
  Corner: TVec2;
begin
  if not DraftObject.HasResult then
    Exit;
  // Its text as typed, since the fields are not known here
  if DraftObject is TNoteObject then
  begin
    Box := NoteFrame(TNoteObject(DraftObject), Default(TFieldValues));
    Include(Bounds, Empty, Vec2(Box.MinX, Box.MinY));
    Include(Bounds, Empty, Vec2(Box.MaxX, Box.MaxY));
    if TNoteObject(DraftObject).Leader <> nlNone then
      Include(Bounds, Empty, TNoteObject(DraftObject).AnchorPosition);
  end
  else if DraftObject is TPointObject then
    Include(Bounds, Empty, TPointObject(DraftObject).Position)
  else if DraftObject is TPieceObject then
    for Corner in TPieceObject(DraftObject).CutLine do
      Include(Bounds, Empty, Corner)
  else if DraftObject is TEdgeObject then
    for Segment in TEdgeObject(DraftObject).Segments do
      if Segment.Kind = skLine then
      begin
        Include(Bounds, Empty, Segment.Line.P1);
        Include(Bounds, Empty, Segment.Line.P2);
      end
      else
      begin
        CurveBounds := Segment.Curve.Bounds;
        Include(Bounds, Empty, Vec2(CurveBounds.MinX, CurveBounds.MinY));
        Include(Bounds, Empty, Vec2(CurveBounds.MaxX, CurveBounds.MaxY));
      end;
end;

const
  // What Move Copy's distance is rounded up to, in each pattern unit
  MOVE_ASIDE_STEPS: array[TMeasureUnit] of integer = (10, 1, 1);

function MoveAsideText(Pattern: TPattern; const Keys: TStringArray): string;
var
  Key: string;
  Node: TEvalNode;
  Bounds: TRect2;
  Empty: boolean;
  Width: double;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Key in Keys do
  begin
    Node := Pattern.FindNode(Key);
    if (Node is TPointObject) or (Node is TEdgeObject) then
      IncludeObject(Bounds, Empty, TDraftObject(Node));
  end;
  Width := 0;
  if not Empty then
    Width := Bounds.MaxX - Bounds.MinX;
  Result := MoveAsideWidthText(Pattern, Width);
end;

function MoveAsideWidthText(Pattern: TPattern; Width: double): string;
var
  Step: integer;
begin
  Step := MOVE_ASIDE_STEPS[Pattern.Units];
  // Less a hair, so a distance that is already round is not taken up a step
  Result := IntToStr(Ceil((Width + MOVE_ASIDE_GAP) / MILLIMETRES_PER_UNIT[Pattern.Units] / Step - 1e-9) * Step);
end;

function PatternBounds(Pattern: TPattern; out Bounds: TRect2; WithNotes: boolean): boolean;
var
  Index: integer;
  Empty: boolean;
begin
  Bounds := Default(TRect2);
  Empty := True;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if WithNotes or not (Pattern.Objects[Index] is TNoteObject) then
      IncludeObject(Bounds, Empty, Pattern.Objects[Index]);
  Result := not Empty;
end;

end.
