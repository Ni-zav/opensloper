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
  SysUtils, Sloper.Core.Evaluator, Sloper.Core.Draft, Sloper.Core.Seam, Sloper.Core.Pattern,
  Sloper.Document.PatternDocument;

type
  // What a row holds: text to read, the object's name or a formula to edit, a
  // choice, a box to tick, a button, or the object's problem
  TPropertyRowKind = (prkText, prkName, prkFormula, prkChoice, prkCheck, prkButton, prkProblem);

  TPropertyRow = record
    // Which row it is, for an edit: one of the PROPERTY_ROW_ names, or a
    // formula's field name for a prkFormula row
    Id: string;
    Kind: TPropertyRowKind;
    Caption: string;
    // A prkFormula row's field
    Field: string;
    // What a text, name, formula or problem row shows, or a button's caption
    Text: string;
    // A choice row's items, in the order of the values they stand for, and the one chosen
    Choices: TStringArray;
    Choice: integer;
    Checked: boolean;
    Hint: string;
  end;
  TPropertyRowArray = array of TPropertyRow;

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
// Makes the edit of a row that is not a formula or name: Value is a choice's
// index, or 1 for a ticked box, and a button ignores it. False refuses, with Reason.
function CommitPropertyRow(Document: TPatternDocument; Node: TEvalNode; const RowId: string; Value: integer;
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

implementation

uses
  Sloper.Core.EvalTypes, Sloper.Core.Piece, Sloper.Core.Note, Sloper.Core.Transform, Sloper.Editor.ObjectList,
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
    if Node is TSeamObject then
      AddSeamRows(Builder, Pattern, TSeamObject(Node), Place);
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
function FinishStep(Document: TPatternDocument; Done: boolean; var Reason: string): boolean;
begin
  if not Done and (Reason = '') then
    Reason := Document.Pattern.LastError;
  Document.Commit(Done);
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
  else
    Reason := rsPropNoSuchRow;
end;

end.
