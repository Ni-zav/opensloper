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
// Changing a point's operation, or an edge between a line and a curve, in
// place: the object keeps its ID, name and users, so whatever reads it carries
// on. TPattern's ConvertTo methods call these. No LCL dependency.
unit Sloper.Core.TypeChange;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Draft, Sloper.Core.Pattern;

// Point is freed. Formulas are in stored form. Nil with the reason in the
// pattern's LastError on failure, when Point is left as it was.
function ConvertToFree(Pattern: TPattern; Point: TPointObject; const XText, YText: string): TFreePoint;
function ConvertToBetween(Pattern: TPattern; Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode;
  const Value: string): TBetweenPoint;
function ConvertToAlongEdge(Pattern: TPattern; Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode;
  const Value: string): TAlongEdgePoint;
// Changes Point to the operation Conversion, placed from Inputs: the keys
// POINT_CONVERSION_INPUTS says, in that order. Its numbers are plain, worked
// out from where it is now, so it stays there: a free point at its x and y,
// an offset across and down from the base, or with Mode omPolar a length and
// angle from it, along an edge or between points a
// length from the nearer end or the first point, a compass step at its
// distance from the centre, a projection square to the edge when it is the
// foot of the perpendicular and otherwise at the angle it lies at. Where the
// new operation puts it on an edge, line, circle or crossing, it moves to the
// nearest such place, and is refused when that is more than MAX_CONVERT_MOVE
// away; crossings beyond an edge's ends are used only when nearer. Formulas
// it had are replaced. Refused, with the reason in LastError and Point left
// as it was, for a repeat's point, a copy, a rounded corner's end, a point
// with no place yet, inputs of the wrong kind or with no place, the operation
// and inputs it already has (an offset's mode too), and inputs that read
// Point. Mode is only read for pcOffset. Measure and Origin choose the units
// and end for points along an edge; Measure also applies between points.
function ConvertPoint(Pattern: TPattern; Point: TPointObject; Conversion: TPointConversion; const Inputs: array of string;
  Mode: TOffsetMode = omCartesian; Measure: TPointMeasureMode = pmKeep;
  Origin: TPointMeasureEnd = peKeep): TPointObject;
// What a point becomes, for messages: "an offset point"
function PointConversionName(Conversion: TPointConversion): string;
// Its role and place stay, and a name the user gave it is kept. An arc
// becomes a line between two new points at its ends, offsets from its centre
// by its own formulas. A new curve starts straight, its handles a third of
// the way along. Refused for a circle, a copy, a derived edge, a line whose
// angle a formula reads, and a line a fold follows.
function ConvertToLine(Pattern: TPattern; Edge: TEdgeObject): TLineObject;
function ConvertToCurve(Pattern: TPattern; Edge: TEdgeObject): TCurveObject;
// Carries a curve or curve path on through PointId, as one curve path that
// keeps the edge's ID, name and role. The handles it had stay, but the point
// it ended at turns to run smoothly on to PointId, and the new stretch's
// handles are a third of its length. Refused for any other kind of edge, a
// copy, an edge something uses (its end moves), and the point it ends at.
function ExtendCurve(Pattern: TPattern; Edge: TEdgeObject; const PointId: string): TCurvePathObject;

const
  // What each conversion reads besides the point, in order: P a point, E an edge
  POINT_CONVERSION_INPUTS: array[TPointConversion] of string = ('', 'P', 'E', 'PP', 'EE', 'PE', 'PP', 'PE');
  // What each conversion makes, as the pattern file names its type
  POINT_CONVERSION_TYPES: array[TPointConversion] of string = ('freePoint', 'offsetPoint', 'alongEdgePoint', 'betweenPoint',
    'intersectPoint', 'circleEdgePoint', 'circleCirclePoint', 'projectPoint');
  // The furthest ConvertPoint moves a point onto its new edge, line or crossing (mm)
  MAX_CONVERT_MOVE = 10;

resourcestring
  rsPatternConvertNeeds = 'To become %s, %s needs %s';
  rsPatternConvertNeedsPoint = 'a point to be placed from';
  rsPatternConvertNeedsEdge = 'an edge';
  rsPatternConvertNeedsTwoPoints = 'two points';
  rsPatternConvertNeedsTwoEdges = 'two edges';
  rsPatternConvertNeedsPointEdge = 'a point and an edge';
  rsPatternConvertNeedsNothing = 'nothing else';
  rsPatternConvertCornerPoint = '%s is an end of the rounded corner %s, so its type cannot change';
  rsPatternConvertNoPlace = '%s has no place yet, so its type cannot change';
  rsPatternConvertInputNoPlace = '%s has no place yet, so %s cannot be placed from it';
  rsPatternConvertZeroSpan = 'A ratio needs a length above zero';
  rsPatternConvertRatioOutside = 'The point lies outside the interval for a ratio';
  rsPatternConvertAlready = '%s is already placed that way';
  rsPatternConvertTooFar = '%s is %s from where it would go; move it closer first';
  rsPatternConvertNoCrossing = '%s and %s do not cross';
  rsPatternConvertCircleMisses = 'A circle round %s through %s does not cross %s';
  rsPatternConvertCirclesMiss = 'Circles round %s and %s through %s do not cross';
  rsPatternConvertSamePlace = '%s and %s are in the same place, so there is no line between them';
  rsPatternConvertNameFree = 'a free point';
  rsPatternConvertNameOffset = 'an offset point';
  rsPatternConvertNameAlong = 'a point along an edge';
  rsPatternConvertNameBetween = 'a point between points';
  rsPatternConvertNameIntersect = 'a crossing of two edges';
  rsPatternConvertNameCircleEdge = 'a compass step onto an edge';
  rsPatternConvertNameCircleCircle = 'two compass steps';
  rsPatternConvertNameProject = 'a point projected onto an edge';
  rsPatternNotConvertible = '%s cannot be changed: only lines, curves and arcs can become a line or a curve';
  rsPatternAlreadyLine = '%s is already a line';
  rsPatternAlreadyCurve = '%s is already a curve';
  rsPatternCircleNoEnds = '%s is a whole circle, so it has no ends to join with a line';
  rsPatternOnlyLineToCurve = 'Only a line can become a curve, and %s is an arc';
  rsPatternAngleInUse = '%s reads %s.angle, which only a line has, so it cannot become a curve';
  rsPatternFoldFollows = '%s is the fold of %s, so %s cannot become a curve';
  rsPatternMirrorAxisFollows = '%s is the axis of the mirror %s, so %s cannot become a curve';
  rsPatternNotExtendable = '%s cannot be carried on: only a curve or a curve path can';
  rsPatternExtendInUse = '%s is used by %s, so it cannot be carried on';
  rsPatternExtendSamePoint = '%s already ends at %s';

implementation

uses
  SysUtils, StrUtils, Math, Sloper.Core.Geometry, Sloper.Core.Formula, Sloper.Core.Evaluator, Sloper.Core.Piece,
  Sloper.Core.Transform, Sloper.Core.Units, Sloper.Core.JSON;

const
  // A ratio a conversion writes is rounded to this many places, which moves
  // a point at most 0.05 mm along a 1 m edge
  RATIO_DECIMALS = 4;
  // A converted point this near a place counts as on it (mm): a projection
  // lands on the foot of the perpendicular, and a crossing needs no extension
  CONVERT_SAME_PLACE = 0.05;
  // Angles ConvertPoint writes are rounded to this many decimals
  CONVERT_ANGLE_DECIMALS = 2;
  // The kind of point each conversion makes, to tell when it is that already
  CONVERSION_CLASSES: array[TPointConversion] of TClass = (TFreePoint, TOffsetPoint, TAlongEdgePoint, TBetweenPoint,
    TIntersectPoint, TCircleEdgePoint, TCircleCirclePoint, TProjectPoint);

type
  // How ConvertPoint places the point: where it goes, its fields, and the
  // choices the operation's constructor takes
  TConversionPlan = record
    Target: TVec2;
    Names, Texts: TStringArray;
    FromEnd, ExtendA, ExtendB, Perpendicular: boolean;
    Pick: integer;
    AlongMode: TAlongMode;
  end;

// Lines, curves and arcs the user drew; copies and parts follow other edges
function CheckConvertible(Pattern: TPattern; Edge: TEdgeObject): boolean;
begin
  if Edge is TEdgeCopy then
    Exit(Pattern.SetError(Format(rsPatternCopyOfTransform, [Edge.DisplayName, Pattern.FindNode(TEdgeCopy(Edge).TransformKey).DisplayName])));
  if Edge.ClassType = TCircleObject then
    Exit(Pattern.SetError(Format(rsPatternCircleNoEnds, [Edge.DisplayName])));
  if (Edge.ClassType <> TLineObject) and (Edge.ClassType <> TCurveObject) and (Edge.ClassType <> TArcObject) then
    Exit(Pattern.SetError(Format(rsPatternNotConvertible, [Edge.DisplayName])));
  Result := True;
end;

// False, with the reason, when a piece's fold or a mirror's axis is Edge or
// an edge that is straight only while Edge is: its parts, copies and offsets
function CheckStaysStraight(Pattern: TPattern; Edge: TEdgeObject): boolean;
var
  Following: TStringArray;
  DraftObject: TDraftObject;
  Source: string;
  Piece: TPieceObject;
  Mirror: TTransformObject;
  Index: integer;
begin
  Following := [Edge.Key];
  // The objects are in input order, so a part of a part is found after its source
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    Source := '';
    if DraftObject is TSplitPart then
      Source := TSplitPart(DraftObject).Source
    else if DraftObject is TEdgeCopy then
      Source := TEdgeCopy(DraftObject).Source
    else if (DraftObject is TOffsetEdge) and (Length(TOffsetEdge(DraftObject).Run) = 1) then
      Source := TOffsetEdge(DraftObject).Run[0].EdgeKey;
    if (Source <> '') and (IndexStr(Source, Following) >= 0) then
      Insert(DraftObject.Key, Following, Length(Following));
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      if (Piece.FoldEdgeKey <> '') and (IndexStr(Piece.FoldEdgeKey, Following) >= 0) then
        Exit(Pattern.SetError(Format(rsPatternFoldFollows, [Pattern.FindNode(Piece.FoldEdgeKey).DisplayName, Piece.DisplayName, Edge.DisplayName])));
    end
    else if Pattern.Objects[Index] is TTransformObject then
    begin
      Mirror := TTransformObject(Pattern.Objects[Index]);
      if (Mirror.AxisEdgeKey <> '') and (IndexStr(Mirror.AxisEdgeKey, Following) >= 0) then
        Exit(Pattern.SetError(Format(rsPatternMirrorAxisFollows, [Pattern.FindNode(Mirror.AxisEdgeKey).DisplayName, Mirror.DisplayName, Edge.DisplayName])));
    end;
  Result := True;
end;

function ConvertToLine(Pattern: TPattern; Edge: TEdgeObject): TLineObject;
var
  StartPoint, EndPoint: TOffsetPoint;
  Radius: string;
begin
  Result := nil;
  if not CheckConvertible(Pattern, Edge) then
    Exit;
  if Edge is TLineObject then
  begin
    Pattern.SetError(Format(rsPatternAlreadyLine, [Edge.DisplayName]));
    Exit;
  end;
  if Edge is TArcObject then
  begin
    Radius := Pattern.FormulaText(Edge, 'radius');
    StartPoint := Pattern.AddOffsetPoint('', TArcObject(Edge).Centre, omPolar, Radius, Pattern.FormulaText(Edge, 'angle1'));
    if not Assigned(StartPoint) then
      Exit;
    EndPoint := Pattern.AddOffsetPoint('', TArcObject(Edge).Centre, omPolar, Radius, Pattern.FormulaText(Edge, 'angle2'));
    if not Assigned(EndPoint) then
      Exit;
    Result := TLineObject.Create(Edge.Key, StartPoint.Key, EndPoint.Key);
  end
  else
    Result := TLineObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
  if not Pattern.ReplaceEdge(Edge, Result, [], []) then
    Result := nil;
end;

function ConvertToCurve(Pattern: TPattern; Edge: TEdgeObject): TCurveObject;
var
  User: TEvalNode;
  FieldIndex: integer;
  Ref: TFormulaReference;
  Direction, BackAngle, Handle: double;
  Formats: TFormatSettings;

  function Text(Value: double): string;
  begin
    Result := FloatToStr(RoundTo(Value, -1), Formats);
  end;

begin
  Result := nil;
  if not CheckConvertible(Pattern, Edge) then
    Exit;
  if Edge is TCurveObject then
  begin
    Pattern.SetError(Format(rsPatternAlreadyCurve, [Edge.DisplayName]));
    Exit;
  end;
  if Edge is TArcObject then
  begin
    Pattern.SetError(Format(rsPatternOnlyLineToCurve, [Edge.DisplayName]));
    Exit;
  end;
  for User in Pattern.UsersOf(Edge) do
    for FieldIndex := 0 to User.FieldCount - 1 do
      for Ref in User.Fields[FieldIndex].Formula.References do
        if (ReferenceKey(Ref) = Edge.Key) and SameText(Ref.Prop, 'angle') then
        begin
          Pattern.SetError(Format(rsPatternAngleInUse, [User.DisplayName, Edge.DisplayName]));
          Exit;
        end;
  if not CheckStaysStraight(Pattern, Edge) then
    Exit;
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  // The handles are placed from where the line is now
  if not Edge.HasResult then
    Pattern.Evaluate;
  Direction := 0;
  Handle := 0;
  if Edge.HasResult then
  begin
    Direction := Edge.StartDirection;
    Handle := Edge.Length / 3;
  end;
  // The end handle points back along the edge
  BackAngle := NormalizeAngle(Direction + 180);
  Result := TCurveObject.Create(Edge.Key, Edge.StartKey, Edge.EndKey);
  if not Pattern.ReplaceEdge(Edge, Result, ['angle1', 'length1', 'angle2', 'length2'],
    [Text(Direction), RoundLengthFormulaText(Handle, Pattern.Units), Text(BackAngle), RoundLengthFormulaText(Handle, Pattern.Units)]) then
    Result := nil;
end;

function ConvertToFree(Pattern: TPattern; Point: TPointObject; const XText, YText: string): TFreePoint;
begin
  Result := TFreePoint.Create(Point.Key);
  if not Pattern.ReplacePoint(Point, Result, ['x', 'y'], [XText, YText]) then
    Result := nil;
end;

function ConvertToBetween(Pattern: TPattern; Point: TPointObject; const FirstId, LastId: string; Mode: TAlongMode; const Value: string): TBetweenPoint;
begin
  Result := nil;
  if not Pattern.CheckPoint(FirstId) or not Pattern.CheckPoint(LastId) then
    Exit;
  Result := TBetweenPoint.Create(Point.Key, FirstId, LastId, Mode);
  if not Pattern.ReplacePoint(Point, Result, ['value'], [Value]) then
    Result := nil;
end;

function ConvertToAlongEdge(Pattern: TPattern; Point: TPointObject; const EdgeId: string; FromEnd: boolean; Mode: TAlongMode;
  const Value: string): TAlongEdgePoint;
begin
  Result := nil;
  if not Pattern.CheckEdgeTarget(EdgeId) then
    Exit;
  Result := TAlongEdgePoint.Create(Point.Key, EdgeId, FromEnd, Mode);
  if not Pattern.ReplacePoint(Point, Result, ['value'], [Value]) then
    Result := nil;
end;

function PointConversionName(Conversion: TPointConversion): string;
begin
  case Conversion of
    pcFree: Result := rsPatternConvertNameFree;
    pcOffset: Result := rsPatternConvertNameOffset;
    pcAlongEdge: Result := rsPatternConvertNameAlong;
    pcBetween: Result := rsPatternConvertNameBetween;
    pcIntersect: Result := rsPatternConvertNameIntersect;
    pcCircleEdge: Result := rsPatternConvertNameCircleEdge;
    pcCircleCircle: Result := rsPatternConvertNameCircleCircle;
    pcProject: Result := rsPatternConvertNameProject;
  end;
end;

// What the conversion reads besides the point, in words
function ConversionNeeds(Conversion: TPointConversion): string;
begin
  case POINT_CONVERSION_INPUTS[Conversion] of
    'P': Result := rsPatternConvertNeedsPoint;
    'E': Result := rsPatternConvertNeedsEdge;
    'PP': Result := rsPatternConvertNeedsTwoPoints;
    'EE': Result := rsPatternConvertNeedsTwoEdges;
    'PE': Result := rsPatternConvertNeedsPointEdge;
    else
      Result := rsPatternConvertNeedsNothing;
  end;
end;

procedure AddField(var Plan: TConversionPlan; const AName, AText: string);
begin
  Insert(AName, Plan.Names, Length(Plan.Names));
  Insert(AText, Plan.Texts, Length(Plan.Texts));
end;

// A length as the field will hold it, in the pattern's unit, and what that is in mm
function LengthText(Pattern: TPattern; Millimetres: double; out Rounded: double): string;
var
  Code: integer;
begin
  Result := RoundLengthFormulaText(Millimetres, Pattern.Units);
  Val(Result, Rounded, Code);
  Rounded := Rounded * MILLIMETRES_PER_UNIT[Pattern.Units];
end;

function LengthText(Pattern: TPattern; Millimetres: double): string;
var
  Rounded: double;
begin
  Result := LengthText(Pattern, Millimetres, Rounded);
end;

// The crossing nearest At, False when there is none
function NearestCrossing(const Crossings: TEdgeCrossingArray; const At: TVec2; out Index: integer; out Gap: double): boolean;
var
  Candidate: integer;
begin
  Index := -1;
  Gap := 0;
  for Candidate := 0 to High(Crossings) do
    if (Index < 0) or (Distance(Crossings[Candidate].Point, At) < Gap) then
    begin
      Index := Candidate;
      Gap := Distance(Crossings[Candidate].Point, At);
    end;
  Result := Index >= 0;
end;

// Takes Crossings when its nearest to At is nearer than the plan's so far by
// more than CONVERT_SAME_PLACE, so a crossing that needs no extension wins a tie
function TakeNearer(const Crossings: TEdgeCrossingArray; const At: TVec2; var Plan: TConversionPlan; var Best: double;
  var Found: boolean): boolean;
var
  Index: integer;
  Gap: double;
begin
  Result := NearestCrossing(Crossings, At, Index, Gap) and (not Found or (Gap < Best - CONVERT_SAME_PLACE));
  if not Result then
    Exit;
  Found := True;
  Best := Gap;
  Plan.Target := Crossings[Index].Point;
  Plan.Pick := Index + 1;
end;

// A ratio as a formula: between 0 and 1, to RATIO_DECIMALS places, as a
// length is rounded as a drag rounds it
function RatioText(Ratio: double): string;
begin
  Result := FormatRoundedJSONFloat(EnsureRange(Ratio, 0.0, 1.0), RATIO_DECIMALS);
end;

function AddAlongValue(Pattern: TPattern; Span, DistanceAlong: double; Measure: TPointMeasureMode;
  var Plan: TConversionPlan): boolean;
begin
  Result := True;
  if Measure = pmRatio then
  begin
    if Span <= DEFAULT_TOLERANCE then
      Exit(Pattern.SetError(rsPatternConvertZeroSpan));
    Plan.AlongMode := amRatio;
    AddField(Plan, 'value', RatioText(DistanceAlong / Span));
  end
  else
    AddField(Plan, 'value', LengthText(Pattern, DistanceAlong));
end;

function PlanAlongEdge(Edge: TEdgeObject; Pattern: TPattern; const Here: TVec2; Measure: TPointMeasureMode;
  Origin: TPointMeasureEnd; var Plan: TConversionPlan): boolean;
var
  Position, Offset: double;
begin
  Plan.Target := Edge.Locate(Here, Position, Offset);
  // A newly converted point defaults to the nearer end.
  Plan.FromEnd := (Origin = peEnd) or ((Origin = peKeep) and (Position > Edge.Length / 2));
  if Plan.FromEnd then
    Position := Edge.Length - Position;
  Result := AddAlongValue(Pattern, Edge.Length, Position, Measure, Plan);
end;

function PlanBetween(PointA, PointB: TPointObject; Pattern: TPattern; const Here: TVec2; Measure: TPointMeasureMode;
  var Plan: TConversionPlan): boolean;
var
  Span: TVec2;
  SpanLength, Along: double;
begin
  Span := Vec2(PointB.Position.X - PointA.Position.X, PointB.Position.Y - PointA.Position.Y);
  SpanLength := Sqrt(Dot(Span, Span));
  if SpanLength < CONVERT_SAME_PLACE then
    Exit(Pattern.SetError(Format(rsPatternConvertSamePlace, [PointA.DisplayName, PointB.DisplayName])));
  Along := Dot(Vec2(Here.X - PointA.Position.X, Here.Y - PointA.Position.Y), Span) / SpanLength;
  Plan.Target := Lerp(PointA.Position, PointB.Position, Along / SpanLength);
  if (Measure = pmRatio) and ((Along < -DEFAULT_TOLERANCE) or (Along > SpanLength + DEFAULT_TOLERANCE)) then
    Exit(Pattern.SetError(rsPatternConvertRatioOutside));
  Result := AddAlongValue(Pattern, SpanLength, Along, Measure, Plan);
end;

// Reuse the evaluated value when the inputs did not change. Locating a point
// again on a self-crossing edge could otherwise choose another stretch.
function ReplanAlong(Pattern: TPattern; Point: TPointObject; Span: double; PreviousMode: TAlongMode;
  WasFromEnd: boolean; Measure: TPointMeasureMode; Origin: TPointMeasureEnd; out Plan: TConversionPlan): boolean;
var
  Value, LengthScale: double;
begin
  Plan := Default(TConversionPlan);
  Plan.Target := Point.Position;
  Plan.AlongMode := PreviousMode;
  if Measure = pmLength then
    Plan.AlongMode := amLength
  else if Measure = pmRatio then
    Plan.AlongMode := amRatio;
  Plan.FromEnd := (Origin = peEnd) or ((Origin = peKeep) and WasFromEnd);
  if (Plan.AlongMode = PreviousMode) and (Plan.FromEnd = WasFromEnd) then
    Exit(Pattern.SetError(Format(rsPatternConvertAlready, [Point.DisplayName])));
  if not Pattern.EvaluateText(Point.Field('value').StoredText, Value) then
    Exit(False);
  LengthScale := MILLIMETRES_PER_UNIT[Pattern.Units];
  if PreviousMode = amLength then
    Value := Value * LengthScale;
  if (PreviousMode = amLength) and (Plan.AlongMode = amRatio) then
  begin
    if Span <= DEFAULT_TOLERANCE then
      Exit(Pattern.SetError(rsPatternConvertZeroSpan));
    Value := Value / Span;
  end
  else if (PreviousMode = amRatio) and (Plan.AlongMode = amLength) then
    Value := Value * Span;
  if Plan.FromEnd <> WasFromEnd then
    if Plan.AlongMode = amRatio then
      Value := 1 - Value
    else
      Value := Span - Value;
  // Rounded as the other conversions round, so the formula stays readable
  if Plan.AlongMode = amLength then
    AddField(Plan, 'value', LengthText(Pattern, Value))
  else
    AddField(Plan, 'value', RatioText(Value));
  Result := True;
end;

function PlanIntersect(EdgeA, EdgeB: TEdgeObject; Pattern: TPattern; const Here: TVec2; var Plan: TConversionPlan): boolean;
var
  Combination: integer;
  Best: double;
  Found: boolean;
begin
  Found := False;
  Best := 0;
  // Neither extended, then either, then both
  for Combination := 0 to 3 do
    if TakeNearer(CrossEdges(EdgeA, Odd(Combination), EdgeB, Combination >= 2), Here, Plan, Best, Found) then
    begin
      Plan.ExtendA := Odd(Combination);
      Plan.ExtendB := Combination >= 2;
    end;
  if not Found then
    Exit(Pattern.SetError(Format(rsPatternConvertNoCrossing, [EdgeA.DisplayName, EdgeB.DisplayName])));
  Result := True;
end;

function PlanCircleEdge(Centre: TPointObject; Edge: TEdgeObject; Point: TPointObject; Pattern: TPattern; var Plan: TConversionPlan): boolean;
var
  Radius, Best: double;
  Extend, Found: boolean;
begin
  AddField(Plan, 'radius', LengthText(Pattern, Distance(Centre.Position, Point.Position), Radius));
  Found := False;
  Best := 0;
  for Extend in boolean do
    if TakeNearer(CrossCircleEdge(Centre.Position, Radius, Edge, Extend), Point.Position, Plan, Best, Found) then
      Plan.ExtendA := Extend;
  if not Found then
    Exit(Pattern.SetError(Format(rsPatternConvertCircleMisses, [Centre.DisplayName, Point.DisplayName, Edge.DisplayName])));
  Result := True;
end;

function PlanCircleCircle(CentreA, CentreB, Point: TPointObject; Pattern: TPattern; var Plan: TConversionPlan): boolean;
var
  RadiusA, RadiusB: double;
  First, Second: TVec2;
begin
  AddField(Plan, 'radiusA', LengthText(Pattern, Distance(CentreA.Position, Point.Position), RadiusA));
  AddField(Plan, 'radiusB', LengthText(Pattern, Distance(CentreB.Position, Point.Position), RadiusB));
  if IntersectCircles(CentreA.Position, RadiusA, CentreB.Position, RadiusB, First, Second) = 0 then
    Exit(Pattern.SetError(Format(rsPatternConvertCirclesMiss, [CentreA.DisplayName, CentreB.DisplayName, Point.DisplayName])));
  Plan.Pick := 1;
  Plan.Target := First;
  if Distance(Second, Point.Position) < Distance(First, Point.Position) then
  begin
    Plan.Pick := 2;
    Plan.Target := Second;
  end;
  Result := True;
end;

function PlanProject(Source: TPointObject; Edge: TEdgeObject; const Here: TVec2; var Plan: TConversionPlan): boolean;
var
  Position, Offset: double;
  Foot: TVec2;
begin
  Plan.Target := Edge.Locate(Here, Position, Offset);
  Foot := Edge.Locate(Source.Position, Position, Offset);
  Plan.Perpendicular := Distance(Foot, Plan.Target) <= CONVERT_SAME_PLACE;
  if not Plan.Perpendicular then
    AddField(Plan, 'angle', FormatRoundedJSONFloat(AngleBetween(Source.Position, Plan.Target), CONVERT_ANGLE_DECIMALS));
  Result := True;
end;

// Where Conversion puts the point and with what, from Nodes, the inputs
function PlanConversion(Pattern: TPattern; Point: TPointObject; Conversion: TPointConversion; const Nodes: array of TDraftObject;
  Mode: TOffsetMode; Measure: TPointMeasureMode; Origin: TPointMeasureEnd; out Plan: TConversionPlan): boolean;
var
  Here: TVec2;
begin
  Plan := Default(TConversionPlan);
  Here := Point.Position;
  Plan.Target := Here;
  Result := True;
  case Conversion of
    pcFree:
    begin
      AddField(Plan, 'x', LengthText(Pattern, Here.X));
      AddField(Plan, 'y', LengthText(Pattern, Here.Y));
    end;
    pcOffset:
      if Mode = omPolar then
      begin
        AddField(Plan, 'length', LengthText(Pattern, Distance(TPointObject(Nodes[0]).Position, Here)));
        AddField(Plan, 'angle', FormatRoundedJSONFloat(AngleBetween(TPointObject(Nodes[0]).Position, Here), CONVERT_ANGLE_DECIMALS));
      end
      else
      begin
        AddField(Plan, 'dx', LengthText(Pattern, Here.X - TPointObject(Nodes[0]).Position.X));
        AddField(Plan, 'dy', LengthText(Pattern, Here.Y - TPointObject(Nodes[0]).Position.Y));
      end;
    pcAlongEdge: Result := PlanAlongEdge(TEdgeObject(Nodes[0]), Pattern, Here, Measure, Origin, Plan);
    pcBetween: Result := PlanBetween(TPointObject(Nodes[0]), TPointObject(Nodes[1]), Pattern, Here, Measure, Plan);
    pcIntersect: Result := PlanIntersect(TEdgeObject(Nodes[0]), TEdgeObject(Nodes[1]), Pattern, Here, Plan);
    pcCircleEdge: Result := PlanCircleEdge(TPointObject(Nodes[0]), TEdgeObject(Nodes[1]), Point, Pattern, Plan);
    pcCircleCircle: Result := PlanCircleCircle(TPointObject(Nodes[0]), TPointObject(Nodes[1]), Point, Pattern, Plan);
    pcProject: Result := PlanProject(TPointObject(Nodes[0]), TEdgeObject(Nodes[1]), Here, Plan);
  end;
  if Result and (Distance(Plan.Target, Here) > MAX_CONVERT_MOVE) then
    Result := Pattern.SetError(Format(rsPatternConvertTooFar, [Point.DisplayName, LengthWithUnit(Distance(Plan.Target, Here), Pattern.Units)]));
end;

function NewConvertedPoint(const Key: string; Conversion: TPointConversion; const Inputs: array of string;
  const Plan: TConversionPlan; Mode: TOffsetMode): TPointObject;
begin
  case Conversion of
    pcFree: Result := TFreePoint.Create(Key);
    pcOffset: Result := TOffsetPoint.Create(Key, Inputs[0], Mode);
    pcAlongEdge: Result := TAlongEdgePoint.Create(Key, Inputs[0], Plan.FromEnd, Plan.AlongMode);
    pcBetween: Result := TBetweenPoint.Create(Key, Inputs[0], Inputs[1], Plan.AlongMode);
    pcIntersect: Result := TIntersectPoint.Create(Key, Inputs[0], Inputs[1], Plan.ExtendA, Plan.ExtendB, Plan.Pick);
    pcCircleEdge: Result := TCircleEdgePoint.Create(Key, Inputs[0], Inputs[1], Plan.ExtendA, Plan.Pick);
    pcCircleCircle: Result := TCircleCirclePoint.Create(Key, Inputs[0], Inputs[1], Plan.Pick);
    pcProject:
      if Plan.Perpendicular then
        Result := TProjectPoint.Create(Key, Inputs[0], Inputs[1], pdPerpendicular, False)
      else
        Result := TProjectPoint.Create(Key, Inputs[0], Inputs[1], pdAngle, False);
  end;
end;

// The inputs, checked to be of the kinds Conversion reads and to have a place
function ConversionInputs(Pattern: TPattern; Point: TPointObject; Conversion: TPointConversion; const Inputs: array of string;
  out Nodes: TDraftObjectArray): boolean;
var
  Kinds: string;
  Index: integer;
  Checked: boolean;
begin
  Nodes := nil;
  Kinds := POINT_CONVERSION_INPUTS[Conversion];
  if Length(Inputs) <> Length(Kinds) then
    Exit(Pattern.SetError(Format(rsPatternConvertNeeds, [PointConversionName(Conversion), Point.DisplayName, ConversionNeeds(Conversion)])));
  for Index := 0 to High(Inputs) do
  begin
    if Kinds[Index + 1] = 'P' then
      Checked := Pattern.CheckPoint(Inputs[Index])
    else
      Checked := Pattern.CheckEdgeTarget(Inputs[Index]);
    if not Checked then
      Exit(False);
    Insert(TDraftObject(Pattern.FindNode(Inputs[Index])), Nodes, Length(Nodes));
  end;
  Pattern.Evaluate;
  if not Point.HasResult then
    Exit(Pattern.SetError(Format(rsPatternConvertNoPlace, [Point.DisplayName])));
  for Index := 0 to High(Nodes) do
    if not Nodes[Index].HasResult then
      Exit(Pattern.SetError(Format(rsPatternConvertInputNoPlace, [Nodes[Index].DisplayName, Point.DisplayName])));
  Result := True;
end;

// Point is already Conversion from these inputs, an offset in that mode, so
// there is nothing to change
function AlreadyConverted(Point: TPointObject; Conversion: TPointConversion; const Inputs: array of string;
  Mode: TOffsetMode): boolean;
var
  Current: TStringArray;
  Index: integer;
begin
  if Point.ClassType <> CONVERSION_CLASSES[Conversion] then
    Exit(False);
  if (Point is TOffsetPoint) and (TOffsetPoint(Point).Mode <> Mode) then
    Exit(False);
  Current := Point.InputKeys;
  if Length(Current) <> Length(Inputs) then
    Exit(False);
  for Index := 0 to High(Inputs) do
    if Current[Index] <> Inputs[Index] then
      Exit(False);
  Result := True;
end;

function ConvertPoint(Pattern: TPattern; Point: TPointObject; Conversion: TPointConversion; const Inputs: array of string;
  Mode: TOffsetMode; Measure: TPointMeasureMode; Origin: TPointMeasureEnd): TPointObject;
var
  Nodes: TDraftObjectArray;
  Plan: TConversionPlan;
begin
  Result := nil;
  if Point is TCornerPoint then
  begin
    Pattern.SetError(Format(rsPatternConvertCornerPoint, [Point.DisplayName, Pattern.FindNode(TCornerPoint(Point).Arc).DisplayName]));
    Exit;
  end;
  if not ConversionInputs(Pattern, Point, Conversion, Inputs, Nodes) then
    Exit;
  if AlreadyConverted(Point, Conversion, Inputs, Mode) then
  begin
    if Point is TAlongEdgePoint then
    begin
      if not ReplanAlong(Pattern, Point, TEdgeObject(Nodes[0]).Length, TAlongEdgePoint(Point).Mode,
        TAlongEdgePoint(Point).FromEnd, Measure, Origin, Plan) then
        Exit;
    end
    else if Point is TBetweenPoint then
    begin
      if not ReplanAlong(Pattern, Point, Distance(TPointObject(Nodes[0]).Position, TPointObject(Nodes[1]).Position),
        TBetweenPoint(Point).Mode, False, Measure, peKeep, Plan) then
        Exit;
    end
    else
    begin
      Pattern.SetError(Format(rsPatternConvertAlready, [Point.DisplayName]));
      Exit;
    end;
  end
  else if not PlanConversion(Pattern, Point, Conversion, Nodes, Mode, Measure, Origin, Plan) then
    Exit;
  // ReplacePoint frees the new point when it refuses it
  Result := NewConvertedPoint(Point.Key, Conversion, Inputs, Plan, Mode);
  if not Pattern.ReplacePoint(Point, Result, Plan.Names, Plan.Texts) then
    Result := nil;
end;

function ExtendCurve(Pattern: TPattern; Edge: TEdgeObject; const PointId: string): TCurvePathObject;
var
  Users: TEvalNodeArray;
  Nodes, Names, Texts: TStringArray;
  Count, Index: integer;
  Before, Last, Next: TVec2;
  Handle: double;
  Formats: TFormatSettings;

  function Text(Value: double): string;
  begin
    Result := FloatToStr(RoundTo(Value, -1), Formats);
  end;

  procedure Keep(const NewName, OldName: string);
  begin
    Insert(NewName, Names, Length(Names));
    Insert(Edge.Field(OldName).StoredText, Texts, Length(Texts));
  end;

  procedure Put(const NewName, AText: string);
  begin
    Insert(NewName, Names, Length(Names));
    Insert(AText, Texts, Length(Texts));
  end;

  function PositionOf(const Key: string): TVec2;
  begin
    Result := TPointObject(Pattern.FindNode(Key)).Position;
  end;

begin
  Result := nil;
  if Edge is TEdgeCopy then
  begin
    Pattern.SetError(Format(rsPatternCopyOfTransform, [Edge.DisplayName, Pattern.FindNode(TEdgeCopy(Edge).TransformKey).DisplayName]));
    Exit;
  end;
  if (Edge.ClassType <> TCurveObject) and (Edge.ClassType <> TCurvePathObject) then
  begin
    Pattern.SetError(Format(rsPatternNotExtendable, [Edge.DisplayName]));
    Exit;
  end;
  Users := Pattern.UsersOf(Edge);
  if Length(Users) > 0 then
  begin
    Pattern.SetError(Format(rsPatternExtendInUse, [Edge.DisplayName, Users[0].DisplayName]));
    Exit;
  end;
  if not Pattern.CheckPoint(PointId) then
    Exit;
  if PointId = Edge.EndKey then
  begin
    Pattern.SetError(Format(rsPatternExtendSamePoint, [Edge.DisplayName, Pattern.FindNode(PointId).DisplayName]));
    Exit;
  end;
  if Edge is TCurvePathObject then
    Nodes := Copy(TCurvePathObject(Edge).NodeKeys)
  else
    Nodes := [Edge.StartKey, Edge.EndKey];
  Count := Length(Nodes);
  // The new handles are placed from where the points are now
  if not Edge.HasResult or not Pattern.FindNode(PointId).HasResult then
    Pattern.Evaluate;
  Before := PositionOf(Nodes[Count - 2]);
  Last := PositionOf(Nodes[Count - 1]);
  Next := PositionOf(PointId);
  Handle := Distance(Last, Next) / 3;
  Formats := DefaultFormatSettings;
  Formats.DecimalSeparator := '.';
  Names := nil;
  Texts := nil;
  if Edge is TCurveObject then
  begin
    Keep('node1.angle', 'angle1');
    Keep('node1.lengthOut', 'length1');
    Keep('node2.lengthIn', 'length2');
  end
  else
    for Index := 1 to Count do
    begin
      if Index > 1 then
        Keep(Format('node%d.lengthIn', [Index]), Format('node%d.lengthIn', [Index]));
      if Index < Count then
      begin
        Keep(Format('node%d.angle', [Index]), Format('node%d.angle', [Index]));
        Keep(Format('node%d.lengthOut', [Index]), Format('node%d.lengthOut', [Index]));
      end;
    end;
  // The old end runs on from the point before it towards the new one
  Put(Format('node%d.angle', [Count]), Text(AngleBetween(Before, Next)));
  Put(Format('node%d.lengthOut', [Count]), RoundLengthFormulaText(Handle, Pattern.Units));
  Put(Format('node%d.lengthIn', [Count + 1]), RoundLengthFormulaText(Handle, Pattern.Units));
  Put(Format('node%d.angle', [Count + 1]), Text(AngleBetween(Last, Next)));
  Insert(PointId, Nodes, Length(Nodes));
  Result := TCurvePathObject.Create(Edge.Key, Nodes);
  if not Pattern.ReplaceEdge(Edge, Result, Names, Texts) then
    Result := nil;
end;

end.
