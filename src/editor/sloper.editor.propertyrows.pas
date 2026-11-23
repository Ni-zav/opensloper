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

// What the properties panel shows for an object, row by row, and the edits
// its rows make, each one undo step. The desktop panel builds its controls
// for the same rows and makes the same edits; the web editor gets the rows
// as data (editor_properties) and draws them. Kept free of the LCL so the
// tests can read the rows and make the edits.
unit Sloper.Editor.PropertyRows;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Sloper.Core.Evaluator, Sloper.Core.Draft, Sloper.Core.Seam, Sloper.Core.Pattern, Sloper.Core.Piece,
  Sloper.Core.Note, Sloper.Core.Materials, Sloper.Document.PatternDocument;

type
  // What a row holds: text to read, the object's name or a formula to edit, a
  // choice, a box to tick, a button, the object's problem, a number, text of
  // several lines, a font's name, or a colour
  TPropertyRowKind = (prkText, prkName, prkFormula, prkChoice, prkCheck, prkButton, prkProblem, prkNumber, prkLongText,
    prkFont, prkColor);

  TPropertyRow = record
    // Which row it is, for an edit: one of the PROPERTY_ROW_ names, or a
    // formula's field name for a prkFormula row
    Id: string;
    Kind: TPropertyRowKind;
    Caption: string;
    // A prkFormula row's field
    Field: string;
    // What a text, name, formula, long text, font or problem row shows, a
    // button's caption, the caption beside a check row's box, or a colour
    // row's own colour, '' when it follows the material
    Text: string;
    // A choice row's items, in the order of the values they stand for, and the
    // one chosen; a font row's first item names the default font
    Choices: TStringArray;
    Choice: integer;
    Checked: boolean;
    Hint: string;
    // False when the row cannot be changed now
    Enabled: boolean;
    // A number row's value, its range, its step and how many decimals it shows
    Value, MinValue, MaxValue, Step: double;
    Decimals: integer;
    // A colour row's colour as drawn, from its material when it has none of its own
    Color: string;
  end;
  TPropertyRowArray = array of TPropertyRow;
  PPropertyRow = ^TPropertyRow;

  // Where a section's rows go, top to bottom: every section adds its rows for
  // one place before any section adds rows for the next
  TSectionPlace = (spType, spName, spFields, spRows, spResult, spEnd);

const
  PROPERTY_ROW_TYPE = 'type';
  PROPERTY_ROW_NAME = 'name';
  PROPERTY_ROW_LOCKED = 'locked';
  PROPERTY_ROW_ROLE = 'role';
  PROPERTY_ROW_MARKED_ON = 'markedOn';
  PROPERTY_ROW_MARKER = 'marker';
  PROPERTY_ROW_FROM = 'from';
  PROPERTY_ROW_TO = 'to';
  PROPERTY_ROW_ALONG = 'along';
  PROPERTY_ROW_ENDS = 'ends';
  PROPERTY_ROW_SIDE_A = 'sideA';
  PROPERTY_ROW_SIDE_B = 'sideB';
  PROPERTY_ROW_FLIP = 'flip';
  PROPERTY_ROW_MADE_BY = 'madeBy';
  PROPERTY_ROW_RESULT = 'result';
  PROPERTY_ROW_DIFFERENCE = 'difference';
  PROPERTY_ROW_PROBLEM = 'problem';
  PROPERTY_ROW_CUT = 'cut';
  PROPERTY_ROW_MIRRORED = 'mirrored';
  PROPERTY_ROW_FOLD = 'fold';
  // Followed by the dart's index in PieceDarts
  PROPERTY_ROW_DART = 'dart';
  PROPERTY_ROW_OWN_ALLOWANCE = 'ownAllowance';
  PROPERTY_ROW_MIRROR_ENDS = 'mirrorEnds';
  // Followed by the edge's index in the piece's path
  PROPERTY_ROW_EDGE_ENDS = 'edgeEnds';
  PROPERTY_ROW_GRAIN = 'grain';
  PROPERTY_ROW_GRAIN_FROM = 'grainFrom';
  PROPERTY_ROW_GRAIN_TO = 'grainTo';
  PROPERTY_ROW_MATERIAL = 'material';
  PROPERTY_ROW_FILL = 'fill';
  PROPERTY_ROW_FILL_COLOR = 'fillColor';
  PROPERTY_ROW_NOTE_TEXT = 'noteText';
  PROPERTY_ROW_NOTE_SIZE = 'noteSize';
  PROPERTY_ROW_NOTE_PRINT = 'notePrint';
  PROPERTY_ROW_NOTE_ALIGN = 'noteAlign';
  PROPERTY_ROW_NOTE_BOX = 'noteBox';
  PROPERTY_ROW_NOTE_FONT = 'noteFont';
  PROPERTY_ROW_NOTE_BOLD = 'noteBold';
  PROPERTY_ROW_NOTE_ITALIC = 'noteItalic';
  PROPERTY_ROW_NOTE_LEADER = 'noteLeader';
  PROPERTY_ROW_NOTE_ANCHOR = 'noteAnchor';
  PROPERTY_ROW_NOTE_FREE = 'noteFree';
  MAX_CUT_COUNT = 99;
  NOTE_SIZE_STEP = 1;

type
  // A dart of a piece, as its cap row shows it: its legs and its caption
  TDartRow = record
    Legs: TPieceDart;
    Caption: string;
  end;
  TDartRowArray = array of TDartRow;
  TPathIndexArray = array of integer;

// The object the panel shows for this key: a repeat's first point shows the repeat
function PropertyKey(Pattern: TPattern; const Key: string): string;
// A line, curve or arc the user drew can change type; copies and parts follow other edges
function CanChangeType(Node: TEvalNode): boolean;
// The types a CanChangeType edge can become, its own among them
function EdgeTypeChoices(Node: TEvalNode): TStringArray;
// A field another section than the formulas shows in its own rows, or none
function FieldShownApart(Node: TEvalNode; const FieldName: string): boolean;
// A field's row caption: an edge's own allowance is named after its edge
function FieldRowCaption(Pattern: TPattern; Node: TEvalNode; const FieldName: string): string;
// A note's draft value field: value1, value2
function IsNoteValue(const FieldName: string): boolean;
// The marker fields a point or repeat shows under its marker
function IsMarkerField(const FieldName: string): boolean;
// The marker box's items, in the order of TPointMarker
function MarkerChoices: TStringArray;
// The repeat ends box's items: included first
function RepeatEndsChoices: TStringArray;
// Every row the object shows, in order, with its values
function PropertyRows(Pattern: TPattern; Node: TEvalNode): TPropertyRowArray;
// A formula field's caption with "Change" for its undo step
function FieldEditName(const FieldName: string): string;

// A piece's darts: each seam joining two neighbouring edges of it, and any
// other pair of edges with a cap
function PieceDarts(Pattern: TPattern; Piece: TPieceObject): TDartRowArray;
// How the dart is capped
function DartPress(Piece: TPieceObject; const Legs: TPieceDart): TDartPress;
// The cap box's items, in the order of TDartPress
function DartCapChoices(Pattern: TPattern; const Legs: TPieceDart): TStringArray;
// The edges a piece can fold on: '' for none, then its straight edges
function FoldKeys(Pattern: TPattern; Piece: TPieceObject): TStringArray;
// The path indexes of the edges with no allowance of their own
function EdgesWithoutOwnAllowance(Piece: TPieceObject): TPathIndexArray;
// The path indexes of the edges whose allowance ends are as given
function EdgesWithEnds(Piece: TPieceObject; Value: TAllowanceEnd): TPathIndexArray;
// The points a grainline can run between: '' for none chosen, then every point
function GrainPointKeys(Pattern: TPattern): TStringArray;
// Their names, after the prompt to choose one
function GrainPointChoices(Pattern: TPattern): TStringArray;
// The colour a piece is filled with, its own or its material's, or '' when it has none
function PieceDrawnColor(Pattern: TPattern; Piece: TPieceObject): string;

// Renames the object (FieldName '') or sets one of its formulas, as one undo
// step. Text the field already shows makes no step. False refuses it, with
// Reason and ErrorPos (1-based, 0 for none) where in a formula.
function CommitPropertyField(Document: TPatternDocument; Node: TEvalNode; const FieldName, Text: string;
  out Reason: string; out ErrorPos: integer): boolean;
// The text the field shows: the name for FieldName '', else the formula with names
function PropertyFieldText(Pattern: TPattern; Node: TEvalNode; const FieldName: string): string;

// The steps the other rows make, each one undo step, or none when the object
// already is so. False refuses, with Reason: the pattern's, or a lock's.
function SetLockedStep(Document: TPatternDocument; Node: TEvalNode; Lock: boolean; out Reason: string): boolean;
// Makes the edge a line or curve, as Choice in EdgeTypeChoices says. The
// edge is replaced by one with the same ID.
function ConvertEdgeStep(Document: TPatternDocument; Node: TEvalNode; Choice: integer; out Reason: string): boolean;
function SetEdgeRoleStep(Document: TPatternDocument; Node: TEvalNode; Role: TEdgeRole; out Reason: string): boolean;
function SetMarkerStep(Document: TPatternDocument; Node: TEvalNode; Marker: TPointMarker; out Reason: string): boolean;
function SetRepeatEndsStep(Document: TPatternDocument; Node: TEvalNode; Include: boolean; out Reason: string): boolean;
function FlipSeamStep(Document: TPatternDocument; Node: TEvalNode; out Reason: string): boolean;
// A piece's rows. A run of changes with the same MergeKey is one undo step.
function SetCutStep(Document: TPatternDocument; Node: TEvalNode; Count: integer; Mirrored: boolean; out Reason: string;
  const MergeKey: string = ''): boolean;
function SetFoldStep(Document: TPatternDocument; Node: TEvalNode; const EdgeKey: string; out Reason: string): boolean;
function SetDartCapStep(Document: TPatternDocument; Node: TEvalNode; const Legs: TPieceDart; Press: TDartPress;
  out Reason: string): boolean;
// Gives the edge its own allowance, starting at the piece's, or takes it away
function SetOwnAllowanceStep(Document: TPatternDocument; Node: TEvalNode; PathIndex: integer; Own: boolean;
  out Reason: string): boolean;
function SetAllowanceEndStep(Document: TPatternDocument; Node: TEvalNode; PathIndex: integer; Value: TAllowanceEnd;
  out Reason: string): boolean;
// The points are only used for gkPoints; an angle starts at DEFAULT_GRAIN_ANGLE
function SetGrainStep(Document: TPatternDocument; Node: TEvalNode; Kind: TGrainKind; const StartKey, EndKey: string;
  out Reason: string): boolean;
// MaterialIndex -1 for none
function SetPieceMaterialStep(Document: TPatternDocument; Node: TEvalNode; MaterialIndex: integer;
  out Reason: string): boolean;
function SetPieceFillStep(Document: TPatternDocument; Node: TEvalNode; const AColor: string; Style: TPieceFillStyle;
  out Reason: string): boolean;
// A note's rows. The text is as typed in the field, with names.
function SetNoteTextStep(Document: TPatternDocument; Node: TEvalNode; const FieldText: string;
  out Reason: string): boolean;
function SetNoteSizeStep(Document: TPatternDocument; Node: TEvalNode; Size: double; out Reason: string;
  const MergeKey: string = ''): boolean;
function SetNotePrintStep(Document: TPatternDocument; Node: TEvalNode; Print: boolean; out Reason: string): boolean;
// The leader, alignment, box, bold and italic together
function SetNoteLookStep(Document: TPatternDocument; Node: TEvalNode; Leader: TNoteLeader; Align: TTextAlign;
  Boxed, Bold, Italic: boolean; out Reason: string): boolean;
// '' for the default font
function SetNoteFontStep(Document: TPatternDocument; Node: TEvalNode; const FontName: string;
  out Reason: string): boolean;
function MakeNoteFreeStep(Document: TPatternDocument; Node: TEvalNode; out Reason: string): boolean;

// Makes the edit of a row that is not a formula or name: Value is a choice's
// index, or 1 for a ticked box, and a button ignores it. False refuses, with Reason.
function CommitPropertyRow(Document: TPatternDocument; Node: TEvalNode; const RowId: string; Value: integer;
  out Reason: string): boolean;
// The grainline between two points, given by their indexes in the From and To rows' choices
function CommitGrainPoints(Document: TPatternDocument; Node: TEvalNode; FromChoice, ToChoice: integer;
  out Reason: string): boolean;
// A number row's edit; runs of them on one row are one undo step
function CommitPropertyNumber(Document: TPatternDocument; Node: TEvalNode; const RowId: string; Value: double;
  out Reason: string): boolean;
// A long text, font or colour row's edit, as typed
function CommitPropertyText(Document: TPatternDocument; Node: TEvalNode; const RowId, Text: string;
  out Reason: string): boolean;

resourcestring
  rsPropNothing = 'Nothing selected';
  rsPropMany = '%d objects selected';
  rsPropType = 'Type';
  rsPropName = 'Name';
  rsPropRole = 'Role';
  rsPropRepeatFrom = 'From';
  rsPropRepeatTo = 'To';
  rsPropRepeatEdge = 'Along';
  rsPropEnds = 'Ends';
  rsPropEndsInclude = 'Include the ends';
  rsPropEndsExclude = 'Leave out the ends';
  rsPropChangeEnds = 'Change repeat ends';
  rsPropMarkedOn = 'Marked on';
  rsPropMarker = 'Marker';
  rsPropMarkerPlain = 'Plain';
  rsPropMarkerHole = 'Hole';
  rsPropMarkerButton = 'Button';
  rsPropMarkerMatch = 'Match dot';
  rsPropMarkerButtonhole = 'Buttonhole';
  rsPropChangeMarker = 'Change marker';
  rsPropPosition = 'Position';
  rsPropLength = 'Length';
  rsPropPerimeter = 'Perimeter';
  rsPropSideA = 'Side A';
  rsPropSideB = 'Side B';
  rsPropSeamLengths = 'Lengths';
  rsPropSeamDifference = 'Difference';
  rsPropDirection = 'Direction';
  rsPropFlip = 'Flip';
  rsPropFlipSeam = 'Flip seam';
  rsPropMadeBy = 'Made by';
  rsPropChangeType = 'Change edge type';
  rsPropEdit = 'Change %s';
  rsPropRename = 'Rename';
  rsPropChangeRole = 'Change role';
  rsPropLocked = 'Locked';
  rsPropLockedHint = 'A locked object cannot be moved, edited or deleted, but its formulas still run';
  rsPropLock = 'Lock';
  rsPropUnlock = 'Unlock';
  rsPropGone = 'This object no longer exists';
  rsPropNoSuchRow = 'The object has no such property';
  rsPropNoChoice = 'There is no such choice';
  rsPropCut = 'Cut';
  rsPropMirrored = 'Mirrored';
  rsPropFold = 'Fold';
  rsPropNoFold = 'None';
  rsPropMaterial = 'Material';
  rsPropNoMaterial = 'None';
  rsPropChangeMaterial = 'Change material';
  rsPropFillStyle = 'Fill';
  rsPropFillColor = 'Colour';
  rsPropFromMaterial = 'From material';
  rsPropFillTint = 'Tint';
  rsPropFillHatch = 'Hatching';
  rsPropChooseColor = 'Choose…';
  rsPropChangeFill = 'Change fill';
  rsPropGrainline = 'Grainline';
  rsPropGrainNone = 'None';
  rsPropGrainAngle = 'At an angle';
  rsPropGrainPoints = 'Between two points';
  rsPropGrainFrom = 'Grainline from';
  rsPropGrainTo = 'Grainline to';
  rsPropGrainChoose = 'Choose...';
  rsPropChangeGrainline = 'Change grainline';
  rsPropOwnAllowance = 'Own allowance';
  rsPropOwnAllowancePrompt = 'Add for an edge...';
  rsPropOwnAllowanceHint = 'Give one edge its own seam allowance; empty its row to go back to the piece''s';
  rsPropAddEdgeAllowance = 'Add edge allowance';
  rsPropRemoveEdgeAllowance = 'Remove edge allowance';
  rsPropMirrorEnds = 'Mirrored ends';
  rsPropMirrorEndsPrompt = 'Add for an edge...';
  rsPropMirrorEndsHint = 'Shape an edge''s allowance ends as the edges beside it, mirrored, so it lies flat turned up, ' +
    'as a hem does';
  rsPropEndsOf = 'Ends of %s';
  rsPropEndsPlain = 'Plain';
  rsPropEndsMirrored = 'Mirrored';
  rsPropChangeAllowanceEnd = 'Change allowance ends';
  rsPropChangeCut = 'Change cut';
  rsPropChangeFold = 'Change fold';
  rsPropDartCap = 'Cap on %s';
  rsPropDartCapHint = 'Shapes the seam allowance across the dart as it lies pressed, so it sews into the seam';
  rsPropNoCap = 'None';
  rsPropCapTowards = 'Pressed towards %s';
  rsPropDartLegs = '%s and %s';
  rsPropChangeDartCap = 'Change dart cap';
  rsPropNoteText = 'Text';
  rsPropNoteSize = 'Size (points)';
  rsPropNotePrint = 'Print';
  rsPropNotePrintCaption = 'Print and export it';
  rsPropNoteAnchor = 'Hangs from';
  rsPropNoteFree = 'Make free';
  rsPropNoteFreeHint = 'Unhook the note, leaving it where it is, so what it hangs from can be deleted';
  rsPropChangeNoteText = 'Change note text';
  rsPropChangeNoteSize = 'Change note size';
  rsPropChangeNotePrint = 'Change note printing';
  rsPropFreeNote = 'Make note free';
  rsPropNoteLeader = 'Leader';
  rsPropNoteLeaderNone = 'None (a plain note)';
  rsPropNoteLeaderArrow = 'Arrow';
  rsPropNoteLeaderDot = 'Dot';
  rsPropNoteLeaderLine = 'Line';
  rsPropNoteAlign = 'Lines';
  rsPropNoteAlignLeft = 'Left';
  rsPropNoteAlignCentre = 'Centred';
  rsPropNoteAlignRight = 'Right';
  rsPropNoteBox = 'Box';
  rsPropNoteBoxCaption = 'On a white box';
  rsPropChangeNoteLook = 'Change note';
  rsPropNoteFont = 'Font';
  rsPropNoteStyle = 'Style';
  rsPropNoteBold = 'Bold';
  rsPropNoteItalic = 'Italic';
  rsPropChangeNoteFont = 'Change note font';
  rsPropNoteTextHint = 'Draft values go in {= }, such as {=Line_A_B.length}';
  rsPropOwnColor = 'Own colour';
  rsPropGrainBothPoints = 'Choose both points of the grainline';
  rsPropNoDart = 'The piece has no such dart';
  rsPropNoEdge = 'The piece has no such edge';
  rsPropBadNumber = 'The number is out of range';
  rsPropFontDefault = 'Default (sans-serif)';
  rsPropFontHint = 'The font it prints in. One not installed, or with PostScript outlines, prints in the default font.';

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Transform, Sloper.Core.PatternMaterials, Sloper.Editor.ObjectList,
  Sloper.Editor.PropertyText;

function PropertyKey(Pattern: TPattern; const Key: string): string;
var
  Node: TEvalNode;
begin
  Result := Key;
  Node := Pattern.FindNode(Key);
  if (Node is TRepeatPoint) and (TRepeatPoint(Node).Index = 1) then
    Result := TRepeatPoint(Node).Source.Key;
end;

function CanChangeType(Node: TEvalNode): boolean;
begin
  Result := (Node.ClassType = TLineObject) or (Node.ClassType = TCurveObject) or (Node.ClassType = TArcObject);
end;

function EdgeTypeChoices(Node: TEvalNode): TStringArray;
begin
  if Node is TArcObject then
    Result := [rsTypeArc, rsTypeLine]
  else
    Result := [rsTypeLine, rsTypeCurve];
end;

// A note's draft value field: value1, value2
function IsNoteValue(const FieldName: string): boolean;
begin
  Result := (Copy(FieldName, 1, Length(NOTE_VALUE_FIELD)) = NOTE_VALUE_FIELD) and
    (StrToIntDef(Copy(FieldName, Length(NOTE_VALUE_FIELD) + 1, MaxInt), 0) > 0);
end;

function IsMarkerField(const FieldName: string): boolean;
begin
  Result := (FieldName = MARKER_SIZE_FIELD) or (FieldName = MARKER_ANGLE_FIELD) or (FieldName = MARKER_OFFSET_FIELD);
end;

// A repeat's points share the repeat's marker
function HasMarkerRows(Node: TEvalNode): boolean;
begin
  Result := ((Node is TPointObject) and not (Node is TRepeatPoint)) or (Node is TRepeatObject);
end;

// A marker's size is shown under the marker, or not at all; a piece's
// grainline angle under its grainline; a note's draft values are part of its text
function FieldShownApart(Node: TEvalNode; const FieldName: string): boolean;
begin
  Result := (FieldName = MARKER_SIZE_FIELD) or (HasMarkerRows(Node) and IsMarkerField(FieldName)) or
    ((Node is TPieceObject) and (FieldName = GRAIN_ANGLE_FIELD)) or ((Node is TNoteObject) and IsNoteValue(FieldName));
end;

function FieldRowCaption(Pattern: TPattern; Node: TEvalNode; const FieldName: string): string;
begin
  Result := '';
  if Node is TPieceObject then
    Result := EdgeAllowanceCaption(Pattern, TPieceObject(Node), FieldName);
  if Result = '' then
    Result := FieldCaption(FieldName);
end;

function MarkerChoices: TStringArray;
begin
  Result := [rsPropMarkerPlain, rsPropMarkerHole, rsPropMarkerButton, rsPropMarkerMatch, rsPropMarkerButtonhole];
end;

function RepeatEndsChoices: TStringArray;
begin
  Result := [rsPropEndsInclude, rsPropEndsExclude];
end;

function FieldEditName(const FieldName: string): string;
begin
  Result := Format(rsPropEdit, [FieldCaption(FieldName)]);
end;

function RoleChoices: TStringArray;
var
  Role: TEdgeRole;
begin
  Result := nil;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    Insert(RoleCaption(Role), Result, Length(Result));
end;

function IndexOfText(const Items: TStringArray; const AText: string): integer;
begin
  for Result := 0 to High(Items) do
    if Items[Result] = AText then
      Exit;
  Result := -1;
end;

function NameOf(Pattern: TPattern; const Key: string): string;
var
  Found: TEvalNode;
begin
  Found := Pattern.FindNode(Key);
  if not Assigned(Found) then
    Result := Key
  else
    Result := Found.DisplayName;
end;

type
  // Gathers the rows in order
  TRowBuilder = record
    Rows: TPropertyRowArray;
    procedure Add(const AId: string; AKind: TPropertyRowKind; const ACaption, AText: string);
    procedure AddChoice(const AId, ACaption: string; const AChoices: TStringArray; AChoice: integer);
    procedure AddCheck(const AId, ACaption, ABoxCaption: string; AChecked: boolean);
    procedure AddNumber(const AId, ACaption: string; AValue, AMin, AMax, AStep: double; ADecimals: integer);
    // The last row added
    function Last: PPropertyRow;
  end;

procedure TRowBuilder.Add(const AId: string; AKind: TPropertyRowKind; const ACaption, AText: string);
var
  Row: TPropertyRow;
begin
  Row := Default(TPropertyRow);
  Row.Id := AId;
  Row.Kind := AKind;
  Row.Caption := ACaption;
  Row.Text := AText;
  Row.Choice := -1;
  Row.Enabled := True;
  if AKind = prkFormula then
    Row.Field := AId;
  Insert(Row, Rows, Length(Rows));
end;

procedure TRowBuilder.AddChoice(const AId, ACaption: string; const AChoices: TStringArray; AChoice: integer);
begin
  Add(AId, prkChoice, ACaption, '');
  Rows[High(Rows)].Choices := AChoices;
  Rows[High(Rows)].Choice := AChoice;
end;

procedure TRowBuilder.AddCheck(const AId, ACaption, ABoxCaption: string; AChecked: boolean);
begin
  Add(AId, prkCheck, ACaption, ABoxCaption);
  Last^.Checked := AChecked;
end;

procedure TRowBuilder.AddNumber(const AId, ACaption: string; AValue, AMin, AMax, AStep: double; ADecimals: integer);
begin
  Add(AId, prkNumber, ACaption, '');
  Last^.Value := AValue;
  Last^.MinValue := AMin;
  Last^.MaxValue := AMax;
  Last^.Step := AStep;
  Last^.Decimals := ADecimals;
end;

function TRowBuilder.Last: PPropertyRow;
begin
  Result := @Rows[High(Rows)];
end;

// Type, name and formula fields first, as TCommonSection
procedure AddCommonRows(var Builder: TRowBuilder; Pattern: TPattern; Node: TEvalNode; Place: TSectionPlace);
var
  Index: integer;
  FieldName, Text: string;
begin
  case Place of
    spType:
      if not CanChangeType(Node) then
        Builder.Add(PROPERTY_ROW_TYPE, prkText, rsPropType, TypeCaption(Node));
    spName:
    begin
      if Node is TRepeatPoint then
        Builder.Add(PROPERTY_ROW_NAME, prkText, rsPropName, TRepeatPoint(Node).Name)
      else if Node is TDraftObject then
        Builder.Add(PROPERTY_ROW_NAME, prkName, rsPropName, Node.DisplayName);
      if Node is TDraftObject then
      begin
        Builder.Add(PROPERTY_ROW_LOCKED, prkCheck, rsPropLocked, '');
        Builder.Rows[High(Builder.Rows)].Checked := Pattern.IsLocked(Node);
        Builder.Rows[High(Builder.Rows)].Hint := rsPropLockedHint;
      end;
    end;
    spFields:
      for Index := 0 to Node.FieldCount - 1 do
      begin
        FieldName := Node.Fields[Index].Name;
        if not FieldShownApart(Node, FieldName) then
          Builder.Add(FieldName, prkFormula, FieldRowCaption(Pattern, Node, FieldName), Pattern.FormulaText(Node, FieldName));
      end;
    spResult:
    begin
      if CopyTransformKey(Node) <> '' then
        Builder.Add(PROPERTY_ROW_MADE_BY, prkText, rsPropMadeBy, NameOf(Pattern, CopyTransformKey(Node)));
      Text := '';
      if (Node is TNoteObject) and Node.HasResult then
        Text := PositionText(TNoteObject(Node).Position, Pattern.Units)
      else if Node is TDraftObject then
        Text := ResultText(TDraftObject(Node), Pattern.Units);
      if Node is TPointObject then
        Builder.Add(PROPERTY_ROW_RESULT, prkText, rsPropPosition, Text)
      else if Node is TEdgeObject then
        Builder.Add(PROPERTY_ROW_RESULT, prkText, rsPropLength, Text)
      else if Node is TPieceObject then
        Builder.Add(PROPERTY_ROW_RESULT, prkText, rsPropPerimeter, Text)
      else if Node is TSeamObject then
        Builder.Add(PROPERTY_ROW_RESULT, prkText, rsPropSeamLengths, Text)
      else if Node is TNoteObject then
        Builder.Add(PROPERTY_ROW_RESULT, prkText, rsPropPosition, Text);
    end;
    spEnd:
      if Node.State = esValid then
        Builder.Add(PROPERTY_ROW_PROBLEM, prkProblem, '', '')
      else
        Builder.Add(PROPERTY_ROW_PROBLEM, prkProblem, '', Node.Message);
  end;
end;

// A line, curve or arc: its type when it can change, its role and the pieces it is marked on
procedure AddEdgeRows(var Builder: TRowBuilder; Pattern: TPattern; Edge: TEdgeObject; Place: TSectionPlace);
var
  Choices: TStringArray;
begin
  case Place of
    spType:
      if CanChangeType(Edge) then
      begin
        Choices := EdgeTypeChoices(Edge);
        Builder.AddChoice(PROPERTY_ROW_TYPE, rsPropType, Choices, IndexOfText(Choices, TypeCaption(Edge)));
      end;
    spRows:
    begin
      Builder.AddChoice(PROPERTY_ROW_ROLE, rsPropRole, RoleChoices, Ord(Edge.Role));
      Builder.Add(PROPERTY_ROW_MARKED_ON, prkText, rsPropMarkedOn, MarkedOnText(Pattern, Edge));
    end;
  end;
end;

// A point's or repeat's marker, its fields, and the pieces it is marked on
procedure AddMarkerRows(var Builder: TRowBuilder; Pattern: TPattern; Node: TDraftObject);
var
  Index: integer;
  FieldName: string;
begin
  Builder.AddChoice(PROPERTY_ROW_MARKER, rsPropMarker, MarkerChoices, Ord(Node.Marker));
  for Index := 0 to Node.FieldCount - 1 do
  begin
    FieldName := Node.Fields[Index].Name;
    if IsMarkerField(FieldName) then
      Builder.Add(FieldName, prkFormula, FieldCaption(FieldName), Pattern.FormulaText(Node, FieldName));
  end;
  Builder.Add(PROPERTY_ROW_MARKED_ON, prkText, rsPropMarkedOn, MarkedOnText(Pattern, Node));
end;

// What a repeat runs between or along, and whether it includes the ends
procedure AddRepeatRows(var Builder: TRowBuilder; Pattern: TPattern; ARepeat: TRepeatObject);
begin
  if ARepeat.Edge <> '' then
    Builder.Add(PROPERTY_ROW_ALONG, prkText, rsPropRepeatEdge, NameOf(Pattern, ARepeat.Edge))
  else
  begin
    Builder.Add(PROPERTY_ROW_FROM, prkText, rsPropRepeatFrom, NameOf(Pattern, ARepeat.FirstPoint));
    Builder.Add(PROPERTY_ROW_TO, prkText, rsPropRepeatTo, NameOf(Pattern, ARepeat.LastPoint));
  end;
  Builder.AddChoice(PROPERTY_ROW_ENDS, rsPropEnds, RepeatEndsChoices, Ord(not ARepeat.IncludeEnds));
end;

// A seam's sides and its direction; the difference in their lengths under the lengths
procedure AddSeamRows(var Builder: TRowBuilder; Pattern: TPattern; Seam: TSeamObject; Place: TSectionPlace);
begin
  case Place of
    spRows:
    begin
      Builder.Add(PROPERTY_ROW_SIDE_A, prkText, rsPropSideA, SeamSideText(Pattern, Seam.SideA));
      Builder.Add(PROPERTY_ROW_SIDE_B, prkText, rsPropSideB, SeamSideText(Pattern, Seam.SideB));
      Builder.Add(PROPERTY_ROW_FLIP, prkButton, rsPropDirection, rsPropFlip);
    end;
    spResult:
      if Seam.HasResult then
        Builder.Add(PROPERTY_ROW_DIFFERENCE, prkText, rsPropSeamDifference, SeamDifferenceText(Seam, Pattern.Units))
      else
        Builder.Add(PROPERTY_ROW_DIFFERENCE, prkText, rsPropSeamDifference, '');
  end;
end;

function PieceDarts(Pattern: TPattern; Piece: TPieceObject): TDartRowArray;
var
  Darts: TDartRowArray;
  Index, First, Second, Count: integer;
  Seam: TSeamObject;
  Dart: TPieceDart;

  procedure AddDart(const FirstKey, SecondKey, Caption: string);
  var
    Known: TDartRow;
  begin
    for Known in Darts do
      if ((Known.Legs.FirstKey = FirstKey) and (Known.Legs.SecondKey = SecondKey)) or
        ((Known.Legs.FirstKey = SecondKey) and (Known.Legs.SecondKey = FirstKey)) then
        Exit;
    SetLength(Darts, Length(Darts) + 1);
    Darts[High(Darts)].Legs := Default(TPieceDart);
    Darts[High(Darts)].Legs.FirstKey := FirstKey;
    Darts[High(Darts)].Legs.SecondKey := SecondKey;
    Darts[High(Darts)].Caption := Caption;
  end;

begin
  Darts := nil;
  Count := Length(Piece.Path);
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    if not (Pattern.Objects[Index] is TSeamObject) then
      Continue;
    Seam := TSeamObject(Pattern.Objects[Index]);
    if (Length(Seam.SideA) <> 1) or (Length(Seam.SideB) <> 1) or (Seam.SideA[0].PieceKey <> Piece.Key) or
      (Seam.SideB[0].PieceKey <> Piece.Key) then
      Continue;
    First := Piece.PathIndexOf(Seam.SideA[0].EdgeKey);
    Second := Piece.PathIndexOf(Seam.SideB[0].EdgeKey);
    if (First >= 0) and (Second >= 0) and (((First + 1) mod Count = Second) or ((Second + 1) mod Count = First)) then
      AddDart(Seam.SideA[0].EdgeKey, Seam.SideB[0].EdgeKey, Seam.DisplayName);
  end;
  for Dart in Copy(Piece.Darts) do
    AddDart(Dart.FirstKey, Dart.SecondKey, Format(rsPropDartLegs, [NameOf(Pattern, Dart.FirstKey),
      NameOf(Pattern, Dart.SecondKey)]));
  Result := Darts;
end;

function DartPress(Piece: TPieceObject; const Legs: TPieceDart): TDartPress;
var
  Dart: integer;
begin
  Dart := Piece.DartOf(Legs.FirstKey, Legs.SecondKey);
  if Dart < 0 then
    Result := dpNone
  else if Piece.Darts[Dart].TowardsFirst = (Piece.Darts[Dart].FirstKey = Legs.FirstKey) then
    Result := dpFirst
  else
    Result := dpSecond;
end;

function DartCapChoices(Pattern: TPattern; const Legs: TPieceDart): TStringArray;
begin
  Result := [rsPropNoCap, Format(rsPropCapTowards, [NameOf(Pattern, Legs.FirstKey)]),
    Format(rsPropCapTowards, [NameOf(Pattern, Legs.SecondKey)])];
end;

// Only straight edges can be a fold
function FoldKeys(Pattern: TPattern; Piece: TPieceObject): TStringArray;
var
  Entry: TPieceEdge;
  Edge: TEvalNode;
begin
  Result := [''];
  for Entry in Piece.Path do
  begin
    Edge := Pattern.FindNode(Entry.EdgeKey);
    if (Edge is TEdgeObject) and IsStraightEdge(TEdgeObject(Edge)) then
      Insert(Entry.EdgeKey, Result, Length(Result));
  end;
end;

function EdgesWithoutOwnAllowance(Piece: TPieceObject): TPathIndexArray;
var
  Index: integer;
begin
  Result := nil;
  for Index := 0 to High(Piece.Path) do
    if not Piece.HasOverride(Index) then
      Insert(Index, Result, Length(Result));
end;

function EdgesWithEnds(Piece: TPieceObject; Value: TAllowanceEnd): TPathIndexArray;
var
  Index: integer;
begin
  Result := nil;
  for Index := 0 to High(Piece.Path) do
    if Piece.Path[Index].AllowanceEnd = Value then
      Insert(Index, Result, Length(Result));
end;

function GrainPointKeys(Pattern: TPattern): TStringArray;
var
  Point: TPointObject;
begin
  Result := [''];
  for Point in Pattern.AllPoints do
    Insert(Point.Key, Result, Length(Result));
end;

function GrainPointChoices(Pattern: TPattern): TStringArray;
var
  Point: TPointObject;
begin
  Result := [rsPropGrainChoose];
  for Point in Pattern.AllPoints do
    Insert(Point.DisplayName, Result, Length(Result));
end;

function PieceDrawnColor(Pattern: TPattern; Piece: TPieceObject): string;
begin
  Result := Piece.FillColor;
  if (Result = '') and Assigned(Pattern.MaterialOf(Piece)) then
    Result := Pattern.MaterialOf(Piece).Color;
  if (Result = '') and (Pattern.MaterialCount > 0) then
    Result := Pattern.Materials[0].Color;
end;

// The names of the edges at these path indexes, after the prompt
function EdgeChoices(Pattern: TPattern; Piece: TPieceObject; const Prompt: string;
  const Indexes: TPathIndexArray): TStringArray;
var
  Index: integer;
begin
  Result := [Prompt];
  for Index in Indexes do
    Insert(NameOf(Pattern, Piece.Path[Index].EdgeKey), Result, Length(Result));
end;

// How many to cut, the fold, the darts' caps, the edges' own allowances and
// ends, the grainline, and the material and fill, as TPieceSection
procedure AddPieceRows(var Builder: TRowBuilder; Pattern: TPattern; Piece: TPieceObject);
var
  Keys, Choices: TStringArray;
  Index: integer;
  Darts: TDartRowArray;
  Indexes: TPathIndexArray;
begin
  Builder.AddNumber(PROPERTY_ROW_CUT, rsPropCut, Piece.CutCount, 1, MAX_CUT_COUNT, 1, 0);
  Builder.AddCheck(PROPERTY_ROW_MIRRORED, rsPropMirrored, '', Piece.Mirrored);
  Keys := FoldKeys(Pattern, Piece);
  Choices := [rsPropNoFold];
  for Index := 1 to High(Keys) do
    Insert(NameOf(Pattern, Keys[Index]), Choices, Length(Choices));
  Builder.AddChoice(PROPERTY_ROW_FOLD, rsPropFold, Choices, Max(0, IndexOfText(Keys, Piece.FoldEdgeKey)));
  Darts := PieceDarts(Pattern, Piece);
  for Index := 0 to High(Darts) do
  begin
    Builder.AddChoice(PROPERTY_ROW_DART + IntToStr(Index), Format(rsPropDartCap, [Darts[Index].Caption]),
      DartCapChoices(Pattern, Darts[Index].Legs), Ord(DartPress(Piece, Darts[Index].Legs)));
    Builder.Last^.Hint := rsPropDartCapHint;
  end;
  Indexes := EdgesWithoutOwnAllowance(Piece);
  Builder.AddChoice(PROPERTY_ROW_OWN_ALLOWANCE, rsPropOwnAllowance, EdgeChoices(Pattern, Piece, rsPropOwnAllowancePrompt,
    Indexes), 0);
  Builder.Last^.Hint := rsPropOwnAllowanceHint;
  Builder.Last^.Enabled := Length(Indexes) > 0;
  Indexes := EdgesWithEnds(Piece, aePlain);
  Builder.AddChoice(PROPERTY_ROW_MIRROR_ENDS, rsPropMirrorEnds, EdgeChoices(Pattern, Piece, rsPropMirrorEndsPrompt,
    Indexes), 0);
  Builder.Last^.Hint := rsPropMirrorEndsHint;
  Builder.Last^.Enabled := Length(Indexes) > 0;
  for Index in EdgesWithEnds(Piece, aeMirror) do
  begin
    // In the order of TAllowanceEnd
    Builder.AddChoice(PROPERTY_ROW_EDGE_ENDS + IntToStr(Index), Format(rsPropEndsOf,
      [NameOf(Pattern, Piece.Path[Index].EdgeKey)]), [rsPropEndsPlain, rsPropEndsMirrored], Ord(aeMirror));
    Builder.Last^.Hint := rsPropMirrorEndsHint;
  end;
  // In the order of TGrainKind
  Builder.AddChoice(PROPERTY_ROW_GRAIN, rsPropGrainline, [rsPropGrainNone, rsPropGrainAngle, rsPropGrainPoints],
    Ord(Piece.GrainKind));
  for Index := 0 to Piece.FieldCount - 1 do
    if Piece.Fields[Index].Name = GRAIN_ANGLE_FIELD then
      Builder.Add(GRAIN_ANGLE_FIELD, prkFormula, FieldCaption(GRAIN_ANGLE_FIELD), Pattern.FormulaText(Piece,
        GRAIN_ANGLE_FIELD));
  Keys := GrainPointKeys(Pattern);
  Choices := GrainPointChoices(Pattern);
  if Piece.GrainKind = gkPoints then
  begin
    Builder.AddChoice(PROPERTY_ROW_GRAIN_FROM, rsPropGrainFrom, Choices, Max(0, IndexOfText(Keys, Piece.GrainStartKey)));
    Builder.AddChoice(PROPERTY_ROW_GRAIN_TO, rsPropGrainTo, Choices, Max(0, IndexOfText(Keys, Piece.GrainEndKey)));
  end
  else
  begin
    Builder.AddChoice(PROPERTY_ROW_GRAIN_FROM, rsPropGrainFrom, Choices, 0);
    Builder.Last^.Enabled := False;
    Builder.AddChoice(PROPERTY_ROW_GRAIN_TO, rsPropGrainTo, Choices, 0);
    Builder.Last^.Enabled := False;
  end;
  Choices := nil;
  for Index := 0 to Pattern.MaterialCount - 1 do
    Insert(Pattern.Materials[Index].Name, Choices, Length(Choices));
  Insert(rsPropNoMaterial, Choices, Length(Choices));
  Builder.AddChoice(PROPERTY_ROW_MATERIAL, rsPropMaterial, Choices, Pattern.MaterialCount);
  for Index := 0 to Pattern.MaterialCount - 1 do
    if Pattern.MaterialOf(Piece) = Pattern.Materials[Index] then
      Builder.Last^.Choice := Index;
  // In the order of TPieceFillStyle
  Builder.AddChoice(PROPERTY_ROW_FILL, rsPropFillStyle, [rsPropFromMaterial, rsPropFillTint, rsPropFillHatch],
    Ord(Piece.FillStyle));
  Builder.Add(PROPERTY_ROW_FILL_COLOR, prkColor, rsPropFillColor, Piece.FillColor);
  Builder.Last^.Choices := [rsPropFromMaterial, rsPropOwnColor];
  Builder.Last^.Color := PieceDrawnColor(Pattern, Piece);
end;

// A note's text goes under its name; its size, printing, look and what it hangs from after the fields
procedure AddNoteRows(var Builder: TRowBuilder; Pattern: TPattern; Note: TNoteObject; Place: TSectionPlace);
begin
  case Place of
    spName:
    begin
      Builder.Add(PROPERTY_ROW_NOTE_TEXT, prkLongText, rsPropNoteText, Note.DisplayText(Pattern.Resolver));
      Builder.Last^.Hint := rsPropNoteTextHint;
    end;
    spRows:
    begin
      Builder.AddNumber(PROPERTY_ROW_NOTE_SIZE, rsPropNoteSize, Note.Size, NOTE_SIZE_STEP, MAX_NOTE_SIZE,
        NOTE_SIZE_STEP, 1);
      Builder.AddCheck(PROPERTY_ROW_NOTE_PRINT, rsPropNotePrint, rsPropNotePrintCaption, Note.Print);
      // In the order of TTextAlign
      Builder.AddChoice(PROPERTY_ROW_NOTE_ALIGN, rsPropNoteAlign, [rsPropNoteAlignLeft, rsPropNoteAlignCentre,
        rsPropNoteAlignRight], Ord(Note.Align));
      Builder.AddCheck(PROPERTY_ROW_NOTE_BOX, rsPropNoteBox, rsPropNoteBoxCaption, Note.Boxed);
      Builder.Add(PROPERTY_ROW_NOTE_FONT, prkFont, rsPropNoteFont, Note.Style.Font);
      Builder.Last^.Choices := [rsPropFontDefault];
      Builder.Last^.Hint := rsPropFontHint;
      Builder.AddCheck(PROPERTY_ROW_NOTE_BOLD, rsPropNoteStyle, rsPropNoteBold, Note.Style.Bold);
      Builder.AddCheck(PROPERTY_ROW_NOTE_ITALIC, '', rsPropNoteItalic, Note.Style.Italic);
      // A free note has nothing to point at; in the order of TNoteLeader
      if Note.Anchor <> naFree then
        Builder.AddChoice(PROPERTY_ROW_NOTE_LEADER, rsPropNoteLeader, [rsPropNoteLeaderNone, rsPropNoteLeaderArrow,
          rsPropNoteLeaderDot, rsPropNoteLeaderLine], Ord(Note.Leader));
      Builder.Add(PROPERTY_ROW_NOTE_ANCHOR, prkText, rsPropNoteAnchor, NoteAnchorText(Pattern, Note));
      if Note.Anchor <> naFree then
      begin
        Builder.Add(PROPERTY_ROW_NOTE_FREE, prkButton, '', rsPropNoteFree);
        Builder.Last^.Hint := rsPropNoteFreeHint;
      end;
    end;
  end;
end;

function PropertyRows(Pattern: TPattern; Node: TEvalNode): TPropertyRowArray;
var
  Builder: TRowBuilder;
  Place: TSectionPlace;
begin
  Builder := Default(TRowBuilder);
  for Place := Low(TSectionPlace) to High(TSectionPlace) do
  begin
    AddCommonRows(Builder, Pattern, Node, Place);
    if Node is TEdgeObject then
      AddEdgeRows(Builder, Pattern, TEdgeObject(Node), Place);
    if HasMarkerRows(Node) and (Place = spRows) then
      AddMarkerRows(Builder, Pattern, TDraftObject(Node));
    if (Node is TRepeatObject) and (Place = spRows) then
      AddRepeatRows(Builder, Pattern, TRepeatObject(Node));
    if (Node is TPieceObject) and (Place = spRows) then
      AddPieceRows(Builder, Pattern, TPieceObject(Node));
    if Node is TSeamObject then
      AddSeamRows(Builder, Pattern, TSeamObject(Node), Place);
    if Node is TNoteObject then
      AddNoteRows(Builder, Pattern, TNoteObject(Node), Place);
  end;
  Result := Builder.Rows;
end;

function PropertyFieldText(Pattern: TPattern; Node: TEvalNode; const FieldName: string): string;
begin
  if FieldName = '' then
    Result := Node.DisplayName
  else
    Result := Pattern.FormulaText(Node, FieldName);
end;

// Commits the change begun; False when Done is not, with the pattern's
// reason, or when a lock refused the change
function FinishStep(Document: TPatternDocument; Done: boolean; var Reason: string; const MergeKey: string = ''): boolean;
begin
  if not Done and (Reason = '') then
    Reason := Document.Pattern.LastError;
  Document.Commit(Done, MergeKey);
  Result := Done and not Document.ChangeRefused;
  if Done and not Result then
    Reason := Document.Pattern.LastError;
end;

// False with Reason when the object is not of the kind the row is for
function Refuse(out Reason: string): boolean;
begin
  Reason := rsPropNoSuchRow;
  Result := False;
end;

function CommitPropertyField(Document: TPatternDocument; Node: TEvalNode; const FieldName, Text: string;
  out Reason: string; out ErrorPos: integer): boolean;
var
  Pattern: TPattern;
begin
  Reason := '';
  ErrorPos := 0;
  Pattern := Document.Pattern;
  if Text = PropertyFieldText(Pattern, Node, FieldName) then
    Exit(True);
  // Emptying an edge's own allowance goes back to the piece's
  if (Node is TPieceObject) and (Trim(Text) = '') and (TPieceObject(Node).OverridePathIndex(FieldName) >= 0) then
    Exit(SetOwnAllowanceStep(Document, Node, TPieceObject(Node).OverridePathIndex(FieldName), False, Reason));
  if FieldName = '' then
  begin
    Document.BeginChange(rsPropRename);
    Result := Pattern.Rename(Node, Text);
  end
  else
  begin
    Document.BeginChange(FieldEditName(FieldName));
    Result := Pattern.SetFormula(Node, FieldName, Text);
  end;
  if not Result then
    ErrorPos := Pattern.LastErrorPos;
  Result := FinishStep(Document, Result, Reason);
end;

function SetLockedStep(Document: TPatternDocument; Node: TEvalNode; Lock: boolean; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TDraftObject) then
    Exit(Refuse(Reason));
  if Document.Pattern.IsLocked(Node) = Lock then
    Exit(True);
  if Lock then
    Document.BeginChange(rsPropLock)
  else
    Document.BeginChange(rsPropUnlock);
  Result := FinishStep(Document, Document.Pattern.SetLocked(Node, Lock), Reason);
end;

function ConvertEdgeStep(Document: TPatternDocument; Node: TEvalNode; Choice: integer; out Reason: string): boolean;
var
  Pattern: TPattern;
  Choices: TStringArray;
  Done: boolean;
begin
  Reason := '';
  if not CanChangeType(Node) then
    Exit(Refuse(Reason));
  Choices := EdgeTypeChoices(Node);
  if (Choice < 0) or (Choice > High(Choices)) then
  begin
    Reason := rsPropNoChoice;
    Exit(False);
  end;
  if Choices[Choice] = TypeCaption(Node) then
    Exit(True);
  Pattern := Document.Pattern;
  Document.BeginChange(rsPropChangeType);
  if Choices[Choice] = rsTypeLine then
    Done := Assigned(Pattern.ConvertToLine(TEdgeObject(Node)))
  else
    Done := Assigned(Pattern.ConvertToCurve(TEdgeObject(Node)));
  Result := FinishStep(Document, Done, Reason);
end;

function SetEdgeRoleStep(Document: TPatternDocument; Node: TEvalNode; Role: TEdgeRole; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TEdgeObject) then
    Exit(Refuse(Reason));
  if TEdgeObject(Node).Role = Role then
    Exit(True);
  Document.BeginChange(rsPropChangeRole);
  Result := FinishStep(Document, Document.Pattern.SetEdgeRole(TEdgeObject(Node), Role), Reason);
end;

function SetMarkerStep(Document: TPatternDocument; Node: TEvalNode; Marker: TPointMarker; out Reason: string): boolean;
begin
  Reason := '';
  if not HasMarkerRows(Node) then
    Exit(Refuse(Reason));
  if TDraftObject(Node).Marker = Marker then
    Exit(True);
  Document.BeginChange(rsPropChangeMarker);
  Result := FinishStep(Document, Document.Pattern.SetMarker(Node.Key, Marker), Reason);
end;

function SetRepeatEndsStep(Document: TPatternDocument; Node: TEvalNode; Include: boolean; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TRepeatObject) then
    Exit(Refuse(Reason));
  if TRepeatObject(Node).IncludeEnds = Include then
    Exit(True);
  Document.BeginChange(rsPropChangeEnds);
  TRepeatObject(Node).IncludeEnds := Include;
  Result := FinishStep(Document, True, Reason);
end;

function FlipSeamStep(Document: TPatternDocument; Node: TEvalNode; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TSeamObject) then
    Exit(Refuse(Reason));
  Document.BeginChange(rsPropFlipSeam);
  TSeamObject(Node).Reversed := not TSeamObject(Node).Reversed;
  Result := FinishStep(Document, True, Reason);
end;

// A choice's index outside the choices
function BadChoice(Value, Count: integer; out Reason: string): boolean;
begin
  Result := (Value < 0) or (Value >= Count);
  if Result then
    Reason := rsPropNoChoice
  else
    Reason := '';
end;

function SetCutStep(Document: TPatternDocument; Node: TEvalNode; Count: integer; Mirrored: boolean; out Reason: string;
  const MergeKey: string): boolean;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  if (TPieceObject(Node).CutCount = Count) and (TPieceObject(Node).Mirrored = Mirrored) then
    Exit(True);
  Document.BeginChange(rsPropChangeCut);
  Result := FinishStep(Document, Document.Pattern.SetCut(TPieceObject(Node), Count, Mirrored), Reason, MergeKey);
end;

function SetFoldStep(Document: TPatternDocument; Node: TEvalNode; const EdgeKey: string; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  if TPieceObject(Node).FoldEdgeKey = EdgeKey then
    Exit(True);
  Document.BeginChange(rsPropChangeFold);
  Result := FinishStep(Document, Document.Pattern.SetFoldEdge(TPieceObject(Node), EdgeKey), Reason);
end;

function SetDartCapStep(Document: TPatternDocument; Node: TEvalNode; const Legs: TPieceDart; Press: TDartPress;
  out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  if DartPress(TPieceObject(Node), Legs) = Press then
    Exit(True);
  Document.BeginChange(rsPropChangeDartCap);
  Result := FinishStep(Document, Document.Pattern.SetDartCap(TPieceObject(Node), Legs.FirstKey, Legs.SecondKey, Press),
    Reason);
end;

function SetOwnAllowanceStep(Document: TPatternDocument; Node: TEvalNode; PathIndex: integer; Own: boolean;
  out Reason: string): boolean;
var
  Piece: TPieceObject;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  Piece := TPieceObject(Node);
  if (PathIndex < 0) or (PathIndex > High(Piece.Path)) then
  begin
    Reason := rsPropNoEdge;
    Exit(False);
  end;
  if Piece.HasOverride(PathIndex) = Own then
    Exit(True);
  if Own then
  begin
    Document.BeginChange(rsPropAddEdgeAllowance);
    Result := Document.Pattern.SetEdgeAllowance(Piece, PathIndex, Document.Pattern.FormulaText(Piece,
      PIECE_ALLOWANCE_FIELD));
  end
  else
  begin
    Document.BeginChange(rsPropRemoveEdgeAllowance);
    Result := Document.Pattern.SetEdgeAllowance(Piece, PathIndex, '');
  end;
  Result := FinishStep(Document, Result, Reason);
end;

function SetAllowanceEndStep(Document: TPatternDocument; Node: TEvalNode; PathIndex: integer; Value: TAllowanceEnd;
  out Reason: string): boolean;
var
  Piece: TPieceObject;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  Piece := TPieceObject(Node);
  if (PathIndex < 0) or (PathIndex > High(Piece.Path)) then
  begin
    Reason := rsPropNoEdge;
    Exit(False);
  end;
  if Piece.Path[PathIndex].AllowanceEnd = Value then
    Exit(True);
  Document.BeginChange(rsPropChangeAllowanceEnd);
  Result := FinishStep(Document, Document.Pattern.SetAllowanceEnd(Piece, PathIndex, Value), Reason);
end;

function SetGrainStep(Document: TPatternDocument; Node: TEvalNode; Kind: TGrainKind; const StartKey, EndKey: string;
  out Reason: string): boolean;
var
  Piece: TPieceObject;
  Pattern: TPattern;
  Done: boolean;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  Piece := TPieceObject(Node);
  Pattern := Document.Pattern;
  if (Piece.GrainKind = Kind) and ((Kind <> gkPoints) or ((Piece.GrainStartKey = StartKey) and
    (Piece.GrainEndKey = EndKey))) then
    Exit(True);
  if (Kind = gkPoints) and ((StartKey = '') or (EndKey = '')) then
  begin
    Reason := rsPropGrainBothPoints;
    Exit(False);
  end;
  Document.BeginChange(rsPropChangeGrainline);
  case Kind of
    gkNone:
    begin
      Pattern.ClearGrain(Piece);
      Done := True;
    end;
    gkAngle:
      Done := Pattern.SetGrainAngle(Piece, DEFAULT_GRAIN_ANGLE);
    else
      Done := Pattern.SetGrainPoints(Piece, StartKey, EndKey);
  end;
  Result := FinishStep(Document, Done, Reason);
end;

function SetPieceMaterialStep(Document: TPatternDocument; Node: TEvalNode; MaterialIndex: integer;
  out Reason: string): boolean;
var
  Pattern: TPattern;
  Material: TPatternMaterial;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  Pattern := Document.Pattern;
  if MaterialIndex >= Pattern.MaterialCount then
  begin
    Reason := rsPropNoChoice;
    Exit(False);
  end;
  Material := nil;
  if MaterialIndex >= 0 then
    Material := Pattern.Materials[MaterialIndex];
  if Pattern.MaterialOf(TPieceObject(Node)) = Material then
    Exit(True);
  Document.BeginChange(rsPropChangeMaterial);
  Pattern.SetPieceMaterial(TPieceObject(Node), Material);
  Result := FinishStep(Document, True, Reason);
end;

function SetPieceFillStep(Document: TPatternDocument; Node: TEvalNode; const AColor: string; Style: TPieceFillStyle;
  out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TPieceObject) then
    Exit(Refuse(Reason));
  if SameText(TPieceObject(Node).FillColor, AColor) and (TPieceObject(Node).FillStyle = Style) then
    Exit(True);
  Document.BeginChange(rsPropChangeFill);
  Result := FinishStep(Document, Document.Pattern.SetPieceFill(TPieceObject(Node), AColor, Style), Reason);
end;

function SetNoteTextStep(Document: TPatternDocument; Node: TEvalNode; const FieldText: string;
  out Reason: string): boolean;
var
  NewText: string;
begin
  Reason := '';
  if not (Node is TNoteObject) then
    Exit(Refuse(Reason));
  NewText := NoteTextFromField(FieldText);
  if NewText = TNoteObject(Node).DisplayText(Document.Pattern.Resolver) then
    Exit(True);
  Document.BeginChange(rsPropChangeNoteText);
  Result := FinishStep(Document, Document.Pattern.SetNoteText(TNoteObject(Node), NewText), Reason);
end;

function SetNoteSizeStep(Document: TPatternDocument; Node: TEvalNode; Size: double; out Reason: string;
  const MergeKey: string): boolean;
begin
  Reason := '';
  if not (Node is TNoteObject) then
    Exit(Refuse(Reason));
  if SameValue(TNoteObject(Node).Size, Size) then
    Exit(True);
  Document.BeginChange(rsPropChangeNoteSize);
  Result := FinishStep(Document, Document.Pattern.SetNoteSize(TNoteObject(Node), Size), Reason, MergeKey);
end;

function SetNotePrintStep(Document: TPatternDocument; Node: TEvalNode; Print: boolean; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TNoteObject) then
    Exit(Refuse(Reason));
  if TNoteObject(Node).Print = Print then
    Exit(True);
  Document.BeginChange(rsPropChangeNotePrint);
  Document.Pattern.SetNotePrint(TNoteObject(Node), Print);
  Result := FinishStep(Document, True, Reason);
end;

function SetNoteLookStep(Document: TPatternDocument; Node: TEvalNode; Leader: TNoteLeader; Align: TTextAlign;
  Boxed, Bold, Italic: boolean; out Reason: string): boolean;
var
  Note: TNoteObject;
  Pattern: TPattern;
  Style: TTextStyle;
  Done: boolean;
begin
  Reason := '';
  if not (Node is TNoteObject) then
    Exit(Refuse(Reason));
  Note := TNoteObject(Node);
  Pattern := Document.Pattern;
  Style := Note.Style;
  Style.Bold := Bold;
  Style.Italic := Italic;
  if (Leader = Note.Leader) and (Align = Note.Align) and (Boxed = Note.Boxed) and SameTextStyle(Style, Note.Style) then
    Exit(True);
  Document.BeginChange(rsPropChangeNoteLook);
  Pattern.SetNoteAlign(Note, Align);
  Pattern.SetNoteBoxed(Note, Boxed);
  Done := Pattern.SetNoteStyle(Note, Style) and Pattern.SetNoteLeader(Note, Leader);
  Result := FinishStep(Document, Done, Reason);
end;

function SetNoteFontStep(Document: TPatternDocument; Node: TEvalNode; const FontName: string;
  out Reason: string): boolean;
var
  Style: TTextStyle;
begin
  Reason := '';
  if not (Node is TNoteObject) then
    Exit(Refuse(Reason));
  Style := TNoteObject(Node).Style;
  if Style.Font = FontName then
    Exit(True);
  Style.Font := FontName;
  Document.BeginChange(rsPropChangeNoteFont);
  Result := FinishStep(Document, Document.Pattern.SetNoteStyle(TNoteObject(Node), Style), Reason);
end;

function MakeNoteFreeStep(Document: TPatternDocument; Node: TEvalNode; out Reason: string): boolean;
begin
  Reason := '';
  if not (Node is TNoteObject) then
    Exit(Refuse(Reason));
  if TNoteObject(Node).Anchor = naFree then
    Exit(True);
  Document.BeginChange(rsPropFreeNote);
  Result := FinishStep(Document, Document.Pattern.MakeNoteFree(TNoteObject(Node)), Reason);
end;

// The number after a row's prefix, as dart2 or edgeEnds3, or -1
function RowNumber(const RowId, Prefix: string): integer;
begin
  Result := -1;
  if (Length(RowId) > Length(Prefix)) and (Copy(RowId, 1, Length(Prefix)) = Prefix) then
    Result := StrToIntDef(Copy(RowId, Length(Prefix) + 1, MaxInt), -1);
end;

function CommitPieceRow(Document: TPatternDocument; Piece: TPieceObject; const RowId: string; Value: integer;
  out Reason: string): boolean;
var
  Pattern: TPattern;
  Keys: TStringArray;
  Darts: TDartRowArray;
  Indexes: TPathIndexArray;
  Number: integer;
begin
  Reason := '';
  Result := False;
  Pattern := Document.Pattern;
  if RowId = PROPERTY_ROW_MIRRORED then
    Exit(SetCutStep(Document, Piece, Piece.CutCount, Value <> 0, Reason));
  if RowId = PROPERTY_ROW_FOLD then
  begin
    Keys := FoldKeys(Pattern, Piece);
    if not BadChoice(Value, Length(Keys), Reason) then
      Result := SetFoldStep(Document, Piece, Keys[Value], Reason);
    Exit;
  end;
  // The prompts choose an edge, after themselves; choosing the prompt does nothing
  if (RowId = PROPERTY_ROW_OWN_ALLOWANCE) or (RowId = PROPERTY_ROW_MIRROR_ENDS) then
  begin
    if RowId = PROPERTY_ROW_OWN_ALLOWANCE then
      Indexes := EdgesWithoutOwnAllowance(Piece)
    else
      Indexes := EdgesWithEnds(Piece, aePlain);
    if BadChoice(Value, Length(Indexes) + 1, Reason) then
      Exit(False);
    if Value = 0 then
      Exit(True);
    if RowId = PROPERTY_ROW_OWN_ALLOWANCE then
      Exit(SetOwnAllowanceStep(Document, Piece, Indexes[Value - 1], True, Reason));
    Exit(SetAllowanceEndStep(Document, Piece, Indexes[Value - 1], aeMirror, Reason));
  end;
  if RowId = PROPERTY_ROW_GRAIN then
  begin
    if BadChoice(Value, Ord(High(TGrainKind)) + 1, Reason) then
      Exit(False);
    Exit(SetGrainStep(Document, Piece, TGrainKind(Value), Piece.GrainStartKey, Piece.GrainEndKey, Reason));
  end;
  if (RowId = PROPERTY_ROW_GRAIN_FROM) or (RowId = PROPERTY_ROW_GRAIN_TO) then
  begin
    Keys := GrainPointKeys(Pattern);
    if BadChoice(Value, Length(Keys), Reason) then
      Exit(False);
    if RowId = PROPERTY_ROW_GRAIN_FROM then
      Exit(SetGrainStep(Document, Piece, gkPoints, Keys[Value], Piece.GrainEndKey, Reason));
    Exit(SetGrainStep(Document, Piece, gkPoints, Piece.GrainStartKey, Keys[Value], Reason));
  end;
  if RowId = PROPERTY_ROW_MATERIAL then
  begin
    if BadChoice(Value, Pattern.MaterialCount + 1, Reason) then
      Exit(False);
    if Value = Pattern.MaterialCount then
      Value := -1;
    Exit(SetPieceMaterialStep(Document, Piece, Value, Reason));
  end;
  if RowId = PROPERTY_ROW_FILL then
  begin
    if BadChoice(Value, Ord(High(TPieceFillStyle)) + 1, Reason) then
      Exit(False);
    Exit(SetPieceFillStep(Document, Piece, Piece.FillColor, TPieceFillStyle(Value), Reason));
  end;
  Number := RowNumber(RowId, PROPERTY_ROW_DART);
  if Number >= 0 then
  begin
    Darts := PieceDarts(Pattern, Piece);
    if Number > High(Darts) then
      Reason := rsPropNoDart
    else if not BadChoice(Value, Ord(High(TDartPress)) + 1, Reason) then
      Result := SetDartCapStep(Document, Piece, Darts[Number].Legs, TDartPress(Value), Reason);
    Exit;
  end;
  Number := RowNumber(RowId, PROPERTY_ROW_EDGE_ENDS);
  if Number >= 0 then
  begin
    if not BadChoice(Value, Ord(High(TAllowanceEnd)) + 1, Reason) then
      Result := SetAllowanceEndStep(Document, Piece, Number, TAllowanceEnd(Value), Reason);
    Exit;
  end;
  Reason := rsPropNoSuchRow;
end;

function CommitNoteRow(Document: TPatternDocument; Note: TNoteObject; const RowId: string; Value: integer;
  out Reason: string): boolean;
var
  Leader: TNoteLeader;
  Align: TTextAlign;
  Boxed, Bold, Italic: boolean;
begin
  Reason := '';
  if RowId = PROPERTY_ROW_NOTE_PRINT then
    Exit(SetNotePrintStep(Document, Note, Value <> 0, Reason));
  if RowId = PROPERTY_ROW_NOTE_FREE then
    Exit(MakeNoteFreeStep(Document, Note, Reason));
  Leader := Note.Leader;
  Align := Note.Align;
  Boxed := Note.Boxed;
  Bold := Note.Style.Bold;
  Italic := Note.Style.Italic;
  if RowId = PROPERTY_ROW_NOTE_LEADER then
  begin
    if BadChoice(Value, Ord(High(TNoteLeader)) + 1, Reason) then
      Exit(False);
    Leader := TNoteLeader(Value);
  end
  else if RowId = PROPERTY_ROW_NOTE_ALIGN then
  begin
    if BadChoice(Value, Ord(High(TTextAlign)) + 1, Reason) then
      Exit(False);
    Align := TTextAlign(Value);
  end
  else if RowId = PROPERTY_ROW_NOTE_BOX then
    Boxed := Value <> 0
  else if RowId = PROPERTY_ROW_NOTE_BOLD then
    Bold := Value <> 0
  else if RowId = PROPERTY_ROW_NOTE_ITALIC then
    Italic := Value <> 0
  else
  begin
    Reason := rsPropNoSuchRow;
    Exit(False);
  end;
  Result := SetNoteLookStep(Document, Note, Leader, Align, Boxed, Bold, Italic, Reason);
end;

function CommitGrainPoints(Document: TPatternDocument; Node: TEvalNode; FromChoice, ToChoice: integer;
  out Reason: string): boolean;
var
  Keys: TStringArray;
begin
  Reason := '';
  if not Assigned(Node) then
  begin
    Reason := rsPropGone;
    Exit(False);
  end;
  Keys := GrainPointKeys(Document.Pattern);
  if BadChoice(FromChoice, Length(Keys), Reason) or BadChoice(ToChoice, Length(Keys), Reason) then
    Exit(False);
  Result := SetGrainStep(Document, Node, gkPoints, Keys[FromChoice], Keys[ToChoice], Reason);
end;

function CommitPropertyNumber(Document: TPatternDocument; Node: TEvalNode; const RowId: string; Value: double;
  out Reason: string): boolean;
begin
  Reason := '';
  Result := False;
  if not Assigned(Node) then
    Reason := rsPropGone
  else if (RowId = PROPERTY_ROW_CUT) and (Node is TPieceObject) then
  begin
    if (Value < 1) or (Value > MAX_CUT_COUNT) or (Frac(Value) <> 0) then
      Reason := rsPropBadNumber
    else
      Result := SetCutStep(Document, Node, Round(Value), TPieceObject(Node).Mirrored, Reason, 'cut:' + Node.Key);
  end
  else if (RowId = PROPERTY_ROW_NOTE_SIZE) and (Node is TNoteObject) then
    Result := SetNoteSizeStep(Document, Node, Value, Reason, 'notesize:' + Node.Key)
  else
    Reason := rsPropNoSuchRow;
end;

function CommitPropertyText(Document: TPatternDocument; Node: TEvalNode; const RowId, Text: string;
  out Reason: string): boolean;
begin
  Reason := '';
  Result := False;
  if not Assigned(Node) then
    Reason := rsPropGone
  else if RowId = PROPERTY_ROW_NOTE_TEXT then
    Result := SetNoteTextStep(Document, Node, Text, Reason)
  else if RowId = PROPERTY_ROW_NOTE_FONT then
  begin
    if Trim(Text) = rsPropFontDefault then
      Result := SetNoteFontStep(Document, Node, '', Reason)
    else
      Result := SetNoteFontStep(Document, Node, Trim(Text), Reason);
  end
  else if (RowId = PROPERTY_ROW_FILL_COLOR) and (Node is TPieceObject) then
    Result := SetPieceFillStep(Document, Node, Trim(Text), TPieceObject(Node).FillStyle, Reason)
  else
    Reason := rsPropNoSuchRow;
end;

function CommitPropertyRow(Document: TPatternDocument; Node: TEvalNode; const RowId: string; Value: integer;
  out Reason: string): boolean;
begin
  Reason := '';
  Result := False;
  if not Assigned(Node) then
    Reason := rsPropGone
  else if RowId = PROPERTY_ROW_LOCKED then
    Result := SetLockedStep(Document, Node, Value <> 0, Reason)
  else if RowId = PROPERTY_ROW_TYPE then
    Result := ConvertEdgeStep(Document, Node, Value, Reason)
  else if RowId = PROPERTY_ROW_ROLE then
  begin
    if not BadChoice(Value, Ord(High(TEdgeRole)) + 1, Reason) then
      Result := SetEdgeRoleStep(Document, Node, TEdgeRole(Value), Reason);
  end
  else if RowId = PROPERTY_ROW_MARKER then
  begin
    if not BadChoice(Value, Ord(High(TPointMarker)) + 1, Reason) then
      Result := SetMarkerStep(Document, Node, TPointMarker(Value), Reason);
  end
  else if RowId = PROPERTY_ROW_ENDS then
  begin
    if not BadChoice(Value, Length(RepeatEndsChoices), Reason) then
      Result := SetRepeatEndsStep(Document, Node, Value = 0, Reason);
  end
  else if RowId = PROPERTY_ROW_FLIP then
    Result := FlipSeamStep(Document, Node, Reason)
  else if Node is TPieceObject then
    Result := CommitPieceRow(Document, TPieceObject(Node), RowId, Value, Reason)
  else if Node is TNoteObject then
    Result := CommitNoteRow(Document, TNoteObject(Node), RowId, Value, Reason)
  else
    Reason := rsPropNoSuchRow;
end;

end.
