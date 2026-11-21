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

// Features: sewing details applied to a pattern in one step, such as a zip
// in a seam or a dart in a piece's edge. Each is made of ordinary objects, points, split edges,
// allowances, notches and lines, which the user can then change as if they
// had drawn them. Nothing here is saved as a feature.
unit Sloper.Core.Features;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern;

type
  TFeatureKind = (fkZip, fkDart);

  // Centred: topstitched either side of the seam. Invisible: sewn from the
  // inside, so nothing shows. Lapped: one side laps over the zip, stitched
  // down it and across at the stop. Fly front: the side laps over by the
  // fly's width, its stitching curving in to the stop as a J, with a fly
  // shield behind the zip as a piece of its own.
  TZipStyle = (zsCentred, zsInvisible, zsLapped, zsFlyFront);

  TZipSpec = record
    // An edge of one or more pieces, along which the zip opens
    EdgeKey: string;
    // The zip runs from the edge's end rather than its start
    FromEnd: boolean;
    // Formulas in the pattern's unit, with names: the zip's length, the
    // allowance along the opening (for a fly front its extension), how far
    // the topstitching is from it, and a fly shield's width as it is worn
    Length, Allowance, StitchDistance, ShieldWidth: string;
    Style: TZipStyle;
  end;

  TZipMade = record
    // The point where the zip stops
    StopKey: string;
    // The edge's parts: along the zip, and the rest of the seam
    OpeningKey, RestKey: string;
    // The pieces the zip went into, and its topstitching on each: for a
    // lapped zip the line down and the line across, for a fly front the
    // straight part and the curve
    PieceKeys, StitchKeys: array of string;
    // A fly front's shield, a piece cut on the fold beside the pattern
    ShieldKey: string;
    // The edge is in a seam with another piece's edge, which needs a zip too
    OtherSide: boolean;
  end;

  TDartSpec = record
    // An outline edge of one piece, which the dart opens in
    EdgeKey: string;
    // Position is measured from the edge's end rather than its start
    FromEnd: boolean;
    // Formulas in the pattern's unit, with names: where the dart's middle is
    // along the edge ('' for halfway), its width there, how deep it runs into
    // the piece, square to the edge, and how far back from its point the
    // hole goes ('' for no hole)
    Position, Width, Depth, HoleInset: string;
    // A point the dart runs to, such as a bust point, instead of the depth
    ApexKey: string;
    // Pressed towards the edge's end rather than its start
    TowardsEnd: boolean;
  end;

  TDartMade = record
    // The dart's middle on the edge, and its point
    MidKey, ApexKey: string;
    // Where the legs leave the edge, and the legs, the start's side first
    LegPointKeys, LegKeys: array[0..1] of string;
    // The seam that closes it, the hole near its point, its centre line
    // (where it folds), and the piece
    SeamKey, HoleKey, CentreKey, PieceKey: string;
  end;

const
  ZIP_LENGTH_VARIABLE = 'zip_length';
  ZIP_STOP_NAME = 'ZipStop';
  FLY_SHIELD_NAME = 'FlyShield';
  DART_MID_NAME = 'DartMid';
  DART_APEX_NAME = 'DartApex';
  DART_LEG_NAME = 'DartLeg';
  DART_SEAM_NAME = 'Dart';
  // As the Automation API names the styles
  ZIP_STYLE_NAMES: array[TZipStyle] of string = ('centred', 'invisible', 'lapped', 'flyFront');

// A zip on the edge with the style's starting widths in the pattern's unit,
// its length the zip_length variable, which InsertZip adds when it is missing
function DefaultZip(Pattern: TPattern; const EdgeKey: string; Style: TZipStyle = zsCentred): TZipSpec;
// Adds the zip's objects and evaluates. False, with the reason in
// Pattern.LastError, when it cannot go there; objects may have been added
// by then, so call it inside a document change and cancel that on failure.
function InsertZip(Pattern: TPattern; const Spec: TZipSpec; out Made: TZipMade): boolean;
// A dart halfway along the edge with the pattern unit's starting width,
// depth and hole inset, pressed towards the edge's start
function DefaultDart(Pattern: TPattern; const EdgeKey: string): TDartSpec;
// Adds the dart's objects and evaluates, as InsertZip does: the legs from the
// edge to the point, which take the place of the opening in the piece's
// outline, the seam that closes it, a notch at each leg, a hole near the
// point, the centre line as a fold, and the cap the allowance has across it
function InsertDart(Pattern: TPattern; const Spec: TDartSpec; out Made: TDartMade): boolean;

resourcestring
  rsFeatureZip = 'Zip';
  rsFeatureZipLength = 'The length of the zip';
  rsFeatureNoEdge = 'Choose an edge of a piece for the zip';
  rsFeatureNotInPiece = '%s is in no piece; a zip goes along a piece''s edge';
  rsFeatureZipTooLong = 'The zip, %s long, does not fit along %s, which is %s';
  rsFeatureDart = 'Dart';
  rsFeatureNoDartEdge = 'Choose an edge of a piece for the dart';
  rsFeatureDartNotInPiece = '%s is in no piece; a dart goes into a piece''s edge';
  rsFeatureDartPieces = '%s is in more than one piece; a dart goes into one';
  rsFeatureDartFold = '%s is the fold of %s, which a dart cannot go into';
  rsFeatureDartPieceProblem = '%s has a problem to put right first: %s';
  rsFeatureDartNoWidth = 'A dart needs a width above 0';
  rsFeatureDartTooWide = 'The dart, %s wide with its middle %s along %s, runs past an end of it (%s long)';
  rsFeatureDartNoDepth = 'A dart needs a depth above 0';
  rsFeatureDartApexOutside = 'The dart''s point, %s, is not inside %s';
  rsFeatureDartCrosses = 'The dart''s legs would cross %s';

implementation

uses
  SysUtils, Math, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.EvalTypes, Sloper.Core.Units,
  Sloper.Core.Geometry;

const
  RIGHT_ANGLE = 90;
  // A cubic's handles this share of the radius long make a close quarter circle
  QUARTER_CIRCLE_HANDLE = '0.55';
  // Decimals of a coordinate a feature writes into a formula
  NUMBER_DECIMALS = 3;
  // How far, in mm, from an edge a point is tried to see which side is inside
  PROBE_DISTANCE = 1;
  // How close to where a leg leaves the edge, in mm, it may meet the outline
  // as drawn, whose curves are flattened, without crossing it
  LEG_SLACK = 1;

var
  FormatNumbers: TFormatSettings;

function DefaultZip(Pattern: TPattern; const EdgeKey: string; Style: TZipStyle): TZipSpec;
begin
  Result := Default(TZipSpec);
  Result.EdgeKey := EdgeKey;
  Result.Length := '#' + ZIP_LENGTH_VARIABLE;
  Result.Style := Style;
  Result.Allowance := STARTING_LENGTHS[slZipAllowance, Pattern.Units];
  Result.StitchDistance := STARTING_LENGTHS[slZipStitch, Pattern.Units];
  Result.ShieldWidth := STARTING_LENGTHS[slFlyShieldWidth, Pattern.Units];
  case Style of
    zsLapped:
      Result.StitchDistance := STARTING_LENGTHS[slLapStitch, Pattern.Units];
    zsFlyFront:
    begin
      Result.Allowance := STARTING_LENGTHS[slFlyExtension, Pattern.Units];
      Result.StitchDistance := STARTING_LENGTHS[slFlyStitch, Pattern.Units];
    end;
  end;
end;

// The pieces whose outline runs along the edge
function PiecesOn(Pattern: TPattern; const EdgeKey: string): TPieceObjectArray;
var
  Index: integer;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) and (TPieceObject(Pattern.Objects[Index]).PathIndexOf(EdgeKey) >= 0) then
      Insert(TPieceObject(Pattern.Objects[Index]), Result, Length(Result));
end;

// Whether a seam joins the edge to an edge it is not
function SeamedToAnother(Pattern: TPattern; const EdgeKey: string): boolean;
var
  Index: integer;
  Seam: TSeamObject;
  Entry: TSeamEntry;
  OnA, OnB: boolean;
begin
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TSeamObject then
    begin
      Seam := TSeamObject(Pattern.Objects[Index]);
      OnA := False;
      OnB := False;
      for Entry in Seam.SideA do
        OnA := OnA or (Entry.EdgeKey = EdgeKey);
      for Entry in Seam.SideB do
        OnB := OnB or (Entry.EdgeKey = EdgeKey);
      if OnA <> OnB then
        Exit(True);
    end;
  Result := False;
end;

// Base, or Base with the next free number after it
function FreeName(Pattern: TPattern; const Base: string): string;
var
  Number: integer;
begin
  Result := Base;
  Number := 1;
  while Assigned(Pattern.FindObject(Result)) do
  begin
    Inc(Number);
    Result := Base + IntToStr(Number);
  end;
end;

// The zip_length variable the starting formula names, when it is missing
function AddLengthVariable(Pattern: TPattern; const Spec: TZipSpec): boolean;
begin
  Result := True;
  if (Pos(LowerCase('#' + ZIP_LENGTH_VARIABLE), LowerCase(Spec.Length)) > 0) and not Assigned(Pattern.FindVariable(ZIP_LENGTH_VARIABLE)) then
    Result := Assigned(Pattern.AddVariable(ZIP_LENGTH_VARIABLE, STARTING_LENGTHS[slZipLength, Pattern.Units], rsFeatureZipLength));
end;

// The zip's stop, checked to lie inside the edge rather than at or past an end
function AddStop(Pattern: TPattern; Edge: TEdgeObject; const Spec: TZipSpec; out Stop: TDraftObject): boolean;
var
  Value: double;
begin
  Stop := Pattern.AddAlongEdgePoint(FreeName(Pattern, ZIP_STOP_NAME), Edge.Key, Spec.FromEnd, amLength, Spec.Length);
  if not Assigned(Stop) then
    Exit(False);
  Pattern.Evaluate;
  if not Pattern.EvaluateText(Spec.Length, Value) then
    Exit(False);
  Value := Value * MILLIMETRES_PER_UNIT[Pattern.Units];
  if (Stop.State <> esValid) or (Value <= DEFAULT_TOLERANCE) or (Value >= Edge.Length - DEFAULT_TOLERANCE) then
    Exit(Pattern.Refuse(Format(rsFeatureZipTooLong, [LengthWithUnit(Value, Pattern.Units), Edge.DisplayName,
      LengthWithUnit(Edge.Length, Pattern.Units)])));
  Result := True;
end;

procedure AddStitch(var Made: TZipMade; const Key: string);
begin
  Insert(Key, Made.StitchKeys, Length(Made.StitchKeys));
end;

// Whether the piece's run along the opening ends at the stop
function RunEndsAtStop(Pattern: TPattern; const Run: TRunEdgeArray; const StopKey: string): boolean;
var
  Edge: TEdgeObject;
begin
  Edge := TEdgeObject(Pattern.FindNode(Run[High(Run)].EdgeKey));
  if Run[High(Run)].Reversed then
    Result := Edge.StartKey = StopKey
  else
    Result := Edge.EndKey = StopKey;
end;

// A lap's stitching: down the opening, then across to the seam at the stop
function AddLapStitch(Pattern: TPattern; const Run: TRunEdgeArray; Side: TOffsetSide; const Spec: TZipSpec; var Made: TZipMade): boolean;
var
  Stitch: TOffsetEdge;
  Corner: TDraftObject;
  Across: TEdgeObject;
begin
  Stitch := Pattern.AddOffsetRun(Run, Spec.StitchDistance, Side, erStitch);
  if not Assigned(Stitch) then
    Exit(False);
  AddStitch(Made, Stitch.Key);
  Corner := Pattern.AddAlongEdgePoint('', Stitch.Key, RunEndsAtStop(Pattern, Run, Made.StopKey), amLength, '0');
  if not Assigned(Corner) then
    Exit(False);
  Across := Pattern.AddLine(Corner.Key, Made.StopKey, erStitch);
  if not Assigned(Across) then
    Exit(False);
  AddStitch(Made, Across.Key);
  Result := True;
end;

// A fly's stitching: down at the fly's width, then curving in to the stop as
// a quarter circle of that radius. A guide at the width is split where the
// curve starts; the part down to there is the stitching.
function AddFlyStitch(Pattern: TPattern; const Run: TRunEdgeArray; Side: TOffsetSide; const Spec: TZipSpec; var Made: TZipMade): boolean;
var
  Guide: TOffsetEdge;
  Bend, Stop, Top: TPointObject;
  First, Second, Straight: TSplitPart;
  Opening: TEdgeObject;
  Curve: TCurveObject;
  AtEnd: boolean;
  Travel, Inward, Handle, TopKey: string;
  TravelAngle: double;
  Square: TVec2;
begin
  Result := False;
  Guide := Pattern.AddOffsetRun(Run, Spec.StitchDistance, Side, erConstruction);
  if not Assigned(Guide) then
    Exit;
  AtEnd := RunEndsAtStop(Pattern, Run, Made.StopKey);
  Bend := TPointObject(Pattern.AddAlongEdgePoint('', Guide.Key, AtEnd, amLength, Spec.StitchDistance));
  if not Assigned(Bend) or not Pattern.SplitEdge(Guide.Key, Bend.Key, First, Second) then
    Exit;
  if AtEnd then
    Straight := First
  else
    Straight := Second;
  if not Pattern.SetEdgeRole(Straight, erStitch) then
    Exit;
  AddStitch(Made, Straight.Key);
  Pattern.Evaluate;
  if Bend.State <> esValid then
    Exit(Pattern.Refuse(Bend.Message));
  Opening := TEdgeObject(Pattern.FindNode(Made.OpeningKey));
  TopKey := Opening.StartKey;
  if TopKey = Made.StopKey then
    TopKey := Opening.EndKey;
  Top := TPointObject(Pattern.FindNode(TopKey));
  Stop := TPointObject(Pattern.FindNode(Made.StopKey));
  // Along the opening towards the stop; angles anticlockwise as on screen,
  // with y down
  Travel := Format('atan2(%0:s.y - %1:s.y, %1:s.x - %0:s.x)', [Top.DisplayName, Stop.DisplayName]);
  TravelAngle := RadToDeg(ArcTan2(Top.Position.Y - Stop.Position.Y, Stop.Position.X - Top.Position.X));
  // The end's handle points back into the piece, the side the bend is on
  Square := Vec2(Cos(DegToRad(TravelAngle + RIGHT_ANGLE)), -Sin(DegToRad(TravelAngle + RIGHT_ANGLE)));
  if Dot(Square, Bend.Position - Stop.Position) > 0 then
    Inward := Format('%s + %d', [Travel, RIGHT_ANGLE])
  else
    Inward := Format('%s - %d', [Travel, RIGHT_ANGLE]);
  Handle := Format('%s * (%s)', [QUARTER_CIRCLE_HANDLE, Spec.StitchDistance]);
  Curve := Pattern.AddCurve(Bend.Key, Made.StopKey, Travel, Handle, Inward, Handle, erStitch);
  if not Assigned(Curve) then
    Exit;
  AddStitch(Made, Curve.Key);
  Result := True;
end;

// On each piece: the opening's allowance, a notch at the stop, and the
// style's topstitching inside the piece
function FinishPieces(Pattern: TPattern; const Pieces: TPieceObjectArray; const Spec: TZipSpec; var Made: TZipMade): boolean;
var
  Piece: TPieceObject;
  Run: TRunEdgeArray;
  Side: TOffsetSide;
  Stitch: TOffsetEdge;
begin
  for Piece in Pieces do
  begin
    Insert(Piece.Key, Made.PieceKeys, Length(Made.PieceKeys));
    if (Spec.Allowance <> '') and not Pattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Made.OpeningKey), Spec.Allowance) then
      Exit(False);
    if not Pattern.AddPointNotch(Piece, Made.StopKey) then
      Exit(False);
    if (Spec.Style = zsInvisible) or (Spec.StitchDistance = '') then
      Continue;
    // The side is the run's, which may go against the way the edge was drawn
    if not Pattern.PieceRun(Piece, [Made.OpeningKey], True, Run, Side) then
      Exit(False);
    case Spec.Style of
      zsCentred:
      begin
        Stitch := Pattern.AddOffsetRun(Run, Spec.StitchDistance, Side, erStitch);
        if not Assigned(Stitch) then
          Exit(False);
        AddStitch(Made, Stitch.Key);
      end;
      zsLapped:
        if not AddLapStitch(Pattern, Run, Side, Spec, Made) then
          Exit(False);
      zsFlyFront:
        if not AddFlyStitch(Pattern, Run, Side, Spec, Made) then
          Exit(False);
    end;
  end;
  Result := True;
end;

// The right of every piece's cutting line and the top of the highest, in mm
procedure PatternExtent(Pattern: TPattern; out Right, Top: double);
var
  Index: integer;
  Piece: TPieceObject;
  Point: TVec2;
  First: boolean;
begin
  Right := 0;
  Top := 0;
  First := True;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      for Point in Piece.CutLine do
      begin
        if First or (Point.X > Right) then
          Right := Point.X;
        if First or (Point.Y < Top) then
          Top := Point.Y;
        First := False;
      end;
    end;
end;

function NumberText(Value: double): string;
begin
  Result := FloatToStrF(Value, ffFixed, 15, NUMBER_DECIMALS, FormatNumbers);
end;

// The fly shield: a strip the zip's length and a little more, the shield's
// width cut on the fold, to the right of the pattern
function AddFlyShield(Pattern: TPattern; const Spec: TZipSpec; var Made: TZipMade): boolean;
var
  Right, Top, Gap, Scale: double;
  Corner: TFreePoint;
  Edges: TRectangleEdges;
  Path: TPiecePath;
  Index: integer;
  Shield: TPieceObject;
begin
  Result := False;
  Scale := MILLIMETRES_PER_UNIT[Pattern.Units];
  PatternExtent(Pattern, Right, Top);
  Gap := StrToFloat(STARTING_LENGTHS[slFeatureGap, Pattern.Units], FormatNumbers) * Scale;
  Corner := Pattern.AddFreePoint('', NumberText((Right + Gap) / Scale), NumberText(Top / Scale));
  if not Assigned(Corner) or not Pattern.AddRectangle(Corner.Key, Spec.ShieldWidth, Format('(%s) + %s', [Spec.Length,
    STARTING_LENGTHS[slFlyShieldExtra, Pattern.Units]]), erOutline, Edges) then
    Exit;
  Path := nil;
  SetLength(Path, Length(Edges));
  for Index := 0 to High(Edges) do
  begin
    Path[Index].EdgeKey := Edges[Index].Key;
    Path[Index].Reversed := False;
  end;
  Pattern.Evaluate;
  Shield := Pattern.AddPiece(FreeName(Pattern, FLY_SHIELD_NAME), Path, STARTING_LENGTHS[slPieceAllowance, Pattern.Units]);
  if not Assigned(Shield) then
    Exit;
  Pattern.Evaluate;
  // Folded along the side away from the pattern, so it opens out clear of it
  if not Pattern.SetFoldEdge(Shield, Edges[1].Key) then
    Exit;
  Made.ShieldKey := Shield.Key;
  Result := True;
end;

function InsertZip(Pattern: TPattern; const Spec: TZipSpec; out Made: TZipMade): boolean;
var
  Node: TObject;
  Edge: TEdgeObject;
  Pieces: TPieceObjectArray;
  Stop: TDraftObject;
  First, Second: TSplitPart;
begin
  Made := Default(TZipMade);
  Node := Pattern.FindNode(Spec.EdgeKey);
  if not (Node is TEdgeObject) then
    Exit(Pattern.Refuse(rsFeatureNoEdge));
  Edge := TEdgeObject(Node);
  Pieces := PiecesOn(Pattern, Edge.Key);
  if Length(Pieces) = 0 then
    Exit(Pattern.Refuse(Format(rsFeatureNotInPiece, [Edge.DisplayName])));
  Made.OtherSide := SeamedToAnother(Pattern, Edge.Key);
  if not AddLengthVariable(Pattern, Spec) or not AddStop(Pattern, Edge, Spec, Stop) then
    Exit(False);
  Made.StopKey := Stop.Key;
  if not Pattern.SplitEdge(Edge.Key, Stop.Key, First, Second) then
    Exit(False);
  if Spec.FromEnd then
  begin
    Made.OpeningKey := Second.Key;
    Made.RestKey := First.Key;
  end
  else
  begin
    Made.OpeningKey := First.Key;
    Made.RestKey := Second.Key;
  end;
  Pattern.Evaluate;
  Result := FinishPieces(Pattern, Pieces, Spec, Made) and ((Spec.Style <> zsFlyFront) or AddFlyShield(Pattern, Spec, Made));
  Pattern.Evaluate;
end;

function DefaultDart(Pattern: TPattern; const EdgeKey: string): TDartSpec;
begin
  Result := Default(TDartSpec);
  Result.EdgeKey := EdgeKey;
  Result.Width := STARTING_LENGTHS[slDartWidth, Pattern.Units];
  Result.Depth := STARTING_LENGTHS[slDartDepth, Pattern.Units];
  Result.HoleInset := STARTING_LENGTHS[slDartHoleInset, Pattern.Units];
end;

// The edge of the piece's path that the outline's segment Index is part of
function OutlineEdge(Pattern: TPattern; Piece: TPieceObject; Index: integer): string;
var
  Entry: integer;
begin
  Result := '';
  for Entry := 0 to High(Piece.EdgeStarts) do
    if Piece.EdgeStarts[Entry] <= Index then
      Result := Pattern.FindNode(Piece.Path[Entry].EdgeKey).DisplayName;
end;

// Whether the legs, from the edge to the point, cross the piece's outline
// anywhere but where they leave the edge, with the reason in LastError
function LegsCross(Pattern: TPattern; Piece: TPieceObject; const StartLeg, Apex, EndLeg: TVec2): boolean;
var
  Index, Count: integer;
  Segment: TLine2;
  Hit: TIntersection;
begin
  Count := Length(Piece.Outline);
  for Index := 0 to Count - 1 do
  begin
    Segment := Line2(Piece.Outline[Index], Piece.Outline[(Index + 1) mod Count]);
    if (IntersectLines(Segment, Line2(StartLeg, Apex), False, False, Hit) and not PointsNear(Hit.Point, StartLeg, LEG_SLACK)) or
      (IntersectLines(Segment, Line2(Apex, EndLeg), False, False, Hit) and not PointsNear(Hit.Point, EndLeg, LEG_SLACK)) then
    begin
      Pattern.Refuse(Format(rsFeatureDartCrosses, [OutlineEdge(Pattern, Piece, Index)]));
      Exit(True);
    end;
  end;
  Result := False;
end;

// The edge and its one piece, checked before anything is added
function DartPiece(Pattern: TPattern; const Spec: TDartSpec; out Edge: TEdgeObject; out Piece: TPieceObject): boolean;
var
  Node: TObject;
  Pieces: TPieceObjectArray;
begin
  Edge := nil;
  Piece := nil;
  Node := Pattern.FindNode(Spec.EdgeKey);
  if not (Node is TEdgeObject) or TEdgeObject(Node).IsClosed then
    Exit(Pattern.Refuse(rsFeatureNoDartEdge));
  Edge := TEdgeObject(Node);
  Pieces := PiecesOn(Pattern, Edge.Key);
  if Length(Pieces) = 0 then
    Exit(Pattern.Refuse(Format(rsFeatureDartNotInPiece, [Edge.DisplayName])));
  if Length(Pieces) > 1 then
    Exit(Pattern.Refuse(Format(rsFeatureDartPieces, [Edge.DisplayName])));
  Piece := Pieces[0];
  if Piece.FoldEdgeKey = Edge.Key then
    Exit(Pattern.Refuse(Format(rsFeatureDartFold, [Edge.DisplayName, Piece.DisplayName])));
  Pattern.Evaluate;
  if Piece.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureDartPieceProblem, [Piece.DisplayName, Piece.Message])));
  Result := True;
end;

// The dart's middle and the points its legs leave the edge at, the start's
// side first, checked to lie inside the edge
function AddDartOpening(Pattern: TPattern; Edge: TEdgeObject; const Spec: TDartSpec; var Made: TDartMade): boolean;
var
  Position, Half, NearStart, NearEnd: string;
  Middle, Width, Scale: double;
  Mid, StartLeg, EndLeg: TDraftObject;
begin
  Scale := MILLIMETRES_PER_UNIT[Pattern.Units];
  Position := Trim(Spec.Position);
  if Position = '' then
    Position := Format('%s.length / 2', [Edge.DisplayName]);
  if not Pattern.EvaluateText(Position, Middle) or not Pattern.EvaluateText(Spec.Width, Width) then
    Exit(False);
  Middle := Middle * Scale;
  Width := Width * Scale;
  if Width <= DEFAULT_TOLERANCE then
    Exit(Pattern.Refuse(rsFeatureDartNoWidth));
  if (Middle - Width / 2 <= DEFAULT_TOLERANCE) or (Middle + Width / 2 >= Edge.Length - DEFAULT_TOLERANCE) then
    Exit(Pattern.Refuse(Format(rsFeatureDartTooWide, [LengthWithUnit(Width, Pattern.Units), LengthWithUnit(Middle, Pattern.Units),
      Edge.DisplayName, LengthWithUnit(Edge.Length, Pattern.Units)])));
  Half := Format('(%s) / 2', [Spec.Width]);
  NearStart := Format('(%s) - %s', [Position, Half]);
  NearEnd := Format('(%s) + %s', [Position, Half]);
  // Measured from the end, the point nearer the start is the further one
  if Spec.FromEnd then
  begin
    NearStart := Format('(%s) + %s', [Position, Half]);
    NearEnd := Format('(%s) - %s', [Position, Half]);
  end;
  Mid := Pattern.AddAlongEdgePoint(FreeName(Pattern, DART_MID_NAME), Edge.Key, Spec.FromEnd, amLength, Position);
  if not Assigned(Mid) then
    Exit(False);
  StartLeg := Pattern.AddAlongEdgePoint(FreeName(Pattern, DART_LEG_NAME), Edge.Key, Spec.FromEnd, amLength, NearStart);
  if not Assigned(StartLeg) then
    Exit(False);
  EndLeg := Pattern.AddAlongEdgePoint(FreeName(Pattern, DART_LEG_NAME), Edge.Key, Spec.FromEnd, amLength, NearEnd);
  if not Assigned(EndLeg) then
    Exit(False);
  Made.MidKey := Mid.Key;
  Made.LegPointKeys[0] := StartLeg.Key;
  Made.LegPointKeys[1] := EndLeg.Key;
  Pattern.Evaluate;
  if Mid.State <> esValid then
    Exit(Pattern.Refuse(Mid.Message));
  if StartLeg.State <> esValid then
    Exit(Pattern.Refuse(StartLeg.Message));
  if EndLeg.State <> esValid then
    Exit(Pattern.Refuse(EndLeg.Message));
  Result := True;
end;

// The dart's point: the picked point, or one at the depth from the middle,
// square to the edge (from leg to leg) into the piece
function AddDartApex(Pattern: TPattern; Piece: TPieceObject; const Spec: TDartSpec; var Made: TDartMade): boolean;
var
  Node: TObject;
  StartLeg, EndLeg, Mid: TPointObject;
  Depth: double;
  Travel, Inward: string;
  Apex: TOffsetPoint;
begin
  if Spec.ApexKey <> '' then
  begin
    Node := Pattern.FindNode(Spec.ApexKey);
    if not (Node is TPointObject) then
      Exit(Pattern.Refuse(Format(rsDraftNotAPoint, [Spec.ApexKey])));
    Made.ApexKey := Pattern.UsePoint(Spec.ApexKey);
    Exit(True);
  end;
  if not Pattern.EvaluateText(Spec.Depth, Depth) then
    Exit(False);
  if Depth * MILLIMETRES_PER_UNIT[Pattern.Units] <= DEFAULT_TOLERANCE then
    Exit(Pattern.Refuse(rsFeatureDartNoDepth));
  StartLeg := TPointObject(Pattern.FindNode(Made.LegPointKeys[0]));
  EndLeg := TPointObject(Pattern.FindNode(Made.LegPointKeys[1]));
  Mid := TPointObject(Pattern.FindNode(Made.MidKey));
  Travel := Format('atan2(%0:s.y - %1:s.y, %1:s.x - %0:s.x)', [StartLeg.DisplayName, EndLeg.DisplayName]);
  if PointInPolygon(PolarPoint(Mid.Position, PROBE_DISTANCE, AngleBetween(StartLeg.Position, EndLeg.Position) + RIGHT_ANGLE),
    Piece.Outline) then
    Inward := Format('%s + %d', [Travel, RIGHT_ANGLE])
  else
    Inward := Format('%s - %d', [Travel, RIGHT_ANGLE]);
  Apex := Pattern.AddOffsetPoint(FreeName(Pattern, DART_APEX_NAME), Mid.Key, omPolar, Spec.Depth, Inward);
  if not Assigned(Apex) then
    Exit(False);
  Made.ApexKey := Apex.Key;
  Result := True;
end;

// The legs take the place of the edge's part between them in the piece's
// outline, which stays as construction
function OpenDart(Pattern: TPattern; Edge: TEdgeObject; Piece: TPieceObject; var Made: TDartMade): boolean;
var
  First, Rest, Middle, Last: TSplitPart;
  StartLeg, EndLeg: TLineObject;
  Run: TPiecePath;
  Index: integer;
begin
  StartLeg := Pattern.AddLine(Made.LegPointKeys[0], Made.ApexKey, erOutline);
  if not Assigned(StartLeg) then
    Exit(False);
  EndLeg := Pattern.AddLine(Made.ApexKey, Made.LegPointKeys[1], erOutline);
  if not Assigned(EndLeg) then
    Exit(False);
  Made.LegKeys[0] := StartLeg.Key;
  Made.LegKeys[1] := EndLeg.Key;
  if not Pattern.SplitEdge(Edge.Key, Made.LegPointKeys[0], First, Rest) or not Pattern.SplitEdge(Rest.Key, Made.LegPointKeys[1], Middle, Last) then
    Exit(False);
  Index := Piece.PathIndexOf(Middle.Key);
  if Index < 0 then
    Exit(Pattern.Refuse(Middle.Message));
  if not Pattern.SetEdgeRole(Middle, erConstruction) then
    Exit(False);
  Run := nil;
  SetLength(Run, 2);
  // The way the piece runs along the edge: into the point along one leg, and
  // out along the other
  if Piece.Path[Index].Reversed then
  begin
    Run[0].EdgeKey := EndLeg.Key;
    Run[0].Reversed := True;
    Run[1].EdgeKey := StartLeg.Key;
    Run[1].Reversed := True;
  end
  else
  begin
    Run[0].EdgeKey := StartLeg.Key;
    Run[1].EdgeKey := EndLeg.Key;
  end;
  Result := Pattern.ReplaceInPath(Piece, Middle.Key, Run, False);
end;

// What a dart needs on paper: the seam that closes it, the notches, the hole,
// the centre line and the cap
function MarkDart(Pattern: TPattern; Piece: TPieceObject; const Spec: TDartSpec; var Made: TDartMade): boolean;
var
  SideA, SideB: TSeamSide;
  Seam: TSeamObject;
  Hole: TBetweenPoint;
  Centre: TLineObject;
  Press: TDartPress;
begin
  SideA := nil;
  SideB := nil;
  SetLength(SideA, 1);
  SetLength(SideB, 1);
  SideA[0].PieceKey := Piece.Key;
  SideA[0].EdgeKey := Made.LegKeys[0];
  SideB[0].PieceKey := Piece.Key;
  SideB[0].EdgeKey := Made.LegKeys[1];
  Seam := Pattern.AddSeam(FreeName(Pattern, DART_SEAM_NAME), SideA, SideB);
  if not Assigned(Seam) then
    Exit(False);
  Made.SeamKey := Seam.Key;
  if not Pattern.AddPointNotch(Piece, Made.LegPointKeys[0]) or not Pattern.AddPointNotch(Piece, Made.LegPointKeys[1]) then
    Exit(False);
  if Trim(Spec.HoleInset) <> '' then
  begin
    Hole := Pattern.AddBetweenPoint('', Made.ApexKey, Made.MidKey, amLength, Spec.HoleInset);
    if not Assigned(Hole) or not Pattern.SetMarker(Hole.Key, pmHole) then
      Exit(False);
    Made.HoleKey := Hole.Key;
  end;
  Centre := Pattern.AddLine(Made.MidKey, Made.ApexKey, erFold);
  if not Assigned(Centre) then
    Exit(False);
  Made.CentreKey := Centre.Key;
  Press := dpFirst;
  if Spec.TowardsEnd then
    Press := dpSecond;
  Result := Pattern.SetDartCap(Piece, Made.LegKeys[0], Made.LegKeys[1], Press);
end;

function InsertDart(Pattern: TPattern; const Spec: TDartSpec; out Made: TDartMade): boolean;
var
  Edge: TEdgeObject;
  Piece: TPieceObject;
  Apex: TPointObject;
begin
  Made := Default(TDartMade);
  if not DartPiece(Pattern, Spec, Edge, Piece) then
    Exit(False);
  Made.PieceKey := Piece.Key;
  if not AddDartOpening(Pattern, Edge, Spec, Made) or not AddDartApex(Pattern, Piece, Spec, Made) then
    Exit(False);
  Pattern.Evaluate;
  Apex := TPointObject(Pattern.FindNode(Made.ApexKey));
  if Apex.State <> esValid then
    Exit(Pattern.Refuse(Apex.Message));
  if not PointInPolygon(Apex.Position, Piece.Outline) then
    Exit(Pattern.Refuse(Format(rsFeatureDartApexOutside, [Apex.DisplayName, Piece.DisplayName])));
  if LegsCross(Pattern, Piece, TPointObject(Pattern.FindNode(Made.LegPointKeys[0])).Position, Apex.Position,
    TPointObject(Pattern.FindNode(Made.LegPointKeys[1])).Position) then
    Exit(False);
  if not OpenDart(Pattern, Edge, Piece, Made) then
    Exit(False);
  Pattern.Evaluate;
  if Piece.State <> esValid then
    Exit(Pattern.Refuse(Piece.Message));
  Result := MarkDart(Pattern, Piece, Spec, Made);
  Pattern.Evaluate;
  if Result and (Piece.State <> esValid) then
    Result := Pattern.Refuse(Piece.Message);
end;

initialization
  FormatNumbers := DefaultFormatSettings;
  FormatNumbers.DecimalSeparator := '.';
end.
