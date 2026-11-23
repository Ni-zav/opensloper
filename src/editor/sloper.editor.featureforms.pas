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

// What the Features tab shows for each sewing detail it applies (a zip, a
// dart, a hem, a facing or buttons) as a form of fields, worked out from the
// canvas's selection and the values typed or chosen so far, and the Apply
// that adds the detail's objects as one undo step (Sloper.Core.Features).
// The desktop panel builds its controls for the same fields; the web editor
// gets them as data (editor_features) and draws them. Values are text: a
// choice's index, '1' or '0' for a box, else what is typed.
unit Sloper.Editor.FeatureForms;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Pattern, Sloper.Core.Features, Sloper.Document.PatternDocument;

type
  TFeatureKind = (fkZip, fkDart, fkHem, fkFacing, fkButtons);

  // A field typed in, a choice, a box to tick (its caption beside it), or a
  // choice that may also be typed, as a material's name
  TFeatureFieldKind = (ffkText, ffkChoice, ffkCheck, ffkCombo);

  TFeatureField = record
    // One of the FEATURE_FIELD_ names; a feature's fields are always the same, in the same order
    Id: string;
    Kind: TFeatureFieldKind;
    // Above the field, or beside a box; '' for a field that follows the box it belongs to
    Caption: string;
    Text: string;
    Choices: TStringArray;
    // False when it does not apply now, as the stitching of an invisible zip
    Enabled: boolean;
  end;
  TFeatureFieldArray = array of TFeatureField;

  TFeatureForm = record
    // What it goes along, or what to select first
    Header: string;
    // What Apply adds
    Note: string;
    CanApply: boolean;
    Fields: TFeatureFieldArray;
  end;

  TFeatureValue = record
    Id, Text: string;
  end;
  TFeatureValues = array of TFeatureValue;

  // What the canvas's selection gives the features: the one edge and the one
  // point selected, when nothing else is, and every edge, when only edges are
  TFeatureSelection = record
    EdgeKey, PointKey: string;
    EdgeKeys: TStringArray;
  end;

const
  FEATURE_NAMES: array[TFeatureKind] of string = ('zip', 'dart', 'hem', 'facing', 'buttons');
  FEATURE_FIELD_STYLE = 'style';
  FEATURE_FIELD_LENGTH = 'length';
  FEATURE_FIELD_FROM = 'from';
  FEATURE_FIELD_ALLOWANCE = 'allowance';
  FEATURE_FIELD_STITCH = 'stitch';
  FEATURE_FIELD_SHIELD = 'shield';
  FEATURE_FIELD_POSITION = 'position';
  FEATURE_FIELD_WIDTH = 'width';
  FEATURE_FIELD_DEPTH = 'depth';
  FEATURE_FIELD_HOLE = 'hole';
  FEATURE_FIELD_FOLD = 'fold';
  FEATURE_FIELD_TURN_UNDER = 'turnUnder';
  FEATURE_FIELD_NOTCHES = 'notches';
  FEATURE_FIELD_PLACE = 'place';
  FEATURE_FIELD_INTERFACING = 'interfacing';
  FEATURE_FIELD_MATERIAL = 'material';
  FEATURE_FIELD_SIZE = 'size';
  FEATURE_FIELD_THICKNESS = 'thickness';
  FEATURE_FIELD_COUNT = 'count';
  FEATURE_FIELD_FIRST = 'first';
  FEATURE_FIELD_LAST = 'last';
  FEATURE_FIELD_DIRECTION = 'direction';
  FEATURE_FIELD_EXTENSION = 'extension';
  FEATURE_FIELD_EXTENSION_WIDTH = 'extensionWidth';
  FEATURE_CHECKED = '1';
  FEATURE_UNCHECKED = '0';

function FeatureCaption(Kind: TFeatureKind): string;
// False for a name that is no feature
function FeatureKindOf(const AName: string; out Kind: TFeatureKind): boolean;
function FeatureSelectionOf(Pattern: TPattern; const Keys: array of string): TFeatureSelection;
// The value of a field, or Default when it has none
function FeatureValue(const Values: TFeatureValues; const Id: string; const Default: string = ''): string;
procedure SetFeatureValue(var Values: TFeatureValues; const Id, Text: string);
// The fields' starting values for the pattern's unit, keeping the style
// chosen in Values, if any
function FeatureStartingValues(Pattern: TPattern; Kind: TFeatureKind; const Values: TFeatureValues): TFeatureValues;
// The values after the field Id changed from Previous: another style starts
// again at its own widths, and a hem's topstitching follows its depth until
// it is typed in itself
function FeatureValueChanged(Pattern: TPattern; Kind: TFeatureKind; const Values: TFeatureValues;
  const Id, Previous: string): TFeatureValues;
function FeatureForm(Pattern: TPattern; Kind: TFeatureKind; const Selection: TFeatureSelection;
  const Values: TFeatureValues): TFeatureForm;
// Adds the feature as one undo step; Message says what was added, or why
// nothing was
function ApplyFeature(Document: TPatternDocument; Kind: TFeatureKind; const Selection: TFeatureSelection;
  const Values: TFeatureValues; out Message: string): boolean;

resourcestring
  rsFeaturesStyle = 'Style';
  rsFeaturesCentred = 'Centred, topstitched either side';
  rsFeaturesInvisible = 'Invisible, nothing showing';
  rsFeaturesLapped = 'Lapped, one side over the zip';
  rsFeaturesFlyFront = 'Fly front, with a fly shield';
  rsFeaturesExtension = 'Fly extension past the seam (%s)';
  rsFeaturesLap = 'Lap stitching from the seam (%s)';
  rsFeaturesFly = 'Fly stitching from the seam (%s)';
  rsFeaturesShield = 'Fly shield width (%s)';
  rsFeaturesZipShield = '%s, with a fly shield beside the pattern';
  rsFeaturesLength = 'Length (%s)';
  rsFeaturesFrom = 'Starts from';
  rsFeaturesFromPoint = 'The %s end';
  rsFeaturesAllowance = 'Allowance along the zip (%s)';
  rsFeaturesStitch = 'Topstitching from the seam (%s)';
  rsFeaturesAlong = 'Along %s';
  rsFeaturesChooseEdge = 'Select an edge of a piece on the canvas.';
  rsFeaturesZipNote = 'Apply splits the edge where the zip stops, gives the opening its allowance, notches the stop, ' +
    'adds the style''s topstitching and, for a fly front, a fly shield piece. They are ordinary objects, to change as you ' +
    'like; one Undo takes them all off.';
  rsFeaturesUndoZip = 'Insert Zip';
  rsFeaturesZipDone = 'Zip added along %s';
  rsFeaturesZipOtherSide = '%s; its seam joins another edge, which needs a zip too';
  rsFeaturesDartIn = 'In %s';
  rsFeaturesDartChoose = 'Select an edge of a piece on the canvas, and a point for the dart to run to if you like.';
  rsFeaturesDartPosition = 'Middle from the end below (%s), blank for halfway';
  rsFeaturesDartWidth = 'Width at the edge (%s)';
  rsFeaturesDartDepth = 'Depth into the piece (%s)';
  rsFeaturesDartToPoint = 'Runs to %s, the point selected';
  rsFeaturesDartHole = 'Hole back from the point (%s), blank for none';
  rsFeaturesDartFold = 'Pressed towards';
  rsFeaturesDartNote = 'Apply adds the dart''s middle, legs and point, takes the edge between the legs out of the ' +
    'outline, closes the dart with a seam, notches the legs, marks a hole near the point and the centre line as a fold, ' +
    'and shapes the seam allowance across the dart as it lies pressed. They are ordinary objects, to change as you like; ' +
    'one Undo takes them all off.';
  rsFeaturesUndoDart = 'Insert Dart';
  rsFeaturesDartDone = 'Dart added in %s';
  rsFeaturesHemChoose = 'Select the edges to hem on the canvas: one or more on each piece, running end to end.';
  rsFeaturesHemSingle = 'Single, turned once';
  rsFeaturesHemDouble = 'Double, turned twice';
  rsFeaturesHemNarrow = 'Narrow, a small double hem';
  rsFeaturesHemBlind = 'Blind, no topstitching';
  rsFeaturesHemDepth = 'Depth, turned up (%s)';
  rsFeaturesHemTurnUnder = 'Turned under besides (%s)';
  rsFeaturesHemStitch = 'Topstitching from the fold (%s)';
  rsFeaturesHemNotches = 'Notch where it turns up';
  rsFeaturesHemNote = 'Apply gives the edges the hem''s allowance, shapes its ends to lie along the edges beside it ' +
    'when turned up, adds the topstitching and notches the edges beside it. They are ordinary objects, to change as you ' +
    'like; one Undo takes them all off.';
  rsFeaturesUndoHem = 'Insert Hem';
  rsFeaturesHemDone = 'Hem added along %s';
  rsFeaturesHemProblem = '%s; %s';
  rsFeaturesFacingChoose = 'Select the edges to face on the canvas, such as a neckline: one or more on each piece, ' +
    'running end to end.';
  rsFeaturesFacingWidth = 'Width (%s)';
  rsFeaturesFacingPlace = 'Placement';
  rsFeaturesFacingInPlace = 'In place, over the piece';
  rsFeaturesFacingAside = 'Moved aside, beside the piece';
  rsFeaturesFacingInterfacing = 'Interfacing, cut from';
  rsFeaturesFacingMaterial = 'Interfacing';
  rsFeaturesFacingNote = 'Apply adds the facing''s inner edge, splits the edges either side where it meets them, and ' +
    'adds the facing piece, cut as the piece is, seamed to it and to the facing beside it, with an interfacing if you ' +
    'like. They are ordinary objects, to change as you like; one Undo takes them all off.';
  rsFeaturesUndoFacing = 'Insert Facing';
  rsFeaturesFacingDone = 'Facing added along %s';
  rsFeaturesButtonsChoose = 'Select the opening''s edge on the canvas, such as a centre front, and the other front''s ' +
    'edge too if the fronts are separate pieces.';
  rsFeaturesButtonsHoles = 'Buttonholes along %s';
  rsFeaturesButtonsBoth = 'Buttonholes along %s, buttons along %s';
  rsFeaturesButtonSize = 'Button size (%s)';
  rsFeaturesButtonThickness = 'Button thickness (%s)';
  rsFeaturesButtonCount = 'How many';
  rsFeaturesButtonFirst = 'First from the %s end (%s)';
  rsFeaturesButtonLast = 'Last from the %s end (%s)';
  rsFeaturesButtonStart = 'start';
  rsFeaturesButtonEnd = 'end';
  rsFeaturesButtonDirection = 'Buttonholes';
  rsFeaturesButtonHorizontal = 'Horizontal, square to the edge';
  rsFeaturesButtonVertical = 'Vertical, along the edge';
  rsFeaturesButtonExtension = 'Add an extension this wide';
  rsFeaturesButtonsNote = 'Apply adds the first and last buttons'' points, a repeat of buttonholes and one of buttons ' +
    'between them, and an extension past the edge if you like, the edge staying as a placement line. They are ordinary ' +
    'objects: change #button_count and the buttons follow. One Undo takes them all off.';
  rsFeaturesUndoButtons = 'Insert Buttons';
  rsFeaturesButtonsDone = 'Buttons added along %s';
  rsFeaturesBusy = 'Finish the change under way first';

implementation

uses
  Math, Sloper.Core.Draft, Sloper.Core.Units;

function FeatureCaption(Kind: TFeatureKind): string;
begin
  case Kind of
    fkZip: Result := rsFeatureZip;
    fkDart: Result := rsFeatureDart;
    fkHem: Result := rsFeatureHem;
    fkFacing: Result := rsFeatureFacing;
    else
      Result := rsFeatureButtons;
  end;
end;

function FeatureKindOf(const AName: string; out Kind: TFeatureKind): boolean;
begin
  for Kind in TFeatureKind do
    if FEATURE_NAMES[Kind] = AName then
      Exit(True);
  Kind := fkZip;
  Result := False;
end;

function FeatureSelectionOf(Pattern: TPattern; const Keys: array of string): TFeatureSelection;
var
  Key: string;
  Node: TObject;
  Edges, Points: integer;
begin
  Result := Default(TFeatureSelection);
  Edges := 0;
  Points := 0;
  for Key in Keys do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TEdgeObject then
    begin
      Result.EdgeKey := Key;
      Insert(Key, Result.EdgeKeys, Length(Result.EdgeKeys));
      Inc(Edges);
    end
    else if Node is TPointObject then
    begin
      Result.PointKey := Key;
      Inc(Points);
    end;
  end;
  if Edges <> Length(Keys) then
    Result.EdgeKeys := nil;
  // One of each at most, and nothing else
  if (Edges <> 1) or (Points > 1) or (Edges + Points <> Length(Keys)) then
  begin
    Result.EdgeKey := '';
    Result.PointKey := '';
  end;
end;

function FeatureValue(const Values: TFeatureValues; const Id: string; const Default: string): string;
var
  Value: TFeatureValue;
begin
  for Value in Values do
    if Value.Id = Id then
      Exit(Value.Text);
  Result := Default;
end;

procedure SetFeatureValue(var Values: TFeatureValues; const Id, Text: string);
var
  Index: integer;
begin
  for Index := 0 to High(Values) do
    if Values[Index].Id = Id then
    begin
      Values[Index].Text := Text;
      Exit;
    end;
  SetLength(Values, Length(Values) + 1);
  Values[High(Values)].Id := Id;
  Values[High(Values)].Text := Text;
end;

function ChoiceOf(const Values: TFeatureValues; const Id: string): integer;
begin
  Result := Max(StrToIntDef(FeatureValue(Values, Id, '0'), 0), 0);
end;

function Checked(const Values: TFeatureValues; const Id: string): boolean;
begin
  Result := FeatureValue(Values, Id) = FEATURE_CHECKED;
end;

function ZipStyleOf(const Values: TFeatureValues): TZipStyle;
begin
  Result := TZipStyle(Min(ChoiceOf(Values, FEATURE_FIELD_STYLE), Ord(High(TZipStyle))));
end;

function HemStyleOf(const Values: TFeatureValues): THemStyle;
begin
  Result := THemStyle(Min(ChoiceOf(Values, FEATURE_FIELD_STYLE), Ord(High(THemStyle))));
end;

function FeatureStartingValues(Pattern: TPattern; Kind: TFeatureKind; const Values: TFeatureValues): TFeatureValues;
var
  Zip: TZipSpec;
  Dart: TDartSpec;
  Hem: THemSpec;
  Buttons: TButtonsSpec;
begin
  Result := nil;
  case Kind of
    fkZip:
    begin
      Zip := DefaultZip(Pattern, '', ZipStyleOf(Values));
      SetFeatureValue(Result, FEATURE_FIELD_STYLE, IntToStr(Ord(Zip.Style)));
      SetFeatureValue(Result, FEATURE_FIELD_LENGTH, Zip.Length);
      SetFeatureValue(Result, FEATURE_FIELD_FROM, FeatureValue(Values, FEATURE_FIELD_FROM, '0'));
      SetFeatureValue(Result, FEATURE_FIELD_ALLOWANCE, Zip.Allowance);
      SetFeatureValue(Result, FEATURE_FIELD_STITCH, Zip.StitchDistance);
      SetFeatureValue(Result, FEATURE_FIELD_SHIELD, Zip.ShieldWidth);
    end;
    fkDart:
    begin
      Dart := DefaultDart(Pattern, '');
      SetFeatureValue(Result, FEATURE_FIELD_POSITION, Dart.Position);
      SetFeatureValue(Result, FEATURE_FIELD_FROM, '0');
      SetFeatureValue(Result, FEATURE_FIELD_WIDTH, Dart.Width);
      SetFeatureValue(Result, FEATURE_FIELD_DEPTH, Dart.Depth);
      SetFeatureValue(Result, FEATURE_FIELD_HOLE, Dart.HoleInset);
      SetFeatureValue(Result, FEATURE_FIELD_FOLD, '0');
    end;
    fkHem:
    begin
      Hem := DefaultHem(Pattern, [], HemStyleOf(Values));
      SetFeatureValue(Result, FEATURE_FIELD_STYLE, IntToStr(Ord(Hem.Style)));
      SetFeatureValue(Result, FEATURE_FIELD_DEPTH, Hem.Depth);
      SetFeatureValue(Result, FEATURE_FIELD_TURN_UNDER, Hem.TurnUnder);
      SetFeatureValue(Result, FEATURE_FIELD_STITCH, Hem.StitchDistance);
      SetFeatureValue(Result, FEATURE_FIELD_NOTCHES, FeatureValue(Values, FEATURE_FIELD_NOTCHES, FEATURE_CHECKED));
    end;
    fkFacing:
    begin
      SetFeatureValue(Result, FEATURE_FIELD_WIDTH, DefaultFacing(Pattern, []).Width);
      SetFeatureValue(Result, FEATURE_FIELD_PLACE, '0');
      SetFeatureValue(Result, FEATURE_FIELD_INTERFACING, FEATURE_UNCHECKED);
      SetFeatureValue(Result, FEATURE_FIELD_MATERIAL, rsFeaturesFacingMaterial);
    end;
    fkButtons:
    begin
      Buttons := DefaultButtons(Pattern, '');
      SetFeatureValue(Result, FEATURE_FIELD_SIZE, Buttons.Size);
      SetFeatureValue(Result, FEATURE_FIELD_THICKNESS, Buttons.Thickness);
      SetFeatureValue(Result, FEATURE_FIELD_COUNT, Buttons.Count);
      SetFeatureValue(Result, FEATURE_FIELD_FIRST, Buttons.First);
      SetFeatureValue(Result, FEATURE_FIELD_LAST, Buttons.Last);
      SetFeatureValue(Result, FEATURE_FIELD_DIRECTION, IntToStr(Ord(bdHorizontal)));
      SetFeatureValue(Result, FEATURE_FIELD_EXTENSION, FEATURE_UNCHECKED);
      SetFeatureValue(Result, FEATURE_FIELD_EXTENSION_WIDTH, Buttons.Size);
    end;
  end;
end;

function FeatureValueChanged(Pattern: TPattern; Kind: TFeatureKind; const Values: TFeatureValues;
  const Id, Previous: string): TFeatureValues;
var
  Starting: TFeatureValues;
  Field: string;
begin
  Result := Copy(Values);
  if (Kind in [fkZip, fkHem]) and (Id = FEATURE_FIELD_STYLE) then
  begin
    // A style starts with its own widths: a fly is wider than a lap, a narrow hem much smaller
    Starting := FeatureStartingValues(Pattern, Kind, Values);
    for Field in [FEATURE_FIELD_LENGTH, FEATURE_FIELD_ALLOWANCE, FEATURE_FIELD_STITCH, FEATURE_FIELD_SHIELD,
        FEATURE_FIELD_DEPTH, FEATURE_FIELD_TURN_UNDER] do
      if FeatureValue(Starting, Field, #0) <> #0 then
        SetFeatureValue(Result, Field, FeatureValue(Starting, Field));
  end
  else if (Kind = fkHem) and (Id = FEATURE_FIELD_DEPTH) and
    (Trim(FeatureValue(Values, FEATURE_FIELD_STITCH)) = HemStitchDistance(Pattern, Trim(Previous))) then
    SetFeatureValue(Result, FEATURE_FIELD_STITCH, HemStitchDistance(Pattern,
      Trim(FeatureValue(Values, FEATURE_FIELD_DEPTH))));
end;

function NameOf(Pattern: TPattern; const Key: string): string;
var
  Node: TObject;
begin
  Node := Pattern.FindNode(Key);
  if Node is TDraftObject then
    Result := TDraftObject(Node).DisplayName
  else
    Result := Key;
end;

// The selected edges' names, in the order selected
function EdgeNames(Pattern: TPattern; const Keys: array of string): string;
var
  Key: string;
begin
  Result := '';
  for Key in Keys do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + NameOf(Pattern, Key);
  end;
end;

// The one edge selected, when it has two ends
function OpenEdge(Pattern: TPattern; const Selection: TFeatureSelection): TEdgeObject;
var
  Node: TObject;
begin
  Result := nil;
  Node := Pattern.FindNode(Selection.EdgeKey);
  if (Node is TEdgeObject) and not TEdgeObject(Node).IsClosed then
    Result := TEdgeObject(Node);
end;

// The edge's two ends as choices, none without one
function EndChoices(Pattern: TPattern; Edge: TEdgeObject): TStringArray;
begin
  Result := nil;
  if Assigned(Edge) then
    Result := [Format(rsFeaturesFromPoint, [NameOf(Pattern, Edge.StartKey)]),
      Format(rsFeaturesFromPoint, [NameOf(Pattern, Edge.EndKey)])];
end;

procedure AddField(var Form: TFeatureForm; const Values: TFeatureValues; const Id, Caption: string;
  Kind: TFeatureFieldKind = ffkText; const Choices: TStringArray = nil; Enabled: boolean = True);
var
  Field: TFeatureField;
begin
  Field := Default(TFeatureField);
  Field.Id := Id;
  Field.Kind := Kind;
  Field.Caption := Caption;
  Field.Text := FeatureValue(Values, Id);
  Field.Choices := Choices;
  Field.Enabled := Enabled;
  Insert(Field, Form.Fields, Length(Form.Fields));
end;

function ZipForm(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  const UnitText: string): TFeatureForm;
var
  Edge: TEdgeObject;
  Style: TZipStyle;
  Allowance, Stitch: string;
begin
  Result := Default(TFeatureForm);
  Edge := OpenEdge(Pattern, Selection);
  Style := ZipStyleOf(Values);
  Result.CanApply := Assigned(Edge) and (Selection.PointKey = '');
  if Result.CanApply then
    Result.Header := Format(rsFeaturesAlong, [Edge.DisplayName])
  else
    Result.Header := rsFeaturesChooseEdge;
  Result.Note := rsFeaturesZipNote;
  if Style = zsFlyFront then
    Allowance := rsFeaturesExtension
  else
    Allowance := rsFeaturesAllowance;
  case Style of
    zsLapped: Stitch := rsFeaturesLap;
    zsFlyFront: Stitch := rsFeaturesFly;
    else
      Stitch := rsFeaturesStitch;
  end;
  AddField(Result, Values, FEATURE_FIELD_STYLE, rsFeaturesStyle, ffkChoice, [rsFeaturesCentred, rsFeaturesInvisible,
    rsFeaturesLapped, rsFeaturesFlyFront]);
  AddField(Result, Values, FEATURE_FIELD_LENGTH, Format(rsFeaturesLength, [UnitText]));
  if Result.CanApply then
    AddField(Result, Values, FEATURE_FIELD_FROM, rsFeaturesFrom, ffkChoice, EndChoices(Pattern, Edge))
  else
    AddField(Result, Values, FEATURE_FIELD_FROM, rsFeaturesFrom, ffkChoice, nil, False);
  AddField(Result, Values, FEATURE_FIELD_ALLOWANCE, Format(Allowance, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_STITCH, Format(Stitch, [UnitText]), ffkText, nil, Style <> zsInvisible);
  AddField(Result, Values, FEATURE_FIELD_SHIELD, Format(rsFeaturesShield, [UnitText]), ffkText, nil, Style = zsFlyFront);
end;

function DartForm(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  const UnitText: string): TFeatureForm;
var
  Edge: TEdgeObject;
  Depth: string;
begin
  Result := Default(TFeatureForm);
  Edge := OpenEdge(Pattern, Selection);
  Result.CanApply := Assigned(Edge);
  if Result.CanApply then
    Result.Header := Format(rsFeaturesDartIn, [Edge.DisplayName])
  else
    Result.Header := rsFeaturesDartChoose;
  Result.Note := rsFeaturesDartNote;
  if Selection.PointKey = '' then
    Depth := Format(rsFeaturesDartDepth, [UnitText])
  else
    Depth := Format(rsFeaturesDartToPoint, [NameOf(Pattern, Selection.PointKey)]);
  AddField(Result, Values, FEATURE_FIELD_POSITION, Format(rsFeaturesDartPosition, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_FROM, rsFeaturesFrom, ffkChoice, EndChoices(Pattern, Edge), Result.CanApply);
  AddField(Result, Values, FEATURE_FIELD_WIDTH, Format(rsFeaturesDartWidth, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_DEPTH, Depth, ffkText, nil, Selection.PointKey = '');
  AddField(Result, Values, FEATURE_FIELD_HOLE, Format(rsFeaturesDartHole, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_FOLD, rsFeaturesDartFold, ffkChoice, EndChoices(Pattern, Edge), Result.CanApply);
end;

function HemForm(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  const UnitText: string): TFeatureForm;
var
  Style: THemStyle;
begin
  Result := Default(TFeatureForm);
  Style := HemStyleOf(Values);
  Result.CanApply := Length(Selection.EdgeKeys) > 0;
  if Result.CanApply then
    Result.Header := Format(rsFeaturesAlong, [EdgeNames(Pattern, Selection.EdgeKeys)])
  else
    Result.Header := rsFeaturesHemChoose;
  Result.Note := rsFeaturesHemNote;
  AddField(Result, Values, FEATURE_FIELD_STYLE, rsFeaturesStyle, ffkChoice, [rsFeaturesHemSingle, rsFeaturesHemDouble,
    rsFeaturesHemNarrow, rsFeaturesHemBlind]);
  AddField(Result, Values, FEATURE_FIELD_DEPTH, Format(rsFeaturesHemDepth, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_TURN_UNDER, Format(rsFeaturesHemTurnUnder, [UnitText]), ffkText, nil,
    Style in [hsDouble, hsNarrow]);
  AddField(Result, Values, FEATURE_FIELD_STITCH, Format(rsFeaturesHemStitch, [UnitText]), ffkText, nil, Style <> hsBlind);
  AddField(Result, Values, FEATURE_FIELD_NOTCHES, rsFeaturesHemNotches, ffkCheck);
end;

function FacingForm(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  const UnitText: string): TFeatureForm;
var
  Materials: TStringArray;
  Index: integer;
begin
  Result := Default(TFeatureForm);
  Result.CanApply := Length(Selection.EdgeKeys) > 0;
  if Result.CanApply then
    Result.Header := Format(rsFeaturesAlong, [EdgeNames(Pattern, Selection.EdgeKeys)])
  else
    Result.Header := rsFeaturesFacingChoose;
  Result.Note := rsFeaturesFacingNote;
  Materials := nil;
  for Index := 0 to Pattern.MaterialCount - 1 do
    Insert(Pattern.Materials[Index].Name, Materials, Length(Materials));
  AddField(Result, Values, FEATURE_FIELD_WIDTH, Format(rsFeaturesFacingWidth, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_PLACE, rsFeaturesFacingPlace, ffkChoice, [rsFeaturesFacingInPlace,
    rsFeaturesFacingAside]);
  AddField(Result, Values, FEATURE_FIELD_INTERFACING, rsFeaturesFacingInterfacing, ffkCheck);
  // A material of the pattern, or a new one's name typed in
  AddField(Result, Values, FEATURE_FIELD_MATERIAL, '', ffkCombo, Materials, Checked(Values, FEATURE_FIELD_INTERFACING));
end;

function ButtonsForm(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  const UnitText: string): TFeatureForm;
var
  StartName, EndName: string;
  Edge: TEdgeObject;
begin
  Result := Default(TFeatureForm);
  Result.CanApply := Length(Selection.EdgeKeys) in [1, 2];
  StartName := rsFeaturesButtonStart;
  EndName := rsFeaturesButtonEnd;
  if not Result.CanApply then
    Result.Header := rsFeaturesButtonsChoose
  else
  begin
    if Length(Selection.EdgeKeys) = 1 then
      Result.Header := Format(rsFeaturesButtonsHoles, [NameOf(Pattern, Selection.EdgeKeys[0])])
    else
      Result.Header := Format(rsFeaturesButtonsBoth, [NameOf(Pattern, Selection.EdgeKeys[0]),
        NameOf(Pattern, Selection.EdgeKeys[1])]);
    Edge := TEdgeObject(Pattern.FindNode(Selection.EdgeKeys[0]));
    StartName := NameOf(Pattern, Edge.StartKey);
    EndName := NameOf(Pattern, Edge.EndKey);
  end;
  Result.Note := rsFeaturesButtonsNote;
  AddField(Result, Values, FEATURE_FIELD_SIZE, Format(rsFeaturesButtonSize, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_THICKNESS, Format(rsFeaturesButtonThickness, [UnitText]));
  AddField(Result, Values, FEATURE_FIELD_COUNT, rsFeaturesButtonCount);
  AddField(Result, Values, FEATURE_FIELD_FIRST, Format(rsFeaturesButtonFirst, [StartName, UnitText]));
  AddField(Result, Values, FEATURE_FIELD_LAST, Format(rsFeaturesButtonLast, [EndName, UnitText]));
  AddField(Result, Values, FEATURE_FIELD_DIRECTION, rsFeaturesButtonDirection, ffkChoice, [rsFeaturesButtonHorizontal,
    rsFeaturesButtonVertical]);
  AddField(Result, Values, FEATURE_FIELD_EXTENSION, rsFeaturesButtonExtension, ffkCheck);
  AddField(Result, Values, FEATURE_FIELD_EXTENSION_WIDTH, '', ffkText, nil, Checked(Values, FEATURE_FIELD_EXTENSION));
end;

function FeatureForm(Pattern: TPattern; Kind: TFeatureKind; const Selection: TFeatureSelection;
  const Values: TFeatureValues): TFeatureForm;
var
  UnitText: string;
begin
  UnitText := MEASURE_UNIT_NAMES[Pattern.Units];
  case Kind of
    fkZip: Result := ZipForm(Pattern, Selection, Values, UnitText);
    fkDart: Result := DartForm(Pattern, Selection, Values, UnitText);
    fkHem: Result := HemForm(Pattern, Selection, Values, UnitText);
    fkFacing: Result := FacingForm(Pattern, Selection, Values, UnitText);
    else
      Result := ButtonsForm(Pattern, Selection, Values, UnitText);
  end;
end;

function Typed(const Values: TFeatureValues; const Id: string): string;
begin
  Result := Trim(FeatureValue(Values, Id));
end;

// Each runs the feature inside the change Document has begun; False with
// the pattern's LastError when it cannot go there
function DoZip(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  out Done: string): boolean;
var
  Spec: TZipSpec;
  Made: TZipMade;
begin
  Spec := DefaultZip(Pattern, Selection.EdgeKey, ZipStyleOf(Values));
  Spec.FromEnd := ChoiceOf(Values, FEATURE_FIELD_FROM) = 1;
  Spec.Length := Typed(Values, FEATURE_FIELD_LENGTH);
  Spec.Allowance := Typed(Values, FEATURE_FIELD_ALLOWANCE);
  Spec.StitchDistance := Typed(Values, FEATURE_FIELD_STITCH);
  Spec.ShieldWidth := Typed(Values, FEATURE_FIELD_SHIELD);
  Done := Format(rsFeaturesZipDone, [NameOf(Pattern, Selection.EdgeKey)]);
  Result := InsertZip(Pattern, Spec, Made);
  if not Result then
    Exit;
  if Made.ShieldKey <> '' then
    Done := Format(rsFeaturesZipShield, [Done]);
  if Made.OtherSide then
    Done := Format(rsFeaturesZipOtherSide, [Done]);
end;

function DoDart(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  out Done: string): boolean;
var
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Spec := DefaultDart(Pattern, Selection.EdgeKey);
  Spec.FromEnd := ChoiceOf(Values, FEATURE_FIELD_FROM) = 1;
  Spec.TowardsEnd := ChoiceOf(Values, FEATURE_FIELD_FOLD) = 1;
  Spec.Position := Typed(Values, FEATURE_FIELD_POSITION);
  Spec.Width := Typed(Values, FEATURE_FIELD_WIDTH);
  Spec.Depth := Typed(Values, FEATURE_FIELD_DEPTH);
  Spec.HoleInset := Typed(Values, FEATURE_FIELD_HOLE);
  // A repeat's point is made an object of its own to run to
  if Selection.PointKey <> '' then
    Spec.ApexKey := Pattern.UsePoint(Selection.PointKey);
  Result := InsertDart(Pattern, Spec, Made);
  Done := '';
  if Result then
    Done := Format(rsFeaturesDartDone, [NameOf(Pattern, Made.PieceKey)]);
end;

procedure AddProblems(var Done: string; const Problems: array of string);
var
  Problem: string;
begin
  for Problem in Problems do
    Done := Format(rsFeaturesHemProblem, [Done, Problem]);
end;

function DoHem(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  out Done: string): boolean;
var
  Spec: THemSpec;
  Made: THemMade;
begin
  Spec := DefaultHem(Pattern, Selection.EdgeKeys, HemStyleOf(Values));
  Spec.Depth := Typed(Values, FEATURE_FIELD_DEPTH);
  Spec.TurnUnder := Typed(Values, FEATURE_FIELD_TURN_UNDER);
  Spec.StitchDistance := Typed(Values, FEATURE_FIELD_STITCH);
  Spec.Notches := Checked(Values, FEATURE_FIELD_NOTCHES);
  Done := Format(rsFeaturesHemDone, [EdgeNames(Pattern, Selection.EdgeKeys)]);
  Result := InsertHem(Pattern, Spec, Made);
  if Result then
    AddProblems(Done, Made.Problems);
end;

function DoFacing(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  out Done: string): boolean;
var
  Spec: TFacingSpec;
  Made: TFacingMade;
begin
  Spec := DefaultFacing(Pattern, Selection.EdgeKeys);
  Spec.Width := Typed(Values, FEATURE_FIELD_WIDTH);
  Spec.Aside := ChoiceOf(Values, FEATURE_FIELD_PLACE) = 1;
  if Checked(Values, FEATURE_FIELD_INTERFACING) then
    Spec.Interfacing := Typed(Values, FEATURE_FIELD_MATERIAL);
  Done := Format(rsFeaturesFacingDone, [EdgeNames(Pattern, Selection.EdgeKeys)]);
  Result := InsertFacing(Pattern, Spec, Made);
end;

function DoButtons(Pattern: TPattern; const Selection: TFeatureSelection; const Values: TFeatureValues;
  out Done: string): boolean;
var
  Spec: TButtonsSpec;
  Made: TButtonsMade;
begin
  Spec := DefaultButtons(Pattern, Selection.EdgeKeys[0]);
  if Length(Selection.EdgeKeys) = 2 then
    Spec.ButtonsEdgeKey := Selection.EdgeKeys[1];
  Spec.Size := Typed(Values, FEATURE_FIELD_SIZE);
  Spec.Thickness := Typed(Values, FEATURE_FIELD_THICKNESS);
  Spec.Count := Typed(Values, FEATURE_FIELD_COUNT);
  Spec.First := Typed(Values, FEATURE_FIELD_FIRST);
  Spec.Last := Typed(Values, FEATURE_FIELD_LAST);
  Spec.Direction := TButtonDirection(Min(ChoiceOf(Values, FEATURE_FIELD_DIRECTION), Ord(High(TButtonDirection))));
  if Checked(Values, FEATURE_FIELD_EXTENSION) then
    Spec.Extension := Typed(Values, FEATURE_FIELD_EXTENSION_WIDTH);
  Done := Format(rsFeaturesButtonsDone, [EdgeNames(Pattern, Selection.EdgeKeys)]);
  Result := InsertButtons(Pattern, Spec, Made);
  if Result then
    AddProblems(Done, Made.Problems);
end;

function ApplyFeature(Document: TPatternDocument; Kind: TFeatureKind; const Selection: TFeatureSelection;
  const Values: TFeatureValues; out Message: string): boolean;
var
  Form: TFeatureForm;
  Pattern: TPattern;
  Done, UndoName: string;
begin
  Result := False;
  Pattern := Document.Pattern;
  if Document.ChangeOpen then
  begin
    Message := rsFeaturesBusy;
    Exit;
  end;
  Form := FeatureForm(Pattern, Kind, Selection, Values);
  if not Form.CanApply then
  begin
    Message := Form.Header;
    Exit;
  end;
  case Kind of
    fkZip: UndoName := rsFeaturesUndoZip;
    fkDart: UndoName := rsFeaturesUndoDart;
    fkHem: UndoName := rsFeaturesUndoHem;
    fkFacing: UndoName := rsFeaturesUndoFacing;
    else
      UndoName := rsFeaturesUndoButtons;
  end;
  Document.BeginChange(UndoName);
  case Kind of
    fkZip: Result := DoZip(Pattern, Selection, Values, Done);
    fkDart: Result := DoDart(Pattern, Selection, Values, Done);
    fkHem: Result := DoHem(Pattern, Selection, Values, Done);
    fkFacing: Result := DoFacing(Pattern, Selection, Values, Done);
    else
      Result := DoButtons(Pattern, Selection, Values, Done);
  end;
  if not Result then
  begin
    Message := Pattern.LastError;
    Document.CancelChange;
    Exit;
  end;
  Document.EndChange;
  if Document.ChangeRefused then
  begin
    Message := Pattern.LastError;
    Exit(False);
  end;
  Message := Done;
end;

end.
