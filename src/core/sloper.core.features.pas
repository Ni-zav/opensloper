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
// in a seam, a dart in a piece's edge, a hem, a facing or buttons. Each is made of ordinary objects, points, split edges,
// allowances, notches and lines, which the user can then change as if they
// had drawn them. Nothing here is saved as a feature.
unit Sloper.Core.Features;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern;

type
  TFeatureKind = (fkZip, fkDart, fkHem, fkFacing, fkButtons);

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

  // Single: turned once, its raw edge overlocked. Double: turned twice, the
  // raw edge turned under. Narrow: a small double hem, as on a shirt. Blind:
  // turned once and sewn by hand or blind stitch, so no topstitching shows.
  THemStyle = (hsSingle, hsDouble, hsNarrow, hsBlind);

  THemSpec = record
    // Edges of one or more pieces; each piece's must run end to end
    EdgeKeys: array of string;
    Style: THemStyle;
    // Formulas in the pattern's unit, with names: how deep the hem is once
    // turned up, how much a double hem turns under besides, and how far the
    // topstitching is from the hem's fold
    Depth, TurnUnder, StitchDistance: string;
    // A notch at each end of the hem, in the neighbouring edge
    Notches: boolean;
  end;

  THemNotch = record
    PieceKey, EdgeKey: string;
  end;

  THemMade = record
    // The pieces hemmed, and the topstitching on each
    PieceKeys, StitchKeys: array of string;
    Notches: array of THemNotch;
    // What is worth checking, though it was done: a hem deeper than its piece
    Problems: array of string;
  end;

  TFacingSpec = record
    // Outline edges of one or more pieces; each piece's must run end to end
    EdgeKeys: array of string;
    // A formula in the pattern's unit, with names: how wide the facing is
    Width: string;
    // Drawn beside the piece, as Move Copy draws it, rather than over it
    Aside: boolean;
    // The material of an interfacing cut as the facing is, '' for none; a
    // name no material has yet adds one
    Interfacing: string;
  end;

  TFacingMade = record
    // On each piece faced, in pattern order: the piece, its facing, the
    // facing's inner edge, its interfacing ('' for none) and the seam
    // joining the facing to the piece
    PieceKeys, FacingKeys, InnerKeys, InterfacingKeys, SeamKeys: array of string;
    // Seams between facings where their pieces are seamed, as at the shoulder
    JoinKeys: array of string;
  end;

  // Horizontal buttonholes run square to the opening, as on shirts and coats;
  // vertical ones along it, as on a placket
  TButtonDirection = (bdHorizontal, bdVertical);

  TButtonsSpec = record
    // The opening's edge on a piece, such as a centre front, along which the
    // buttonholes go, and the buttons too unless ButtonsEdgeKey is given
    EdgeKey: string;
    // The matching edge of another piece the buttons go along, as on
    // separate left and right fronts; '' puts them on EdgeKey, for one piece
    // cut twice
    ButtonsEdgeKey: string;
    // Formulas in the pattern's unit, with names: the button's size and
    // thickness, how many buttons there are (a number), how far the first
    // and last are from the edge's start and end, and the extension's width
    // ('' for none)
    Size, Thickness, Count, First, Last, Extension: string;
    Direction: TButtonDirection;
  end;

  TButtonsMade = record
    // The first and last buttonholes' points, and the buttons' (the same
    // points on one piece)
    TopKey, BottomKey, ButtonTopKey, ButtonBottomKey: string;
    // The repeats of buttonholes and buttons, and the pieces they are on
    HolesKey, ButtonsKey, HolesPieceKey, ButtonsPieceKey: string;
    // Each extension's lines and offset, in the order the paths run
    ExtensionKeys: array of string;
    // What is worth checking, though it was done: a narrow extension
    Problems: array of string;
  end;

const
  ZIP_LENGTH_VARIABLE = 'zip_length';
  HEM_DEPTH_VARIABLE = 'hem_depth';
  FACING_WIDTH_VARIABLE = 'facing_width';
  // A facing and an interfacing are named for the piece: Facing_Front
  FACING_PREFIX = 'Facing_';
  INTERFACING_PREFIX = 'Interfacing_';
  FACING_SEAM_NAME = 'FacingSeam';
  BUTTON_SIZE_VARIABLE = 'button_size';
  BUTTON_THICKNESS_VARIABLE = 'button_thickness';
  BUTTON_COUNT_VARIABLE = 'button_count';
  // A number, not a length, so the same in every unit
  STARTING_BUTTON_COUNT = '5';
  BUTTON_TOP_NAME = 'ButtonTop';
  BUTTON_BOTTOM_NAME = 'ButtonBottom';
  BUTTON_NAME = 'Button';
  BUTTONHOLE_NAME = 'Buttonhole';
  BUTTON_DIRECTION_NAMES: array[TButtonDirection] of string = ('horizontal', 'vertical');
  ZIP_STOP_NAME = 'ZipStop';
  FLY_SHIELD_NAME = 'FlyShield';
  DART_MID_NAME = 'DartMid';
  DART_APEX_NAME = 'DartApex';
  DART_LEG_NAME = 'DartLeg';
  DART_SEAM_NAME = 'Dart';
  // As the Automation API names the styles
  ZIP_STYLE_NAMES: array[TZipStyle] of string = ('centred', 'invisible', 'lapped', 'flyFront');
  HEM_STYLE_NAMES: array[THemStyle] of string = ('single', 'double', 'narrow', 'blind');

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
// A hem along the edges in the style's starting widths: its depth the
// hem_depth variable, which InsertHem adds when it is missing, except for a
// narrow hem, and the topstitching 3 mm short of the depth
function DefaultHem(Pattern: TPattern; const EdgeKeys: array of string; Style: THemStyle = hsSingle): THemSpec;
// The topstitching's starting distance for a hem of this depth: 3 mm short of
// it, worked out for a number and as a formula on a formula
function HemStitchDistance(Pattern: TPattern; const Depth: string): string;
// Adds the hem and evaluates, as InsertZip does: on each piece its edges'
// allowance at the depth (and the turn-under), their ends mirroring the
// neighbouring edges', the topstitching inside the piece, and a notch at
// each end in the neighbouring edge
function InsertHem(Pattern: TPattern; const Spec: THemSpec; out Made: THemMade): boolean;
// A facing along the edges, in place, its width the facing_width variable,
// which InsertFacing adds when it is missing, with no interfacing
function DefaultFacing(Pattern: TPattern; const EdgeKeys: array of string): TFacingSpec;
// Adds a facing on each piece and evaluates, as InsertZip does: the inner
// edge at the width, meeting the edges either side, which are split there;
// the facing piece round the run, cut as the piece is; the seam joining it
// to the piece; the piece's notches along it; seams between facings where
// their pieces are seamed; and an interfacing if asked for
function InsertFacing(Pattern: TPattern; const Spec: TFacingSpec; out Made: TFacingMade): boolean;
// Buttons along the edge, on one piece cut twice, with horizontal holes and
// no extension: their size, thickness and count the button_size,
// button_thickness and button_count variables, which InsertButtons adds
// when they are missing
function DefaultButtons(Pattern: TPattern; const EdgeKey: string): TButtonsSpec;
// Adds the buttons and evaluates, as InsertZip does: ButtonTop and
// ButtonBottom along the edge, a repeat of buttonholes between them and one
// of buttons (on the other piece's edge when there is one), and the
// extension if asked for, the edge becoming a placement line
function InsertButtons(Pattern: TPattern; const Spec: TButtonsSpec; out Made: TButtonsMade): boolean;

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
  rsFeatureHem = 'Hem';
  rsFeatureHemDepth = 'The depth of the hem, turned up';
  rsFeatureNoHemEdge = 'Choose one or more edges of pieces for the hem';
  rsFeatureHemNotInPiece = '%s is in no piece; a hem goes along a piece''s edge';
  rsFeatureHemFold = '%s is the fold of %s, which cannot be hemmed';
  rsFeatureHemPieceProblem = '%s has a problem to put right first: %s';
  rsFeatureHemNoDepth = 'A hem needs a depth above 0';
  rsFeatureHemTooDeep = 'The hem, %s deep, is deeper than %s is tall above it (%s)';
  rsFeatureFacing = 'Facing';
  rsFeatureFacingWidth = 'The width of the facings';
  rsFeatureNoFacingEdge = 'Choose one or more edges of pieces for the facing';
  rsFeatureFacingNotInPiece = '%s is in no piece; a facing goes along a piece''s edge';
  rsFeatureFacingFold = '%s is the fold of %s, which cannot be faced';
  rsFeatureFacingPieceProblem = '%s has a problem to put right first: %s';
  rsFeatureFacingWhole = 'The edges go all round %s; that is a lining, not a facing';
  rsFeatureFacingOneNeighbour = 'Only %s is left of %s beside the edges; a facing needs an edge at each end of them';
  rsFeatureFacingNoWidth = 'A facing needs a width above 0';
  rsFeatureFacingTooWide = 'The facing is wider than %s there: %s';
  rsFeatureButtons = 'Buttons';
  rsFeatureButtonSize = 'The size of the buttons, across';
  rsFeatureButtonThickness = 'The thickness of the buttons, which a buttonhole is longer by';
  rsFeatureButtonCount = 'How many buttons there are';
  rsFeatureNoButtonEdge = 'Choose an edge of a piece for the buttons, such as a centre front';
  rsFeatureButtonsNotInPiece = '%s is in no piece; buttons go along a piece''s edge';
  rsFeatureButtonsPieces = '%s is in more than one piece; buttons go along one';
  rsFeatureButtonsFold = '%s is the fold of %s, where buttons cannot go';
  rsFeatureButtonsSamePiece = 'The buttons'' edge is on %s too; choose the other front''s edge, or none';
  rsFeatureButtonsNoCount = 'There must be at least one button';
  rsFeatureButtonsNoRoom = 'The first button %s from one end and the last %s from the other leave no room along %s (%s long)';
  rsFeatureButtonsNarrow = 'The extension, %s wide, is narrower than half a button';

implementation

uses
  SysUtils, Math, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.EvalTypes, Sloper.Core.Units,
  Sloper.Core.Geometry, Sloper.Core.Transform, Sloper.Core.Bounds, Sloper.Core.Materials;

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

function DefaultHem(Pattern: TPattern; const EdgeKeys: array of string; Style: THemStyle): THemSpec;
var
  Index: integer;
begin
  Result := Default(THemSpec);
  SetLength(Result.EdgeKeys, Length(EdgeKeys));
  for Index := 0 to High(EdgeKeys) do
    Result.EdgeKeys[Index] := EdgeKeys[Index];
  Result.Style := Style;
  Result.TurnUnder := STARTING_LENGTHS[slHemTurnUnder, Pattern.Units];
  Result.Notches := True;
  // A narrow hem is too small to share a depth with deeper ones
  if Style = hsNarrow then
    Result.Depth := STARTING_LENGTHS[slNarrowHemDepth, Pattern.Units]
  else
    Result.Depth := '#' + HEM_DEPTH_VARIABLE;
  Result.StitchDistance := HemStitchDistance(Pattern, Result.Depth);
end;

type
  TRunEdgeArrays = array of TRunEdgeArray;
  TOffsetSides = array of TOffsetSide;

// A formula as a term of a sum: a name or number as it is, else in brackets
function Term(const Text: string): string;
var
  Letter: char;
begin
  Result := Trim(Text);
  for Letter in Result do
    if not (Letter in ['A'..'Z', 'a'..'z', '0'..'9', '_', '#', '@', '.']) then
      Exit('(' + Result + ')');
end;

function HasKey(const Keys: TStringArray; const Key: string): boolean;
var
  Item: string;
begin
  for Item in Keys do
    if Item = Key then
      Exit(True);
  Result := False;
end;

function HemStitchDistance(Pattern: TPattern; const Depth: string): string;
var
  Value: double;
  Back: string;
begin
  Back := STARTING_LENGTHS[slHemStitchBack, Pattern.Units];
  if TryStrToFloat(Trim(Depth), Value, FormatNumbers) then
    Result := FloatToStr(Value - StrToFloat(Back, FormatNumbers), FormatNumbers)
  else
    Result := Format('%s - %s', [Term(Depth), Back]);
end;

// The hem_depth variable the starting formula names, when it is missing
function AddDepthVariable(Pattern: TPattern; const Spec: THemSpec): boolean;
begin
  Result := True;
  if (Pos(LowerCase('#' + HEM_DEPTH_VARIABLE), LowerCase(Spec.Depth + ' ' + Spec.StitchDistance)) > 0) and not
    Assigned(Pattern.FindVariable(HEM_DEPTH_VARIABLE)) then
    Result := Assigned(Pattern.AddVariable(HEM_DEPTH_VARIABLE, STARTING_LENGTHS[slHemDepth, Pattern.Units], rsFeatureHemDepth));
end;

// The pieces the edges are on, in pattern order, each with the run its
// edges make and the side of it that is inside, checked before anything is
// added
function HemPieces(Pattern: TPattern; const Spec: THemSpec; out Pieces: TPieceObjectArray; out Runs: TRunEdgeArrays;
  out Sides: TOffsetSides): boolean;
var
  Key: string;
  Node: TObject;
  Piece, Other: TPieceObject;
  Keys: TStringArray;
  Index: integer;
begin
  Pieces := nil;
  Runs := nil;
  Sides := nil;
  if Length(Spec.EdgeKeys) = 0 then
    Exit(Pattern.Refuse(rsFeatureNoHemEdge));
  for Key in Spec.EdgeKeys do
  begin
    Node := Pattern.FindNode(Key);
    if not (Node is TEdgeObject) then
      Exit(Pattern.Refuse(rsFeatureNoHemEdge));
    if Length(PiecesOn(Pattern, Key)) = 0 then
      Exit(Pattern.Refuse(Format(rsFeatureHemNotInPiece, [TEdgeObject(Node).DisplayName])));
    for Other in PiecesOn(Pattern, Key) do
      if Other.FoldEdgeKey = Key then
        Exit(Pattern.Refuse(Format(rsFeatureHemFold, [TEdgeObject(Node).DisplayName, Other.DisplayName])));
  end;
  Pattern.Evaluate;
  for Piece in Pattern.PieceList do
  begin
    Keys := nil;
    // Each edge once, in the order given
    for Key in Spec.EdgeKeys do
      if (Piece.PathIndexOf(Key) >= 0) and not HasKey(Keys, Key) then
        Insert(Key, Keys, Length(Keys));
    if Length(Keys) = 0 then
      Continue;
    if Piece.State <> esValid then
      Exit(Pattern.Refuse(Format(rsFeatureHemPieceProblem, [Piece.DisplayName, Piece.Message])));
    Index := Length(Pieces);
    Insert(Piece, Pieces, Index);
    SetLength(Runs, Index + 1);
    SetLength(Sides, Index + 1);
    if not Pattern.PieceRun(Piece, Keys, True, Runs[Index], Sides[Index]) then
      Exit(False);
  end;
  Result := True;
end;

// A notch where the hem meets the edge beside it in the path, at that
// edge's end, so the hem turns up there
function AddHemNotch(Pattern: TPattern; Piece: TPieceObject; PathIndex: integer; AtPathEnd: boolean; var Made: THemMade): boolean;
var
  Entry: TPieceEdge;
  Edge: TEdgeObject;
  Position: string;
begin
  Entry := Piece.Path[PathIndex];
  if Entry.EdgeKey = Piece.FoldEdgeKey then
    Exit(True);
  Edge := TEdgeObject(Pattern.FindNode(Entry.EdgeKey));
  // The edge's end the path reaches it at, or leaves it from
  if AtPathEnd <> Entry.Reversed then
    Position := Format('%s.length', [Edge.DisplayName])
  else
    Position := '0';
  if not Pattern.AddEdgeNotch(Piece, Edge.Key, Position) then
    Exit(False);
  SetLength(Made.Notches, Length(Made.Notches) + 1);
  Made.Notches[High(Made.Notches)].PieceKey := Piece.Key;
  Made.Notches[High(Made.Notches)].EdgeKey := Edge.Key;
  Result := True;
end;

// Where the run starts and ends, as the path goes
procedure RunEnds(Pattern: TPattern; const Run: TRunEdgeArray; out First, Last: TVec2);
var
  Edge: TEdgeObject;
begin
  Edge := TEdgeObject(Pattern.FindNode(Run[0].EdgeKey));
  if Run[0].Reversed then
    First := Edge.PointAtLength(Edge.Length)
  else
    First := Edge.PointAtLength(0);
  Edge := TEdgeObject(Pattern.FindNode(Run[High(Run)].EdgeKey));
  if Run[High(Run)].Reversed then
    Last := Edge.PointAtLength(0)
  else
    Last := Edge.PointAtLength(Edge.Length);
end;

// A hem deeper than the piece is tall above the line between its ends
procedure CheckHemDepth(Pattern: TPattern; Piece: TPieceObject; const Run: TRunEdgeArray; Depth: double; var Made: THemMade);
var
  First, Last, Point: TVec2;
  Hem: TLine2;
  Height: double;
begin
  if Length(Run) = Length(Piece.Path) then
    Exit;
  RunEnds(Pattern, Run, First, Last);
  if PointsNear(First, Last) then
    Exit;
  Hem := Line2(First, Last);
  Height := 0;
  for Point in Piece.Outline do
    Height := Max(Height, Distance(Point, Hem.ClosestPoint(Point, True)));
  if Depth >= Height then
    Insert(Format(rsFeatureHemTooDeep, [LengthWithUnit(Depth, Pattern.Units), Piece.DisplayName, LengthWithUnit(Height,
      Pattern.Units)]), Made.Problems, Length(Made.Problems));
end;

// On one piece: the allowance and mirrored ends of each edge, the
// topstitching and the notches
function HemPiece(Pattern: TPattern; Piece: TPieceObject; const Run: TRunEdgeArray; Side: TOffsetSide; const Spec: THemSpec;
  const Allowance: string; var Made: THemMade): boolean;
var
  Item: TRunEdge;
  PathIndex, Count: integer;
  Stitch: TOffsetEdge;
begin
  Insert(Piece.Key, Made.PieceKeys, Length(Made.PieceKeys));
  for Item in Run do
  begin
    PathIndex := Piece.PathIndexOf(Item.EdgeKey);
    if not Pattern.SetEdgeAllowance(Piece, PathIndex, Allowance) or not Pattern.SetAllowanceEnd(Piece, PathIndex, aeMirror) then
      Exit(False);
  end;
  if (Spec.Style <> hsBlind) and (Trim(Spec.StitchDistance) <> '') then
  begin
    Stitch := Pattern.AddOffsetRun(Run, Spec.StitchDistance, Side, erStitch);
    if not Assigned(Stitch) then
      Exit(False);
    Insert(Stitch.Key, Made.StitchKeys, Length(Made.StitchKeys));
  end;
  Count := Length(Piece.Path);
  if not Spec.Notches or (Length(Run) = Count) then
    Exit(True);
  Result := AddHemNotch(Pattern, Piece, (Piece.PathIndexOf(Run[0].EdgeKey) + Count - 1) mod Count, True, Made) and
    AddHemNotch(Pattern, Piece, (Piece.PathIndexOf(Run[High(Run)].EdgeKey) + 1) mod Count, False, Made);
end;

function InsertHem(Pattern: TPattern; const Spec: THemSpec; out Made: THemMade): boolean;
var
  Pieces: TPieceObjectArray;
  Runs: TRunEdgeArrays;
  Sides: TOffsetSides;
  Allowance: string;
  Depth: double;
  Index: integer;
  Stitch: TDraftObject;
begin
  Made := Default(THemMade);
  if not HemPieces(Pattern, Spec, Pieces, Runs, Sides) or not AddDepthVariable(Pattern, Spec) then
    Exit(False);
  Pattern.Evaluate;
  if not Pattern.EvaluateText(Spec.Depth, Depth) then
    Exit(False);
  Depth := Depth * MILLIMETRES_PER_UNIT[Pattern.Units];
  if Depth <= DEFAULT_TOLERANCE then
    Exit(Pattern.Refuse(rsFeatureHemNoDepth));
  Allowance := Trim(Spec.Depth);
  if Spec.Style in [hsDouble, hsNarrow] then
    Allowance := Format('%s + %s', [Term(Spec.Depth), Term(Spec.TurnUnder)]);
  for Index := 0 to High(Pieces) do
    if not HemPiece(Pattern, Pieces[Index], Runs[Index], Sides[Index], Spec, Allowance, Made) then
      Exit(False);
  Pattern.Evaluate;
  for Index := 0 to High(Pieces) do
  begin
    if Pieces[Index].State <> esValid then
      Exit(Pattern.Refuse(Pieces[Index].Message));
    CheckHemDepth(Pattern, Pieces[Index], Runs[Index], Depth, Made);
  end;
  for Index := 0 to High(Made.StitchKeys) do
  begin
    Stitch := TDraftObject(Pattern.FindNode(Made.StitchKeys[Index]));
    if Stitch.State <> esValid then
      Exit(Pattern.Refuse(Stitch.Message));
  end;
  Result := True;
end;

function DefaultFacing(Pattern: TPattern; const EdgeKeys: array of string): TFacingSpec;
var
  Index: integer;
begin
  Result := Default(TFacingSpec);
  SetLength(Result.EdgeKeys, Length(EdgeKeys));
  for Index := 0 to High(EdgeKeys) do
    Result.EdgeKeys[Index] := EdgeKeys[Index];
  Result.Width := '#' + FACING_WIDTH_VARIABLE;
end;

type
  // One piece's facing as it is worked out
  TFacingPlan = record
    Piece: TPieceObject;
    // The edges faced, as the piece's path runs, and the side inside it
    Run: TRunEdgeArray;
    Side: TOffsetSide;
    // The edges of the piece's path the inner edge meets before and after
    // the run, as they were: those beside it, or further on past short ones,
    // as past the step out to a button extension
    BeforeKey, AfterKey: string;
    BeforeReversed, AfterReversed: boolean;
    // The edges passed over to reach them, which the facing takes whole, in
    // the order the path runs
    BeforeWhole, AfterWhole: TPiecePath;
    // The facing's inner edge, the neighbours' parts beside the run, and the
    // facing's path round them all
    InnerKey, BeforePart, AfterPart: string;
    // The neighbours' other parts
    BeforeFar, AfterFar: string;
    Path: TPiecePath;
    // What the facing uses for each object of Path and its notches: the
    // object itself, or its copy when the facing is moved aside
    Sources, Copies: TStringArray;
    FacingKey: string;
  end;

  TFacingPlans = array of TFacingPlan;

// The facing's key for one of the piece's objects
function FacingKeyFor(const Plan: TFacingPlan; const Key: string): string;
var
  Index: integer;
begin
  for Index := 0 to High(Plan.Sources) do
    if Plan.Sources[Index] = Key then
      Exit(Plan.Copies[Index]);
  Result := Key;
end;

// The facing_width variable the starting formula names, when it is missing
function AddFacingVariable(Pattern: TPattern; const Spec: TFacingSpec): boolean;
begin
  Result := True;
  if (Pos(LowerCase('#' + FACING_WIDTH_VARIABLE), LowerCase(Spec.Width)) > 0) and not Assigned(Pattern.FindVariable(FACING_WIDTH_VARIABLE)) then
    Result := Assigned(Pattern.AddVariable(FACING_WIDTH_VARIABLE, STARTING_LENGTHS[slFacingWidth, Pattern.Units], rsFeatureFacingWidth));
end;

// One piece's run and the edges either side of it, checked before anything
// is added
function PlanFacing(Pattern: TPattern; Piece: TPieceObject; const Keys: TStringArray; out Plan: TFacingPlan): boolean;
var
  Count, Before, After: integer;
  Item: TRunEdge;
begin
  Plan := Default(TFacingPlan);
  Plan.Piece := Piece;
  if Piece.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureFacingPieceProblem, [Piece.DisplayName, Piece.Message])));
  Count := Length(Piece.Path);
  if Length(Keys) >= Count then
    Exit(Pattern.Refuse(Format(rsFeatureFacingWhole, [Piece.DisplayName])));
  if not Pattern.PieceRun(Piece, Keys, True, Plan.Run, Plan.Side) then
    Exit(False);
  for Item in Plan.Run do
    if Item.EdgeKey = Piece.FoldEdgeKey then
      Exit(Pattern.Refuse(Format(rsFeatureFacingFold, [Pattern.FindNode(Item.EdgeKey).DisplayName, Piece.DisplayName])));
  Before := (Piece.PathIndexOf(Plan.Run[0].EdgeKey) + Count - 1) mod Count;
  After := (Piece.PathIndexOf(Plan.Run[High(Plan.Run)].EdgeKey) + 1) mod Count;
  if Before = After then
    Exit(Pattern.Refuse(Format(rsFeatureFacingOneNeighbour, [Pattern.FindNode(Piece.Path[Before].EdgeKey).DisplayName,
      Piece.DisplayName])));
  Plan.BeforeKey := Piece.Path[Before].EdgeKey;
  Plan.BeforeReversed := Piece.Path[Before].Reversed;
  Plan.AfterKey := Piece.Path[After].EdgeKey;
  Plan.AfterReversed := Piece.Path[After].Reversed;
  Result := True;
end;

// The pieces the edges are on, in pattern order, each with its plan
function FacingPlans(Pattern: TPattern; const Spec: TFacingSpec; out Plans: TFacingPlans): boolean;
var
  Key: string;
  Node: TObject;
  Piece: TPieceObject;
  Keys: TStringArray;
begin
  Plans := nil;
  if Length(Spec.EdgeKeys) = 0 then
    Exit(Pattern.Refuse(rsFeatureNoFacingEdge));
  for Key in Spec.EdgeKeys do
  begin
    Node := Pattern.FindNode(Key);
    if not (Node is TEdgeObject) then
      Exit(Pattern.Refuse(rsFeatureNoFacingEdge));
    if Length(PiecesOn(Pattern, Key)) = 0 then
      Exit(Pattern.Refuse(Format(rsFeatureFacingNotInPiece, [TEdgeObject(Node).DisplayName])));
  end;
  Pattern.Evaluate;
  for Piece in Pattern.PieceList do
  begin
    Keys := nil;
    for Key in Spec.EdgeKeys do
      if (Piece.PathIndexOf(Key) >= 0) and not HasKey(Keys, Key) then
        Insert(Key, Keys, Length(Keys));
    if Length(Keys) = 0 then
      Continue;
    SetLength(Plans, Length(Plans) + 1);
    if not PlanFacing(Pattern, Piece, Keys, Plans[High(Plans)]) then
      Exit(False);
  end;
  Result := True;
end;

// The part of a neighbouring edge, split at the point, that runs to the run:
// the path runs along the edge before the run to its far end, and along the
// edge after it from its near end
function SplitNeighbour(Pattern: TPattern; const EdgeKey, PointKey: string; NearStart: boolean; out PartKey, FarKey: string): boolean;
var
  First, Second: TSplitPart;
begin
  PartKey := '';
  FarKey := '';
  if not Pattern.SplitEdge(EdgeKey, PointKey, First, Second) then
    Exit(False);
  PartKey := Second.Key;
  FarKey := First.Key;
  if NearStart then
  begin
    PartKey := First.Key;
    FarKey := Second.Key;
  end;
  Result := True;
end;

procedure AddPathEntry(var Path: TPiecePath; const EdgeKey: string; Reversed: boolean);
begin
  SetLength(Path, Length(Path) + 1);
  Path[High(Path)] := Default(TPieceEdge);
  Path[High(Path)].EdgeKey := EdgeKey;
  Path[High(Path)].Reversed := Reversed;
end;

// The inner edge at the width, meeting the edges either side of the run,
// which are split where it meets them; and the facing's path: the run, the
// part of the edge after it, the inner edge back and the part of the edge
// before it
// Whether the edge lies within the facing's width of the run all along, as
// a short step does, so the facing can take it whole
function WithinFacing(Pattern: TPattern; const Plan: TFacingPlan; Edge: TEdgeObject; Width: double): boolean;

  function Near(const Point: TVec2): boolean;
  var
    Item: TRunEdge;
    Position, Offset: double;
  begin
    for Item in Plan.Run do
    begin
      TEdgeObject(Pattern.FindNode(Item.EdgeKey)).Locate(Point, Position, Offset);
      if Offset <= Width + DEFAULT_TOLERANCE then
        Exit(True);
    end;
    Result := False;
  end;

begin
  Result := Near(Edge.PointAtLength(0)) and Near(Edge.PointAtLength(Edge.Length));
end;

// The edges the inner edge, carried on straight, meets going on round the
// path from each end of the run: the first it reaches each way, past short
// edges within the facing's width, which it takes whole
function ChooseFacingLimits(Pattern: TPattern; Inner: TOffsetEdge; Width: double; var Plan: TFacingPlan): boolean;
var
  Path: TPiecePath;
  Count, RunStart, RunEnd, Index, EndIndex: integer;
  Hit: TEdgeCrossing;
  Found: boolean;
  Edge: TEdgeObject;
begin
  Path := Plan.Piece.Path;
  Count := Length(Path);
  RunStart := Plan.Piece.PathIndexOf(Plan.Run[0].EdgeKey);
  RunEnd := Plan.Piece.PathIndexOf(Plan.Run[High(Plan.Run)].EdgeKey);
  Plan.AfterWhole := nil;
  Plan.BeforeWhole := nil;
  // On from the end, short of the edge before the run, which the start needs
  Index := (RunEnd + 1) mod Count;
  Found := False;
  while not Found and (Index <> (RunStart + Count - 1) mod Count) do
  begin
    Edge := TEdgeObject(Pattern.FindNode(Path[Index].EdgeKey));
    Found := OffsetLimitCrossing(Inner, Edge, True, Hit);
    if not Found and not WithinFacing(Pattern, Plan, Edge, Width) then
      Break;
    if not Found then
    begin
      Insert(Path[Index], Plan.AfterWhole, Length(Plan.AfterWhole));
      Index := (Index + 1) mod Count;
    end;
  end;
  if not Found then
    Exit(Pattern.Refuse(Format(rsFeatureFacingTooWide, [Plan.Piece.DisplayName, Format(rsDraftOffsetEndMisses,
      [Pattern.FindNode(Plan.AfterKey).DisplayName])])));
  EndIndex := Index;
  // Back from the start, short of the edge the end meets
  Index := (RunStart + Count - 1) mod Count;
  Found := False;
  while not Found and (Index <> EndIndex) do
  begin
    Edge := TEdgeObject(Pattern.FindNode(Path[Index].EdgeKey));
    Found := OffsetLimitCrossing(Inner, Edge, False, Hit);
    if not Found and not WithinFacing(Pattern, Plan, Edge, Width) then
      Break;
    if not Found then
    begin
      Insert(Path[Index], Plan.BeforeWhole, 0);
      Index := (Index + Count - 1) mod Count;
    end;
  end;
  if not Found then
    Exit(Pattern.Refuse(Format(rsFeatureFacingTooWide, [Plan.Piece.DisplayName, Format(rsDraftOffsetStartMisses,
      [Pattern.FindNode(Plan.BeforeKey).DisplayName])])));
  Plan.BeforeKey := Path[Index].EdgeKey;
  Plan.BeforeReversed := Path[Index].Reversed;
  Plan.AfterKey := Path[EndIndex].EdgeKey;
  Plan.AfterReversed := Path[EndIndex].Reversed;
  Inner.SetLimits(Plan.BeforeKey, Plan.AfterKey);
  Result := True;
end;

function AddFacingInner(Pattern: TPattern; const Spec: TFacingSpec; var Plan: TFacingPlan): boolean;
var
  Inner: TOffsetEdge;
  StartPoint, EndPoint: TDraftObject;
  Before, After: TEdgeObject;
  Item: TRunEdge;
  Entry: TPieceEdge;
  Width: double;
begin
  Inner := Pattern.AddOffsetRun(Plan.Run, Spec.Width, Plan.Side, erOutline);
  if not Assigned(Inner) then
    Exit(False);
  Plan.InnerKey := Inner.Key;
  Pattern.Evaluate;
  if Inner.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureFacingTooWide, [Plan.Piece.DisplayName, Inner.Message])));
  if not Pattern.EvaluateText(Spec.Width, Width) or not ChooseFacingLimits(Pattern, Inner, Width * MILLIMETRES_PER_UNIT[Pattern.Units],
    Plan) then
    Exit(False);
  Pattern.Evaluate;
  if Inner.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureFacingTooWide, [Plan.Piece.DisplayName, Inner.Message])));
  StartPoint := Pattern.AddAlongEdgePoint('', Inner.Key, False, amLength, '0');
  EndPoint := Pattern.AddAlongEdgePoint('', Inner.Key, True, amLength, '0');
  if not Assigned(StartPoint) or not Assigned(EndPoint) then
    Exit(False);
  // The run starts at the far end of the edge before it, as the path goes
  if not SplitNeighbour(Pattern, Plan.BeforeKey, StartPoint.Key, Plan.BeforeReversed, Plan.BeforePart, Plan.BeforeFar) or
    not SplitNeighbour(Pattern, Plan.AfterKey, EndPoint.Key, not Plan.AfterReversed, Plan.AfterPart, Plan.AfterFar) then
    Exit(False);
  Pattern.Evaluate;
  Before := TEdgeObject(Pattern.FindNode(Plan.BeforePart));
  After := TEdgeObject(Pattern.FindNode(Plan.AfterPart));
  if Before.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureFacingTooWide, [Plan.Piece.DisplayName, Before.Message])));
  if After.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureFacingTooWide, [Plan.Piece.DisplayName, After.Message])));
  Plan.Path := nil;
  for Item in Plan.Run do
    AddPathEntry(Plan.Path, Item.EdgeKey, Item.Reversed);
  for Entry in Plan.AfterWhole do
    AddPathEntry(Plan.Path, Entry.EdgeKey, Entry.Reversed);
  AddPathEntry(Plan.Path, Plan.AfterPart, Plan.AfterReversed);
  AddPathEntry(Plan.Path, Plan.InnerKey, True);
  AddPathEntry(Plan.Path, Plan.BeforePart, Plan.BeforeReversed);
  for Entry in Plan.BeforeWhole do
    AddPathEntry(Plan.Path, Entry.EdgeKey, Entry.Reversed);
  Result := True;
end;

// Whether a point lies on one of the facing's edges, as drawn on the piece
function OnFacingPath(Pattern: TPattern; const Plan: TFacingPlan; const PointKey: string): boolean;
var
  Node: TObject;
  Entry: TPieceEdge;
  Position, Offset: double;
begin
  Node := Pattern.FindNode(PointKey);
  if not (Node is TPointObject) or not TPointObject(Node).HasResult then
    Exit(False);
  for Entry in Plan.Path do
  begin
    TEdgeObject(Pattern.FindNode(Entry.EdgeKey)).Locate(TPointObject(Node).Position, Position, Offset);
    if Offset <= NOTCH_POINT_TOLERANCE then
      Exit(True);
  end;
  Result := False;
end;

// How wide the piece's cutting line is, in mm
function CutLineWidth(Piece: TPieceObject): double;
var
  Point: TVec2;
  Left, Right: double;
begin
  if Length(Piece.CutLine) = 0 then
    Exit(0);
  Left := Piece.CutLine[0].X;
  Right := Left;
  for Point in Piece.CutLine do
  begin
    Left := Min(Left, Point.X);
    Right := Max(Right, Point.X);
  end;
  Result := Right - Left;
end;

// Moved aside: the facing's edges, and the points its notches are at, copied
// to the right of the piece, and the copies noted for the facing to use. The
// inner edge on the piece becomes construction, to show where the facing goes.
function MoveFacingAside(Pattern: TPattern; var Plan: TFacingPlan): boolean;
var
  Spec: TTransformSpec;
  Transform: TTransformObject;
  Entry: TPieceEdge;
  Notch: TPieceNotch;
  Copied: TDraftObject;
  Sources: TStringArray;
begin
  Sources := nil;
  for Entry in Plan.Path do
    Insert(Entry.EdgeKey, Sources, Length(Sources));
  for Notch in Plan.Piece.Notches do
    if (Notch.PointKey <> '') and not (Pattern.FindNode(Notch.PointKey) is TRepeatPoint) and not HasKey(Sources, Notch.PointKey) and
      OnFacingPath(Pattern, Plan, Notch.PointKey) then
      Insert(Notch.PointKey, Sources, Length(Sources));
  Spec := Default(TTransformSpec);
  Spec.Kind := tkMove;
  Spec.Sources := Sources;
  // Clear of the piece's cutting line, so their allowances do not meet
  Spec.DX := MoveAsideWidthText(Pattern, CutLineWidth(Plan.Piece));
  Spec.DY := '0';
  Transform := Pattern.AddTransform(Spec);
  if not Assigned(Transform) then
    Exit(False);
  Plan.Sources := nil;
  Plan.Copies := nil;
  for Copied in Pattern.CopiesOf(Transform) do
  begin
    if Copied is TEdgeCopy then
      Insert(TEdgeCopy(Copied).Source, Plan.Sources, Length(Plan.Sources))
    else if Copied is TPointCopy then
      Insert(TPointCopy(Copied).Source, Plan.Sources, Length(Plan.Sources))
    else
      Continue;
    Insert(Copied.Key, Plan.Copies, Length(Plan.Copies));
  end;
  Result := Pattern.SetEdgeRole(TEdgeObject(Pattern.FindNode(Plan.InnerKey)), erConstruction);
end;

// The facing's path, with the copies when it is moved aside
function FacingPath(const Plan: TFacingPlan): TPiecePath;
var
  Index: integer;
begin
  Result := Copy(Plan.Path);
  for Index := 0 to High(Result) do
    Result[Index].EdgeKey := FacingKeyFor(Plan, Result[Index].EdgeKey);
end;

// A piece cut as the faced piece is: on its grain, from its material unless
// given another, as many times and mirrored as it is, and on the fold when
// the facing runs to the piece's fold
function AddFacingPiece(Pattern: TPattern; const Plan: TFacingPlan; const AName: string; Material: TPatternMaterial): TPieceObject;
var
  Garment: TPieceObject;
  Grain, Fold: string;
  Index, GarmentIndex: integer;
begin
  Garment := Plan.Piece;
  Result := Pattern.AddPiece(FreeName(Pattern, AName + Garment.Name), FacingPath(Plan), Pattern.FormulaText(Garment,
    PIECE_ALLOWANCE_FIELD));
  if not Assigned(Result) then
    Exit;
  // The piece's own allowances on the edges it shares with the facing
  for Index := 0 to High(Plan.Path) do
  begin
    GarmentIndex := Garment.PathIndexOf(Plan.Path[Index].EdgeKey);
    if (GarmentIndex >= 0) and Garment.HasOverride(GarmentIndex) then
      if not Pattern.SetEdgeAllowance(Result, Index, Pattern.FormulaText(Garment, Garment.OverrideField(GarmentIndex))) then
        Exit(nil);
  end;
  case Garment.GrainKind of
    gkAngle:
      Grain := Pattern.FormulaText(Garment, GRAIN_ANGLE_FIELD);
    gkPoints:
      // The angle of the piece's grainline, through the facing's middle
      Grain := Format('atan2(%0:s.y - %1:s.y, %1:s.x - %0:s.x)', [Pattern.FindNode(Garment.GrainStartKey).DisplayName,
        Pattern.FindNode(Garment.GrainEndKey).DisplayName]);
    else
      Grain := '';
  end;
  if Grain = '' then
    Pattern.ClearGrain(Result)
  else if not Pattern.SetGrainAngle(Result, Grain) then
    Exit(nil);
  if not Assigned(Material) then
    Material := Pattern.MaterialOf(Garment);
  Pattern.SetPieceMaterial(Result, Material);
  if not Pattern.SetCut(Result, Garment.CutCount, Garment.Mirrored) then
    Exit(nil);
  // On the fold along the fold's part, or the fold itself when it is taken whole
  Fold := '';
  if Garment.FoldEdgeKey = Plan.BeforeKey then
    Fold := Plan.BeforePart
  else if Garment.FoldEdgeKey = Plan.AfterKey then
    Fold := Plan.AfterPart
  else
    for Index := 0 to High(Plan.Path) do
      if (Garment.FoldEdgeKey <> '') and (Plan.Path[Index].EdgeKey = Garment.FoldEdgeKey) then
        Fold := Garment.FoldEdgeKey;
  if (Fold <> '') and not Pattern.SetFoldEdge(Result, FacingKeyFor(Plan, Fold)) then
    Exit(nil);
end;

// The piece's notches that lie on the facing's edges, on the facing too
function CopyFacingNotches(Pattern: TPattern; const Plan: TFacingPlan; Facing: TPieceObject): boolean;
var
  Index: integer;
  Notch: TPieceNotch;
  Key: string;
  Aside: boolean;
begin
  Aside := Length(Plan.Copies) > 0;
  for Index := 0 to High(Plan.Piece.Notches) do
  begin
    Notch := Plan.Piece.Notches[Index];
    if Notch.PointKey <> '' then
    begin
      // Moved aside, a point that could not be copied, as a repeat's, is left out
      Key := FacingKeyFor(Plan, Notch.PointKey);
      if OnFacingPath(Pattern, Plan, Notch.PointKey) and (not Aside or (Key <> Notch.PointKey)) and not Pattern.AddPointNotch(Facing, Key) then
        Exit(False);
    end
    else if Facing.PathIndexOf(FacingKeyFor(Plan, Notch.EdgeKey)) >= 0 then
      if not Pattern.AddEdgeNotch(Facing, FacingKeyFor(Plan, Notch.EdgeKey), Pattern.FormulaText(Plan.Piece,
        Plan.Piece.NotchField(Index))) then
        Exit(False);
  end;
  Result := True;
end;

// The seam between the facing's run and the piece's, both running the way
// their paths do, as the facing is turned over onto the piece
function AddFacingSeam(Pattern: TPattern; const Plan: TFacingPlan; var Made: TFacingMade): boolean;
var
  SideA, SideB: TSeamSide;
  Item: TRunEdge;
  Seam: TSeamObject;
begin
  SideA := nil;
  SideB := nil;
  for Item in Plan.Run do
  begin
    SetLength(SideA, Length(SideA) + 1);
    SideA[High(SideA)].PieceKey := Plan.Piece.Key;
    SideA[High(SideA)].EdgeKey := Item.EdgeKey;
    SetLength(SideB, Length(SideB) + 1);
    SideB[High(SideB)].PieceKey := Plan.FacingKey;
    SideB[High(SideB)].EdgeKey := FacingKeyFor(Plan, Item.EdgeKey);
  end;
  Seam := Pattern.AddSeam(FreeName(Pattern, FACING_SEAM_NAME), SideA, SideB);
  if not Assigned(Seam) then
    Exit(False);
  Seam.Reversed := True;
  Insert(Seam.Key, Made.SeamKeys, Length(Made.SeamKeys));
  Result := True;
end;

// The facing's entries for those of a seam's side that are a neighbouring
// part of a faced piece
function FacingSide(const Plans: TFacingPlans; const Side: TSeamSide; out Owner: integer): TSeamSide;
var
  Entry: TSeamEntry;
  Index: integer;
begin
  Result := nil;
  Owner := -1;
  for Entry in Side do
    for Index := 0 to High(Plans) do
      if (Entry.PieceKey = Plans[Index].Piece.Key) and ((Entry.EdgeKey = Plans[Index].BeforePart) or
        (Entry.EdgeKey = Plans[Index].AfterPart)) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)].PieceKey := Plans[Index].FacingKey;
        Result[High(Result)].EdgeKey := FacingKeyFor(Plans[Index], Entry.EdgeKey);
        Owner := Index;
      end;
end;

// Where the pieces are seamed along edges both facings now share part of,
// such as the shoulder, the facings are seamed there too
function JoinFacings(Pattern: TPattern; const Plans: TFacingPlans; var Made: TFacingMade): boolean;
var
  Index, OwnerA, OwnerB: integer;
  Seam, Join: TSeamObject;
  SideA, SideB: TSeamSide;
begin
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if not (Pattern.Objects[Index] is TSeamObject) or HasKey(Made.SeamKeys, Pattern.Objects[Index].Key) or
      HasKey(Made.JoinKeys, Pattern.Objects[Index].Key) then
      Continue;
    Seam := TSeamObject(Pattern.Objects[Index]);
    SideA := FacingSide(Plans, Seam.SideA, OwnerA);
    SideB := FacingSide(Plans, Seam.SideB, OwnerB);
    if (Length(SideA) = 0) or (Length(SideB) = 0) or (OwnerA = OwnerB) then
      Continue;
    Join := Pattern.AddSeam(FreeName(Pattern, FACING_SEAM_NAME), SideA, SideB);
    if not Assigned(Join) then
      Exit(False);
    Join.Reversed := Seam.Reversed;
    Insert(Join.Key, Made.JoinKeys, Length(Made.JoinKeys));
  end;
  Result := True;
end;

// The interfacing's material: the one named, or a new one by that name
function InterfacingMaterial(Pattern: TPattern; const AName: string; out Material: TPatternMaterial): boolean;
begin
  Material := Pattern.FindMaterialNamed(Trim(AName));
  if not Assigned(Material) then
    Material := Pattern.AddMaterial(Trim(AName));
  Result := Assigned(Material);
end;

// A neighbour's part in no piece becomes construction rather than an outline
// that does not print: a fold's, since the piece keeps its whole fold, and
// one a facing moved aside has a copy of
function KeepPartOutOfPrint(Pattern: TPattern; const PartKey: string): boolean;
begin
  Result := True;
  if Length(PiecesOn(Pattern, PartKey)) = 0 then
    Result := Pattern.SetEdgeRole(TEdgeObject(Pattern.FindNode(PartKey)), erConstruction);
end;

// On one piece: the facing and its interfacing, with the seam joining the
// facing to the piece and the piece's notches along it
function FaceOnePiece(Pattern: TPattern; const Spec: TFacingSpec; Material: TPatternMaterial; var Plan: TFacingPlan;
  var Made: TFacingMade): boolean;
var
  Facing, Interfacing: TPieceObject;
  InterfacingKey: string;
begin
  if not AddFacingInner(Pattern, Spec, Plan) then
    Exit(False);
  if Spec.Aside and not MoveFacingAside(Pattern, Plan) then
    Exit(False);
  Pattern.Evaluate;
  Facing := AddFacingPiece(Pattern, Plan, FACING_PREFIX, nil);
  if not Assigned(Facing) then
    Exit(False);
  Plan.FacingKey := Facing.Key;
  InterfacingKey := '';
  if Assigned(Material) then
  begin
    Interfacing := AddFacingPiece(Pattern, Plan, INTERFACING_PREFIX, Material);
    if not Assigned(Interfacing) then
      Exit(False);
    InterfacingKey := Interfacing.Key;
  end;
  Pattern.Evaluate;
  if not CopyFacingNotches(Pattern, Plan, Facing) or not AddFacingSeam(Pattern, Plan, Made) or not KeepPartOutOfPrint(Pattern, Plan.BeforeFar) or
    not KeepPartOutOfPrint(Pattern, Plan.AfterFar) or not KeepPartOutOfPrint(Pattern, Plan.BeforePart) or not KeepPartOutOfPrint(Pattern, Plan.AfterPart) then
    Exit(False);
  Insert(Plan.Piece.Key, Made.PieceKeys, Length(Made.PieceKeys));
  Insert(Facing.Key, Made.FacingKeys, Length(Made.FacingKeys));
  Insert(FacingKeyFor(Plan, Plan.InnerKey), Made.InnerKeys, Length(Made.InnerKeys));
  Insert(InterfacingKey, Made.InterfacingKeys, Length(Made.InterfacingKeys));
  Result := True;
end;

function InsertFacing(Pattern: TPattern; const Spec: TFacingSpec; out Made: TFacingMade): boolean;
var
  Plans: TFacingPlans;
  Material: TPatternMaterial;
  Width: double;
  Index: integer;
  Key: string;
  Piece: TDraftObject;
begin
  Made := Default(TFacingMade);
  if not FacingPlans(Pattern, Spec, Plans) or not AddFacingVariable(Pattern, Spec) then
    Exit(False);
  Pattern.Evaluate;
  if not Pattern.EvaluateText(Spec.Width, Width) then
    Exit(False);
  if Width * MILLIMETRES_PER_UNIT[Pattern.Units] <= DEFAULT_TOLERANCE then
    Exit(Pattern.Refuse(rsFeatureFacingNoWidth));
  Material := nil;
  if (Trim(Spec.Interfacing) <> '') and not InterfacingMaterial(Pattern, Spec.Interfacing, Material) then
    Exit(False);
  for Index := 0 to High(Plans) do
    if not FaceOnePiece(Pattern, Spec, Material, Plans[Index], Made) then
      Exit(False);
  if not JoinFacings(Pattern, Plans, Made) then
    Exit(False);
  Pattern.Evaluate;
  for Key in Concat(Made.PieceKeys, Made.FacingKeys) do
  begin
    Piece := TDraftObject(Pattern.FindNode(Key));
    if Piece.State <> esValid then
      Exit(Pattern.Refuse(Format(rsFeatureFacingPieceProblem, [Piece.DisplayName, Piece.Message])));
  end;
  Result := True;
end;

function DefaultButtons(Pattern: TPattern; const EdgeKey: string): TButtonsSpec;
begin
  Result := Default(TButtonsSpec);
  Result.EdgeKey := EdgeKey;
  Result.Size := '#' + BUTTON_SIZE_VARIABLE;
  Result.Thickness := '#' + BUTTON_THICKNESS_VARIABLE;
  Result.Count := '#' + BUTTON_COUNT_VARIABLE;
  Result.First := STARTING_LENGTHS[slButtonEnd, Pattern.Units];
  Result.Last := STARTING_LENGTHS[slButtonEnd, Pattern.Units];
end;

type
  // One side of the opening: its edge, its piece, and the ends its first and
  // last buttons are measured from
  TButtonSide = record
    Edge: TEdgeObject;
    Piece: TPieceObject;
    // The first button is measured from the edge's end, as the edge runs the
    // other way to the holes' edge
    FromEnd: boolean;
    TopKey, BottomKey: string;
  end;

// The variables the starting formulas name, when they are missing
function AddButtonVariables(Pattern: TPattern; const Spec: TButtonsSpec): boolean;
var
  Formulas: string;

  function Need(const AName, Formula, Description: string): boolean;
  begin
    Result := True;
    if (Pos(LowerCase('#' + AName), Formulas) > 0) and not Assigned(Pattern.FindVariable(AName)) then
      Result := Assigned(Pattern.AddVariable(AName, Formula, Description));
  end;

begin
  Formulas := LowerCase(string.Join(' ', [Spec.Size, Spec.Thickness, Spec.Count, Spec.First, Spec.Last, Spec.Extension]));
  Result := Need(BUTTON_SIZE_VARIABLE, STARTING_LENGTHS[slButtonSize, Pattern.Units], rsFeatureButtonSize) and
    Need(BUTTON_THICKNESS_VARIABLE, STARTING_LENGTHS[slButtonThickness, Pattern.Units], rsFeatureButtonThickness) and
    Need(BUTTON_COUNT_VARIABLE, STARTING_BUTTON_COUNT, rsFeatureButtonCount);
end;

// The edge and its one piece, checked before anything is added
function ButtonSide(Pattern: TPattern; const EdgeKey: string; out Side: TButtonSide): boolean;
var
  Node: TObject;
  Pieces: TPieceObjectArray;
begin
  Side := Default(TButtonSide);
  Node := Pattern.FindNode(EdgeKey);
  if not (Node is TEdgeObject) or TEdgeObject(Node).IsClosed then
    Exit(Pattern.Refuse(rsFeatureNoButtonEdge));
  Side.Edge := TEdgeObject(Node);
  Pieces := PiecesOn(Pattern, EdgeKey);
  if Length(Pieces) = 0 then
    Exit(Pattern.Refuse(Format(rsFeatureButtonsNotInPiece, [Side.Edge.DisplayName])));
  if Length(Pieces) > 1 then
    Exit(Pattern.Refuse(Format(rsFeatureButtonsPieces, [Side.Edge.DisplayName])));
  Side.Piece := Pieces[0];
  if Side.Piece.FoldEdgeKey = EdgeKey then
    Exit(Pattern.Refuse(Format(rsFeatureButtonsFold, [Side.Edge.DisplayName, Side.Piece.DisplayName])));
  if Side.Piece.State <> esValid then
    Exit(Pattern.Refuse(Format(rsFeatureFacingPieceProblem, [Side.Piece.DisplayName, Side.Piece.Message])));
  Result := True;
end;

// The count, at least 1, and room for it between the first and last buttons
function CheckButtonRoom(Pattern: TPattern; const Spec: TButtonsSpec; const Side: TButtonSide): boolean;
var
  Count, First, Last, Scale: double;
begin
  Scale := MILLIMETRES_PER_UNIT[Pattern.Units];
  if not Pattern.EvaluateText(Spec.Count, Count) or not Pattern.EvaluateText(Spec.First, First) or not Pattern.EvaluateText(Spec.Last, Last) then
    Exit(False);
  if Round(Count) < 1 then
    Exit(Pattern.Refuse(rsFeatureButtonsNoCount));
  if (First < 0) or (Last < 0) or ((First + Last) * Scale >= Side.Edge.Length - DEFAULT_TOLERANCE) then
    Exit(Pattern.Refuse(Format(rsFeatureButtonsNoRoom, [LengthWithUnit(First * Scale, Pattern.Units),
      LengthWithUnit(Last * Scale, Pattern.Units), Side.Edge.DisplayName, LengthWithUnit(Side.Edge.Length, Pattern.Units)])));
  Result := True;
end;

// The first and last buttons' points along the side's edge
function AddButtonEnds(Pattern: TPattern; const Spec: TButtonsSpec; var Side: TButtonSide): boolean;
var
  Top, Bottom: TDraftObject;
begin
  Top := Pattern.AddAlongEdgePoint(FreeName(Pattern, BUTTON_TOP_NAME), Side.Edge.Key, Side.FromEnd, amLength, Spec.First);
  Bottom := Pattern.AddAlongEdgePoint(FreeName(Pattern, BUTTON_BOTTOM_NAME), Side.Edge.Key, not Side.FromEnd, amLength, Spec.Last);
  if not Assigned(Top) or not Assigned(Bottom) then
    Exit(False);
  Side.TopKey := Top.Key;
  Side.BottomKey := Bottom.Key;
  Result := True;
end;

// The edge of the buttons' piece runs the same way as the holes' edge, or the
// other way, as on a mirrored copy
function RunsBackwards(Holes, Buttons: TEdgeObject): boolean;
var
  Start, Along: TVec2;
begin
  Start := Holes.PointAtLength(0);
  Along := Holes.PointAtLength(Holes.Length) - Start;
  Result := Dot(Buttons.PointAtLength(0) - Start, Along) > Dot(Buttons.PointAtLength(Buttons.Length) - Start, Along);
end;

// The extension: the edge offset outwards at the width, with lines out to it
// at its ends, in its place in the piece's path; the edge stays as a
// placement line, the centre front the buttons are on
function AddExtension(Pattern: TPattern; const Spec: TButtonsSpec; const Side: TButtonSide; var Made: TButtonsMade): boolean;
var
  Run: TRunEdgeArray;
  Outside: TOffsetSide;
  Offset: TOffsetEdge;
  OutStart, OutEnd: TDraftObject;
  Into, OutOf: TLineObject;
  StartKey, EndKey: string;
  Path: TPiecePath;
  Index: integer;
begin
  if not Pattern.PieceRun(Side.Piece, [Side.Edge.Key], False, Run, Outside) then
    Exit(False);
  Offset := Pattern.AddOffsetRun(Run, Spec.Extension, Outside, erOutline);
  if not Assigned(Offset) then
    Exit(False);
  OutStart := Pattern.AddAlongEdgePoint('', Offset.Key, False, amLength, '0');
  OutEnd := Pattern.AddAlongEdgePoint('', Offset.Key, True, amLength, '0');
  if not Assigned(OutStart) or not Assigned(OutEnd) then
    Exit(False);
  // Where the path reaches the edge and leaves it
  StartKey := Side.Edge.StartKey;
  EndKey := Side.Edge.EndKey;
  if Run[0].Reversed then
  begin
    StartKey := Side.Edge.EndKey;
    EndKey := Side.Edge.StartKey;
  end;
  Into := Pattern.AddLine(StartKey, OutStart.Key, erOutline);
  OutOf := Pattern.AddLine(OutEnd.Key, EndKey, erOutline);
  if not Assigned(Into) or not Assigned(OutOf) then
    Exit(False);
  Path := nil;
  AddPathEntry(Path, Into.Key, False);
  AddPathEntry(Path, Offset.Key, False);
  AddPathEntry(Path, OutOf.Key, False);
  if not Pattern.ReplaceInPath(Side.Piece, Side.Edge.Key, Path, False) or not Pattern.SetEdgeRole(Side.Edge, erPlacement) then
    Exit(False);
  for Index := 0 to High(Path) do
    Insert(Path[Index].EdgeKey, Made.ExtensionKeys, Length(Made.ExtensionKeys));
  Result := True;
end;

// A buttonhole's angle: along the opening for a vertical hole, else square to
// it into the piece
function ButtonholeAngle(Pattern: TPattern; const Spec: TButtonsSpec; const Side: TButtonSide): string;
var
  Top, Bottom: TPointObject;
  Along: double;
  Inward: boolean;
begin
  Top := TPointObject(Pattern.FindNode(Side.TopKey));
  Bottom := TPointObject(Pattern.FindNode(Side.BottomKey));
  Result := Format('atan2(%0:s.y - %1:s.y, %1:s.x - %0:s.x)', [Top.DisplayName, Bottom.DisplayName]);
  Along := AngleBetween(Top.Position, Bottom.Position);
  Inward := PointInPolygon(PolarPoint(Top.Position, PROBE_DISTANCE, Along + RIGHT_ANGLE), Side.Piece.Outline);
  if Spec.Direction = bdVertical then
    Exit;
  if Inward then
    Result := Format('%s + %d', [Result, RIGHT_ANGLE])
  else
    Result := Format('%s - %d', [Result, RIGHT_ANGLE]);
end;

// The buttonholes: a repeat between the holes' ends, each a slot the button's
// size and thickness long, a horizontal one starting just past the centre
// front and running into the piece
function AddButtonholes(Pattern: TPattern; const Spec: TButtonsSpec; const Side: TButtonSide; const Angle: string;
  var Made: TButtonsMade): boolean;
var
  Holes: TRepeatObject;
  Length, Offset: string;
begin
  Holes := Pattern.AddRepeatBetween(FreeName(Pattern, BUTTONHOLE_NAME), Side.TopKey, Side.BottomKey, Spec.Count, True);
  if not Assigned(Holes) then
    Exit(False);
  Made.HolesKey := Holes.Key;
  Length := Format('%s + %s', [Term(Spec.Size), Term(Spec.Thickness)]);
  Offset := '0';
  if Spec.Direction = bdHorizontal then
    Offset := Format('(%s) / 2 - %s', [Length, STARTING_LENGTHS[slButtonholeBack, Pattern.Units]]);
  Result := Pattern.SetMarker(Holes.Key, pmButtonhole, Length) and Pattern.SetFormula(Holes, MARKER_ANGLE_FIELD, Angle) and
    Pattern.SetFormula(Holes, MARKER_OFFSET_FIELD, Offset);
end;

function AddButtonMarkers(Pattern: TPattern; const Spec: TButtonsSpec; const Side: TButtonSide; var Made: TButtonsMade): boolean;
var
  Buttons: TRepeatObject;
begin
  Buttons := Pattern.AddRepeatBetween(FreeName(Pattern, BUTTON_NAME), Side.TopKey, Side.BottomKey, Spec.Count, True);
  if not Assigned(Buttons) then
    Exit(False);
  Made.ButtonsKey := Buttons.Key;
  Result := Pattern.SetMarker(Buttons.Key, pmButton, Spec.Size);
end;

// Markings join every piece they lie in; on separate pieces that overlap,
// the holes are taken off the buttons' piece and the buttons off the holes'
function KeepMarkingOn(Pattern: TPattern; const Key: string; Piece: TPieceObject): boolean;
var
  Other: TPieceObject;
begin
  for Other in Pattern.PiecesWithMarking(Key) do
    if (Other <> Piece) and not Pattern.RemoveMarking(Other, Other.PointMarkingOf(Key)) then
      Exit(False);
  Result := True;
end;

function InsertButtons(Pattern: TPattern; const Spec: TButtonsSpec; out Made: TButtonsMade): boolean;
var
  Holes, Buttons: TButtonSide;
  Separate: boolean;
  Angle: string;
  Extension, Size: double;
  Key: string;
  Keys: TStringArray;
  Node: TDraftObject;
begin
  Made := Default(TButtonsMade);
  if not ButtonSide(Pattern, Spec.EdgeKey, Holes) then
    Exit(False);
  Separate := (Spec.ButtonsEdgeKey <> '') and (Spec.ButtonsEdgeKey <> Spec.EdgeKey);
  Buttons := Holes;
  if Separate then
  begin
    if not ButtonSide(Pattern, Spec.ButtonsEdgeKey, Buttons) then
      Exit(False);
    if Buttons.Piece = Holes.Piece then
      Exit(Pattern.Refuse(Format(rsFeatureButtonsSamePiece, [Holes.Piece.DisplayName])));
    Buttons.FromEnd := RunsBackwards(Holes.Edge, Buttons.Edge);
  end;
  if not AddButtonVariables(Pattern, Spec) then
    Exit(False);
  Pattern.Evaluate;
  if not CheckButtonRoom(Pattern, Spec, Holes) or (Separate and not CheckButtonRoom(Pattern, Spec, Buttons)) then
    Exit(False);
  if not AddButtonEnds(Pattern, Spec, Holes) or (Separate and not AddButtonEnds(Pattern, Spec, Buttons)) then
    Exit(False);
  if not Separate then
    Buttons := Holes;
  Pattern.Evaluate;
  // Which way is into the piece is found before an extension widens it
  Angle := ButtonholeAngle(Pattern, Spec, Holes);
  if Trim(Spec.Extension) <> '' then
  begin
    if not AddExtension(Pattern, Spec, Holes, Made) or (Separate and not AddExtension(Pattern, Spec, Buttons, Made)) then
      Exit(False);
    if Pattern.EvaluateText(Spec.Extension, Extension) and Pattern.EvaluateText(Spec.Size, Size) and (Extension < Size / 2) then
      Insert(Format(rsFeatureButtonsNarrow, [LengthWithUnit(Extension * MILLIMETRES_PER_UNIT[Pattern.Units], Pattern.Units)]),
        Made.Problems, Length(Made.Problems));
  end;
  if not AddButtonholes(Pattern, Spec, Holes, Angle, Made) or not AddButtonMarkers(Pattern, Spec, Buttons, Made) then
    Exit(False);
  Pattern.Evaluate;
  if Separate and (not KeepMarkingOn(Pattern, Made.HolesKey, Holes.Piece) or not KeepMarkingOn(Pattern, Made.ButtonsKey, Buttons.Piece)) then
    Exit(False);
  Pattern.Evaluate;
  Made.TopKey := Holes.TopKey;
  Made.BottomKey := Holes.BottomKey;
  Made.ButtonTopKey := Buttons.TopKey;
  Made.ButtonBottomKey := Buttons.BottomKey;
  Made.HolesPieceKey := Holes.Piece.Key;
  Made.ButtonsPieceKey := Buttons.Piece.Key;
  Keys := nil;
  Insert(Made.HolesKey, Keys, 0);
  Insert(Made.ButtonsKey, Keys, 1);
  Insert(Holes.Piece.Key, Keys, 2);
  Insert(Buttons.Piece.Key, Keys, 3);
  for Key in Keys do
  begin
    Node := TDraftObject(Pattern.FindNode(Key));
    if Node.State <> esValid then
      Exit(Pattern.Refuse(Format(rsFeatureFacingPieceProblem, [Node.DisplayName, Node.Message])));
  end;
  Result := True;
end;

initialization
  FormatNumbers := DefaultFormatSettings;
  FormatNumbers.DecimalSeparator := '.';
end.
