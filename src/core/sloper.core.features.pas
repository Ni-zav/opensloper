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
// in a seam. Each is made of ordinary objects, points, split edges,
// allowances, notches and lines, which the user can then change as if they
// had drawn them. Nothing here is saved as a feature.
unit Sloper.Core.Features;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern;

type
  TFeatureKind = (fkZip);

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

const
  ZIP_LENGTH_VARIABLE = 'zip_length';
  ZIP_STOP_NAME = 'ZipStop';
  FLY_SHIELD_NAME = 'FlyShield';
  // As the Automation API names the styles
  ZIP_STYLE_NAMES: array[TZipStyle] of string = ('centred', 'invisible', 'lapped', 'flyFront');

// A zip on the edge with the style's starting widths in the pattern's unit,
// its length the zip_length variable, which InsertZip adds when it is missing
function DefaultZip(Pattern: TPattern; const EdgeKey: string; Style: TZipStyle = zsCentred): TZipSpec;
// Adds the zip's objects and evaluates. False, with the reason in
// Pattern.LastError, when it cannot go there; objects may have been added
// by then, so call it inside a document change and cancel that on failure.
function InsertZip(Pattern: TPattern; const Spec: TZipSpec; out Made: TZipMade): boolean;

resourcestring
  rsFeatureZip = 'Zip';
  rsFeatureZipLength = 'The length of the zip';
  rsFeatureNoEdge = 'Choose an edge of a piece for the zip';
  rsFeatureNotInPiece = '%s is in no piece; a zip goes along a piece''s edge';
  rsFeatureZipTooLong = 'The zip, %s long, does not fit along %s, which is %s';

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

initialization
  FormatNumbers := DefaultFormatSettings;
  FormatNumbers.DecimalSeparator := '.';
end.
