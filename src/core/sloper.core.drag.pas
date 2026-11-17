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

// Dragging points and curve handles: which can follow the mouse, and the
// formulas a drag writes. A drag only changes fields that are plain numbers, so
// anything placed by a formula (@waist/4) keeps its parametric intent and is
// locked. No LCL dependency.
unit Sloper.Core.Drag;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Bezier, Sloper.Core.FormulaLexer, Sloper.Core.Draft, Sloper.Core.Note, Sloper.Core.Pattern,
  Sloper.Core.Units;

const
  // Dragged angles and ratios are rounded to these decimals; a length is
  // rounded in its unit (DRAG_UNIT_DECIMALS)
  DRAG_ANGLE_DECIMALS = 1;
  DRAG_RATIO_DECIMALS = 4;

type
  // A curve's handle: the end of its tangent line, set by an angle and a length.
  // The two handles at a path's inner node share one angle, so the join stays smooth.
  TCurveHandle = record
    EdgeKey: string;
    // Where the handle starts, on the curve, and where its end is
    Anchor, Position: TVec2;
    AngleField, LengthField: string;
    // Added to the field's angle to get the handle's direction: 180 for the
    // handle into a path node, which points back along the tangent
    AngleOffset: double;
  end;
  TCurveHandleArray = array of TCurveHandle;

// Value rounded to Decimals as formula text, without "-0"
function RoundedText(Value: double; Decimals: integer): string;
// Millimetres as text for a length field being dragged: in the unit the field
// is written in, with its suffix (2in stays in inches), or as a plain number
// in the pattern unit
function DraggedLength(Target: TDraftObject; const FieldName: string; Millimetres: double; Units: TMeasureUnit): string;
// True when Point can be dragged: it is not locked, its type moves freely,
// and every field the drag would change is a plain number. Otherwise
// ErrorMessage says why; for a transform copy it names the source and
// transform.
function CanDrag(Pattern: TPattern; Point: TPointObject; out ErrorMessage: string): boolean;
// Sets Point's fields so it lies at Target, or as near as its operation
// allows (a point along an edge stays on the edge). Call inside a document
// change and evaluate afterwards. False, with ErrorMessage, when the point
// cannot be dragged.
function DragPoint(Pattern: TPattern; Point: TPointObject; const Target: TVec2; out ErrorMessage: string): boolean;
// The fields a drag of Point writes; empty when its type cannot be dragged
function DragFields(Point: TPointObject): TStringArray;
// True when a drag changing only FieldName can move Point: it can be dragged
// apart from its other fields, and FieldName is one a drag writes and a
// plain number. Otherwise ErrorMessage says why.
function CanDragField(Pattern: TPattern; Point: TPointObject; const FieldName: string; out ErrorMessage: string): boolean;
// Sets only FieldName so Point comes as near Target as that field allows: x or
// dx moves it across, y or dy up and down, an offset's length along its angle,
// its angle round its base, and a value along its edge. Call inside a
// document change and evaluate afterwards.
function DragPointField(Pattern: TPattern; Point: TPointObject; const FieldName: string; const Target: TVec2;
  out ErrorMessage: string): boolean;
// Where Point would be with FieldName worked out to Value (mm, degrees or a
// ratio, as the field takes it) and its other fields as they are. False for a
// field that does not place the point.
function FieldPosition(Pattern: TPattern; Point: TPointObject; const FieldName: string; Value: double; out Position: TVec2): boolean;

type
  TFieldGuideKind = (fgNone, fgLine, fgCircle);

  // The path a drag of one field keeps the point on, to draw while dragging
  TFieldGuide = record
    Kind: TFieldGuideKind;
    // A line through Start towards Finish, drawn past both; or a circle
    Start, Finish: TVec2;
    Centre: TVec2;
    Radius: double;
  end;

// None for a value along an edge, whose edge is already drawn
function FieldGuide(Pattern: TPattern; Point: TPointObject; const FieldName: string): TFieldGuide;

// True when the note is not locked and its offset, or a free note's place, is plain numbers
function CanDragNote(Note: TNoteObject; out ErrorMessage: string): boolean;
// Sets the note's offset, or a free note's place, so its top left lies at
// Target. Call inside a document change and evaluate afterwards.
function DragNote(Pattern: TPattern; Note: TNoteObject; const Target: TVec2; out ErrorMessage: string): boolean;
// The handles of a curve or curve path, as computed; empty for other edges,
// and for one not computed. A split part follows its source and has none.
function CurveHandles(Edge: TEdgeObject): TCurveHandleArray;
// True when the edge is not locked and both of the handle's fields are plain numbers
function CanDragHandle(Edge: TEdgeObject; const Handle: TCurveHandle; out ErrorMessage: string): boolean;
// Sets the handle's angle and length so its end lies at Target. At the anchor
// the length is 0 and the angle is kept. Call inside a document change and
// evaluate afterwards.
function DragHandle(Pattern: TPattern; Edge: TEdgeObject; const Handle: TCurveHandle; const Target: TVec2;
  out ErrorMessage: string): boolean;

resourcestring
  rsDragFormula = '%s is placed by a formula; change it in its properties';
  rsDragLocked = '%s is locked; unlock it to move it';
  rsDragPlaced = '%s is placed by other objects and cannot be dragged';
  // A_r1 follows A (Move Copy 'Back'). Edit A to change it.
  rsDragCopy = '%0:s follows %1:s (%2:s ''%3:s''). Edit %1:s to change it.';
  rsDragHandleFormula = 'This handle of %s is set by a formula; change it in its properties';

implementation

uses
  Math, Sloper.Core.Evaluator, Sloper.Core.JSON, Sloper.Core.Transform;

function RoundedText(Value: double; Decimals: integer): string;
var
  Scale, Rounded: double;
begin
  Scale := IntPower(10, Decimals);
  Rounded := Round(Value * Scale) / Scale;
  // No "-0"
  if Rounded = 0 then
    Rounded := 0;
  Result := FormatJSONFloat(Rounded);
end;

function DraggedLength(Target: TDraftObject; const FieldName: string; Millimetres: double; Units: TMeasureUnit): string;
var
  Suffix: TNumberSuffix;
begin
  Suffix := Target.Field(FieldName).LiteralSuffix;
  // TNumberSuffix follows TMeasureUnit after nsNone
  if Suffix <> nsNone then
    Units := TMeasureUnit(Ord(Suffix) - 1);
  Result := RoundLengthFormulaText(Millimetres, Units) + NUMBER_SUFFIX_NAMES[Suffix];
end;

function DragFields(Point: TPointObject): TStringArray;
begin
  Result := nil;
  if Point is TFreePoint then
    Result := ['x', 'y']
  else if Point is TOffsetPoint then
  begin
    if TOffsetPoint(Point).Mode = omPolar then
      Result := ['length', 'angle']
    else
      Result := ['dx', 'dy'];
  end
  else if Point is TAlongEdgePoint then
    Result := ['value'];
end;

// Empty when Point is not a copy, or its source or transform is gone
function CopyRefusal(Pattern: TPattern; Point: TPointObject): string;
var
  Source, Transform: TEvalNode;
begin
  Result := '';
  if not (Point is TPointCopy) then
    Exit;
  Source := Pattern.FindNode(TPointCopy(Point).Source);
  Transform := Pattern.FindNode(TPointCopy(Point).TransformKey);
  if Assigned(Source) and (Transform is TTransformObject) then
    Result := Format(rsDragCopy, [Point.DisplayName, Source.DisplayName, TransformCommandName(TTransformObject(Transform).Kind),
      Transform.DisplayName]);
end;

function CanDrag(Pattern: TPattern; Point: TPointObject; out ErrorMessage: string): boolean;
var
  FieldName: string;
  Fields: TStringArray;
begin
  if Pattern.IsLocked(Point) then
  begin
    ErrorMessage := Format(rsDragLocked, [Point.DisplayName]);
    Exit(False);
  end;
  ErrorMessage := CopyRefusal(Pattern, Point);
  if ErrorMessage <> '' then
    Exit(False);
  Fields := DragFields(Point);
  if Length(Fields) = 0 then
  begin
    ErrorMessage := Format(rsDragPlaced, [Point.DisplayName]);
    Exit(False);
  end;
  for FieldName in Fields do
    if not Point.Field(FieldName).IsLiteral then
    begin
      ErrorMessage := Format(rsDragFormula, [Point.DisplayName]);
      Exit(False);
    end;
  Result := True;
end;

function SetFields(Pattern: TPattern; Target: TDraftObject; const Names, Texts: array of string; out ErrorMessage: string): boolean;
var
  Index: integer;
begin
  for Index := 0 to High(Names) do
    if not Pattern.SetFormula(Target, Names[Index], Texts[Index]) then
    begin
      ErrorMessage := Pattern.LastError;
      Exit(False);
    end;
  Result := True;
end;

function CanDragNote(Note: TNoteObject; out ErrorMessage: string): boolean;
var
  FieldName: string;
begin
  if Note.Locked then
  begin
    ErrorMessage := Format(rsDragLocked, [Note.DisplayName]);
    Exit(False);
  end;
  ErrorMessage := '';
  for FieldName in Note.PlaceFields do
    if not Note.Field(FieldName).IsLiteral then
    begin
      ErrorMessage := Format(rsDragFormula, [Note.DisplayName]);
      Exit(False);
    end;
  Result := True;
end;

function DragNote(Pattern: TPattern; Note: TNoteObject; const Target: TVec2; out ErrorMessage: string): boolean;
var
  Fields: TStringArray;
  Offset: TVec2;
begin
  if not CanDragNote(Note, ErrorMessage) then
    Exit(False);
  Fields := Note.PlaceFields;
  Offset := Target - Note.AnchorPosition;
  if Note.Anchor = naFree then
    Offset := Target;
  Result := SetFields(Pattern, Note, Fields, [DraggedLength(Note, Fields[0], Offset.X, Pattern.Units), DraggedLength(Note, Fields[1], Offset.Y, Pattern.Units)],
    ErrorMessage);
end;

function DragPoint(Pattern: TPattern; Point: TPointObject; const Target: TVec2; out ErrorMessage: string): boolean;
var
  BaseNode: TEvalNode;
  Base: TVec2;
  Along: TAlongEdgePoint;
  Edge: TEdgeObject;
  Position, Offset, Distance, EdgeLength: double;
begin
  if not CanDrag(Pattern, Point, ErrorMessage) then
    Exit(False);
  if Point is TFreePoint then
    Exit(SetFields(Pattern, Point, ['x', 'y'],
      [DraggedLength(Point, 'x', Target.X, Pattern.Units), DraggedLength(Point, 'y', Target.Y, Pattern.Units)], ErrorMessage));

  if Point is TOffsetPoint then
  begin
    BaseNode := Pattern.FindNode(TOffsetPoint(Point).Base);
    Base := TPointObject(BaseNode).Position;
    if TOffsetPoint(Point).Mode = omPolar then
      Exit(SetFields(Pattern, Point, ['length', 'angle'],
        [DraggedLength(Point, 'length', Sloper.Core.Geometry.Distance(Base, Target), Pattern.Units),
        RoundedText(AngleBetween(Base, Target), DRAG_ANGLE_DECIMALS)], ErrorMessage));
    Exit(SetFields(Pattern, Point, ['dx', 'dy'],
      [DraggedLength(Point, 'dx', Target.X - Base.X, Pattern.Units), DraggedLength(Point, 'dy', Target.Y - Base.Y, Pattern.Units)],
      ErrorMessage));
  end;

  // Along an edge: the nearest place on the edge
  Along := TAlongEdgePoint(Point);
  Edge := TEdgeObject(Pattern.FindNode(Along.Edge));
  Edge.Locate(Target, Position, Offset);
  EdgeLength := Edge.Length;
  if Along.FromEnd then
    Distance := EdgeLength - Position
  else
    Distance := Position;
  if Along.Mode = amLength then
    Result := SetFields(Pattern, Point, ['value'], [DraggedLength(Point, 'value', Distance, Pattern.Units)], ErrorMessage)
  else if EdgeLength > 0 then
    Result := SetFields(Pattern, Point, ['value'], [RoundedText(Distance / EdgeLength, DRAG_RATIO_DECIMALS)], ErrorMessage)
  else
    Result := True;
end;

function CanDragField(Pattern: TPattern; Point: TPointObject; const FieldName: string; out ErrorMessage: string): boolean;
var
  Fields: TStringArray;
  Known: string;
  Found: boolean;
begin
  if Pattern.IsLocked(Point) then
  begin
    ErrorMessage := Format(rsDragLocked, [Point.DisplayName]);
    Exit(False);
  end;
  ErrorMessage := CopyRefusal(Pattern, Point);
  if ErrorMessage <> '' then
    Exit(False);
  Fields := DragFields(Point);
  Found := False;
  for Known in Fields do
    Found := Found or (Known = FieldName);
  if not Found then
  begin
    ErrorMessage := Format(rsDragPlaced, [Point.DisplayName]);
    Exit(False);
  end;
  if not Point.Field(FieldName).IsLiteral then
  begin
    ErrorMessage := Format(rsDragFormula, [Point.DisplayName]);
    Exit(False);
  end;
  Result := True;
end;

function OffsetBase(Pattern: TPattern; Point: TOffsetPoint): TVec2;
begin
  Result := TPointObject(Pattern.FindNode(Point.Base)).Position;
end;

// The unit vector of an offset point's current angle; to the right when it
// sits on its base
function OffsetDirection(Pattern: TPattern; Point: TOffsetPoint): TVec2;
var
  Base: TVec2;
begin
  Base := OffsetBase(Pattern, Point);
  if Sloper.Core.Geometry.Distance(Base, Point.Position) > DEFAULT_TOLERANCE then
    Result := (Point.Position - Base).Normalized
  else
    Result := Vec2(1, 0);
end;

function DragPointField(Pattern: TPattern; Point: TPointObject; const FieldName: string; const Target: TVec2;
  out ErrorMessage: string): boolean;
var
  Base: TVec2;
begin
  if not CanDragField(Pattern, Point, FieldName, ErrorMessage) then
    Exit(False);
  if Point is TAlongEdgePoint then
    Exit(DragPoint(Pattern, Point, Target, ErrorMessage));
  if Point is TFreePoint then
  begin
    if FieldName = 'x' then
      Exit(SetFields(Pattern, Point, ['x'], [DraggedLength(Point, 'x', Target.X, Pattern.Units)], ErrorMessage));
    Exit(SetFields(Pattern, Point, ['y'], [DraggedLength(Point, 'y', Target.Y, Pattern.Units)], ErrorMessage));
  end;
  Base := OffsetBase(Pattern, TOffsetPoint(Point));
  case FieldName of
    'dx': Result := SetFields(Pattern, Point, ['dx'], [DraggedLength(Point, 'dx', Target.X - Base.X, Pattern.Units)], ErrorMessage);
    'dy': Result := SetFields(Pattern, Point, ['dy'], [DraggedLength(Point, 'dy', Target.Y - Base.Y, Pattern.Units)], ErrorMessage);
    'length': Result := SetFields(Pattern, Point, ['length'],
        [DraggedLength(Point, 'length', Dot(Target - Base, OffsetDirection(Pattern, TOffsetPoint(Point))), Pattern.Units)], ErrorMessage);
    else
      if Sloper.Core.Geometry.Distance(Base, Target) <= DEFAULT_TOLERANCE then
        Result := True
      else
        Result := SetFields(Pattern, Point, ['angle'], [RoundedText(AngleBetween(Base, Target), DRAG_ANGLE_DECIMALS)], ErrorMessage);
  end;
end;

function FieldPosition(Pattern: TPattern; Point: TPointObject; const FieldName: string; Value: double; out Position: TVec2): boolean;
var
  Base, First, Last: TVec2;
  Edge: TEvalNode;
  Along: TAlongEdgePoint;
  EdgeLength, DistanceAlong: double;
begin
  Position := Point.Position;
  Result := Point.HasResult;
  if not Result then
    Exit;
  if Point is TFreePoint then
  begin
    if FieldName = 'x' then
      Position.X := Value
    else if FieldName = 'y' then
      Position.Y := Value
    else
      Result := False;
  end
  else if Point is TOffsetPoint then
  begin
    Base := OffsetBase(Pattern, TOffsetPoint(Point));
    case FieldName of
      'dx': Position.X := Base.X + Value;
      'dy': Position.Y := Base.Y + Value;
      'length': Position := Base + OffsetDirection(Pattern, TOffsetPoint(Point)) * Value;
      'angle': Position := PolarPoint(Base, Sloper.Core.Geometry.Distance(Base, Point.Position), Value);
      else
        Result := False;
    end;
  end
  else if (Point is TAlongEdgePoint) and (FieldName = 'value') then
  begin
    Along := TAlongEdgePoint(Point);
    Edge := Pattern.FindNode(Along.Edge);
    if not (Edge is TEdgeObject) or not Edge.HasResult then
      Exit(False);
    EdgeLength := TEdgeObject(Edge).Length;
    DistanceAlong := Value;
    if Along.Mode = amRatio then
      DistanceAlong := Value * EdgeLength;
    if Along.FromEnd then
      DistanceAlong := EdgeLength - DistanceAlong;
    Position := TEdgeObject(Edge).PointAtLength(EnsureRange(DistanceAlong, 0, EdgeLength));
  end
  else if (Point is TBetweenPoint) and (FieldName = 'value') then
  begin
    First := TPointObject(Pattern.FindNode(TBetweenPoint(Point).PointA)).Position;
    Last := TPointObject(Pattern.FindNode(TBetweenPoint(Point).PointB)).Position;
    if TBetweenPoint(Point).Mode = amRatio then
      Position := Lerp(First, Last, Value)
    else if Sloper.Core.Geometry.Distance(First, Last) > DEFAULT_TOLERANCE then
      Position := First + (Last - First).Normalized * Value
    else
      Result := False;
  end
  else
    Result := False;
end;

function FieldGuide(Pattern: TPattern; Point: TPointObject; const FieldName: string): TFieldGuide;
var
  Base: TVec2;
begin
  Result := Default(TFieldGuide);
  if not Point.HasResult then
    Exit;
  Result.Start := Point.Position;
  case FieldName of
    'x', 'dx':
    begin
      Result.Kind := fgLine;
      Result.Finish := Point.Position + Vec2(1, 0);
    end;
    'y', 'dy':
    begin
      Result.Kind := fgLine;
      Result.Finish := Point.Position + Vec2(0, 1);
    end;
  end;
  if not (Point is TOffsetPoint) or (TOffsetPoint(Point).Mode <> omPolar) then
    Exit;
  Base := OffsetBase(Pattern, TOffsetPoint(Point));
  if FieldName = 'length' then
  begin
    Result.Kind := fgLine;
    Result.Start := Base;
    Result.Finish := Base + OffsetDirection(Pattern, TOffsetPoint(Point));
  end
  else if FieldName = 'angle' then
  begin
    Result.Kind := fgCircle;
    Result.Centre := Base;
    Result.Radius := Sloper.Core.Geometry.Distance(Base, Point.Position);
  end;
end;

function MakeHandle(Edge: TEdgeObject; const Anchor, Position: TVec2; const AngleField, LengthField: string;
  AngleOffset: double): TCurveHandle;
begin
  Result.EdgeKey := Edge.Key;
  Result.Anchor := Anchor;
  Result.Position := Position;
  Result.AngleField := AngleField;
  Result.LengthField := LengthField;
  Result.AngleOffset := AngleOffset;
end;

function CurveHandles(Edge: TEdgeObject): TCurveHandleArray;
var
  Index: integer;
  Curve: TCubicBezier;
  Node, NextNode: string;
begin
  Result := nil;
  if not Edge.HasResult or (Length(Edge.Segments) = 0) then
    Exit;
  if Edge is TCurveObject then
  begin
    Curve := TCurveObject(Edge).Curve;
    Result := [MakeHandle(Edge, Curve.P0, Curve.P1, 'angle1', 'length1', 0), MakeHandle(Edge, Curve.P3, Curve.P2, 'angle2', 'length2', 0)];
  end
  else if Edge is TCurvePathObject then
  begin
    SetLength(Result, 2 * Length(Edge.Segments));
    for Index := 0 to High(Edge.Segments) do
    begin
      Curve := Edge.Segments[Index].Curve;
      Node := 'node' + IntToStr(Index + 1);
      NextNode := 'node' + IntToStr(Index + 2);
      Result[2 * Index] := MakeHandle(Edge, Curve.P0, Curve.P1, Node + '.angle', Node + '.lengthOut', 0);
      Result[2 * Index + 1] := MakeHandle(Edge, Curve.P3, Curve.P2, NextNode + '.angle', NextNode + '.lengthIn', 180);
    end;
  end;
end;

function CanDragHandle(Edge: TEdgeObject; const Handle: TCurveHandle; out ErrorMessage: string): boolean;
begin
  if Edge.Locked then
  begin
    ErrorMessage := Format(rsDragLocked, [Edge.DisplayName]);
    Exit(False);
  end;
  ErrorMessage := '';
  Result := Edge.Field(Handle.AngleField).IsLiteral and Edge.Field(Handle.LengthField).IsLiteral;
  if not Result then
    ErrorMessage := Format(rsDragHandleFormula, [Edge.DisplayName]);
end;

function DragHandle(Pattern: TPattern; Edge: TEdgeObject; const Handle: TCurveHandle; const Target: TVec2;
  out ErrorMessage: string): boolean;
var
  LengthText: string;
begin
  if not CanDragHandle(Edge, Handle, ErrorMessage) then
    Exit(False);
  LengthText := DraggedLength(Edge, Handle.LengthField, Sloper.Core.Geometry.Distance(Handle.Anchor, Target), Pattern.Units);
  // At the anchor, whatever unit the length is written in
  if LengthText = '0' + NUMBER_SUFFIX_NAMES[Edge.Field(Handle.LengthField).LiteralSuffix] then
    Exit(SetFields(Pattern, Edge, [Handle.LengthField], [LengthText], ErrorMessage));
  Result := SetFields(Pattern, Edge, [Handle.AngleField, Handle.LengthField],
    [RoundedText(NormalizeAngle(AngleBetween(Handle.Anchor, Target) - Handle.AngleOffset), DRAG_ANGLE_DECIMALS), LengthText],
    ErrorMessage);
end;

end.
