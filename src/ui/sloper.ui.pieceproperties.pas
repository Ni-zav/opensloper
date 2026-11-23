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

// A piece's rows in the properties panel: how many to cut and whether
// mirrored, the fold, the cap of each dart, edges with their own seam
// allowance, the grainline, and the material and fill.
unit Sloper.UI.PieceProperties;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StdCtrls, Spin, Sloper.Core.Evaluator, Sloper.Core.Materials, Sloper.Core.Piece, Sloper.UI.Properties,
  Sloper.Editor.PropertyRows;

type
  TPieceSection = class(TPropertySection)
  private
    FCutEdit: TSpinEdit;
    FMirrorBox: TCheckBox;
    FFoldBox: TComboBox;
    // The edge of each fold choice; '' for none
    FFoldKeys: TStringArray;
    // A cap for each dart: none, or pressed towards its first or second leg,
    // in the order of TDartPress
    FDartBoxes: array of TComboBox;
    FDarts: TDartRowArray;
    // Adds an edge's own seam allowance: one choice per edge without one,
    // after the prompt, with the path index of each
    FAllowanceBox: TComboBox;
    FAllowanceIndexes: TPathIndexArray;
    // Mirrors an edge's allowance ends: one choice per edge without, after
    // the prompt, and a row for each edge with them, plain or mirrored, with
    // the path index of each
    FMirrorEndsBox: TComboBox;
    FMirrorIndexes: TPathIndexArray;
    FEndBoxes: array of TComboBox;
    FEndIndexes: array of integer;
    // The grainline's kind, in the order of TGrainKind, and its two points
    // when it runs between them: Choose..., then every point by name
    FGrainBox, FGrainStartBox, FGrainEndBox: TComboBox;
    FGrainPointKeys: TStringArray;
    // One choice per material, then none
    FMaterialBox: TComboBox;
    FFillStyleBox: TComboBox;
    // From the material, the piece's own colour if it has one, then choosing one
    FFillColorBox: TComboBox;
    procedure AddRows(Piece: TPieceObject);
    procedure AddGrainRows(Piece: TPieceObject);
    procedure AddDartRows(Piece: TPieceObject);
    procedure RefreshDartRows(Piece: TPieceObject);
    procedure DartChange(Sender: TObject);
    procedure RefreshGrainRows(Piece: TPieceObject);
    procedure RefreshMaterialRows(Piece: TPieceObject);
    procedure CutChange(Sender: TObject);
    procedure FoldChange(Sender: TObject);
    procedure AllowanceChange(Sender: TObject);
    // Added with the piece's allowance
    procedure AddEdgeAllowance(PathIndex: integer);
    procedure AddEndRows(Piece: TPieceObject);
    procedure MirrorChange(Sender: TObject);
    procedure EndChange(Sender: TObject);
    procedure ChangeAllowanceEnd(PathIndex: integer; Value: TAllowanceEnd);
    procedure GrainChange(Sender: TObject);
    procedure ChangeGrain(Kind: TGrainKind);
    procedure MaterialChange(Sender: TObject);
    procedure FillStyleChange(Sender: TObject);
    procedure FillColorChange(Sender: TObject);
    procedure ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
  public
    procedure Build(Node: TEvalNode; Place: TSectionPlace); override;
    procedure Refresh(Node: TEvalNode); override;
    function OwnsField(Node: TEvalNode; const FieldName: string): boolean; override;
    function FieldRowCaption(Node: TEvalNode; const FieldName: string): string; override;
    function TakesCommit(Node: TEvalNode; const FieldName, AText: string): boolean; override;
    procedure QueuedChangeDue(Change, Data: integer); override;
  end;

implementation

uses
  Sloper.Core.Pattern, Sloper.UI.MaterialGrid, Sloper.Editor.ObjectList, Sloper.Editor.PropertyText;

const
  // The changes that add or remove rows, so they are queued
  QUEUED_ADD_ALLOWANCE = 0;
  QUEUED_REMOVE_ALLOWANCE = 1;
  QUEUED_GRAIN = 2;
  QUEUED_MIRROR_ENDS = 3;
  QUEUED_PLAIN_ENDS = 4;

procedure TPieceSection.Build(Node: TEvalNode; Place: TSectionPlace);
begin
  if Place = spRows then
    AddRows(TPieceObject(Node));
end;

// Only straight edges can be a fold, so only those are offered
procedure TPieceSection.AddRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Index: integer;
  FoldNames, AllowanceNames: TStringArray;
begin
  Pattern := Panel.Document.Pattern;
  FCutEdit := TSpinEdit.Create(Panel);
  FCutEdit.MinValue := 1;
  FCutEdit.MaxValue := MAX_CUT_COUNT;
  FCutEdit.OnChange := @CutChange;
  Panel.AddRow(rsPropCut, FCutEdit);
  FMirrorBox := TCheckBox.Create(Panel);
  FMirrorBox.OnChange := @CutChange;
  Panel.AddRow(rsPropMirrored, FMirrorBox);
  FFoldKeys := FoldKeys(Pattern, Piece);
  FoldNames := [rsPropNoFold];
  for Index := 1 to High(FFoldKeys) do
    Insert(Pattern.FindNode(FFoldKeys[Index]).DisplayName, FoldNames, Length(FoldNames));
  FFoldBox := Panel.AddChoiceRow(rsPropFold, FoldNames, @FoldChange);
  AddDartRows(Piece);
  FAllowanceIndexes := EdgesWithoutOwnAllowance(Piece);
  AllowanceNames := [rsPropOwnAllowancePrompt];
  for Index in FAllowanceIndexes do
    Insert(Pattern.FindNode(Piece.Path[Index].EdgeKey).DisplayName, AllowanceNames, Length(AllowanceNames));
  FAllowanceBox := Panel.AddChoiceRow(rsPropOwnAllowance, AllowanceNames, @AllowanceChange);
  FAllowanceBox.Hint := rsPropOwnAllowanceHint;
  FAllowanceBox.ShowHint := True;
  FAllowanceBox.ItemIndex := 0;
  FAllowanceBox.Enabled := Length(FAllowanceIndexes) > 0;
  AddEndRows(Piece);
  AddGrainRows(Piece);
  FMaterialBox := Panel.AddChoiceRow(rsPropMaterial, [], @MaterialChange);
  // In the order of TPieceFillStyle
  FFillStyleBox := Panel.AddChoiceRow(rsPropFillStyle, [rsPropFromMaterial, rsPropFillTint, rsPropFillHatch], @FillStyleChange);
  FFillColorBox := Panel.AddChoiceRow(rsPropFillColor, [], @FillColorChange);
end;

// The grainline's angle goes under the grainline, not with the other fields
function TPieceSection.OwnsField(Node: TEvalNode; const FieldName: string): boolean;
begin
  Result := FieldName = GRAIN_ANGLE_FIELD;
end;

// An edge's own allowance is named after its edge, which its field is not
function TPieceSection.FieldRowCaption(Node: TEvalNode; const FieldName: string): string;
begin
  Result := EdgeAllowanceCaption(Panel.Document.Pattern, TPieceObject(Node), FieldName);
end;

// Emptying an edge's own allowance removes it, which takes its row away, so
// it waits until the edit's handler has returned
function TPieceSection.TakesCommit(Node: TEvalNode; const FieldName, AText: string): boolean;
var
  PathIndex: integer;
begin
  PathIndex := TPieceObject(Node).OverridePathIndex(FieldName);
  Result := (Trim(AText) = '') and (PathIndex >= 0);
  if Result then
    Panel.QueueChange(Self, QUEUED_REMOVE_ALLOWANCE, PathIndex);
end;

procedure TPieceSection.QueuedChangeDue(Change, Data: integer);
var
  Reason: string;
begin
  case Change of
    QUEUED_ADD_ALLOWANCE: AddEdgeAllowance(Data);
    QUEUED_REMOVE_ALLOWANCE:
    begin
      Panel.BeginStep;
      Panel.EndStep(SetOwnAllowanceStep(Panel.Document, Panel.SelectedNode, Data, False, Reason), Reason);
    end;
    QUEUED_GRAIN: ChangeGrain(TGrainKind(Data));
    QUEUED_MIRROR_ENDS: ChangeAllowanceEnd(Data, aeMirror);
    QUEUED_PLAIN_ENDS: ChangeAllowanceEnd(Data, aePlain);
  end;
end;

// The prompt for an edge to mirror, then a row for each edge that is
procedure TPieceSection.AddEndRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Index: integer;
  Names: TStringArray;
  Box: TComboBox;
begin
  Pattern := Panel.Document.Pattern;
  FEndBoxes := nil;
  FEndIndexes := nil;
  FMirrorIndexes := EdgesWithEnds(Piece, aePlain);
  Names := [rsPropMirrorEndsPrompt];
  for Index in FMirrorIndexes do
    Insert(Pattern.FindNode(Piece.Path[Index].EdgeKey).DisplayName, Names, Length(Names));
  FMirrorEndsBox := Panel.AddChoiceRow(rsPropMirrorEnds, Names, @MirrorChange);
  FMirrorEndsBox.Hint := rsPropMirrorEndsHint;
  FMirrorEndsBox.ShowHint := True;
  FMirrorEndsBox.ItemIndex := 0;
  FMirrorEndsBox.Enabled := Length(FMirrorIndexes) > 0;
  for Index in EdgesWithEnds(Piece, aeMirror) do
  begin
    // In the order of TAllowanceEnd
    Box := Panel.AddChoiceRow(Format(rsPropEndsOf, [Pattern.FindNode(Piece.Path[Index].EdgeKey).DisplayName]),
      [rsPropEndsPlain, rsPropEndsMirrored], @EndChange);
    Box.ItemIndex := Ord(aeMirror);
    Box.Tag := Length(FEndBoxes);
    Box.Hint := rsPropMirrorEndsHint;
    Box.ShowHint := True;
    Insert(Box, FEndBoxes, Length(FEndBoxes));
    Insert(Index, FEndIndexes, Length(FEndIndexes));
  end;
end;

// Mirroring adds a row, so the panel is built again after it
procedure TPieceSection.MirrorChange(Sender: TObject);
begin
  if FFilling or (FMirrorEndsBox.ItemIndex <= 0) then
    Exit;
  Panel.QueueChange(Self, QUEUED_MIRROR_ENDS, FMirrorIndexes[FMirrorEndsBox.ItemIndex - 1]);
end;

// Going back to plain takes the row away
procedure TPieceSection.EndChange(Sender: TObject);
begin
  if FFilling or (TComboBox(Sender).ItemIndex <> Ord(aePlain)) then
    Exit;
  Panel.QueueChange(Self, QUEUED_PLAIN_ENDS, FEndIndexes[TComboBox(Sender).Tag]);
end;

// The commit and the rebuild free this section, so only the panel is used
// after them
procedure TPieceSection.ChangeAllowanceEnd(PathIndex: integer; Value: TAllowanceEnd);
var
  APanel: TPropertiesPanel;
  Reason: string;
begin
  APanel := Panel;
  APanel.BeginStep;
  APanel.EndStep(SetAllowanceEndStep(APanel.Document, APanel.SelectedNode, PathIndex, Value, Reason), Reason);
  APanel.Rebuild;
end;

procedure TPieceSection.Refresh(Node: TEvalNode);
var
  Piece: TPieceObject;
  Index: integer;
begin
  Piece := TPieceObject(Node);
  // Each row fires its change event, when the others are not yet filled in
  FFilling := True;
  try
    FCutEdit.Value := Piece.CutCount;
    FMirrorBox.Checked := Piece.Mirrored;
    RefreshMaterialRows(Piece);
    RefreshGrainRows(Piece);
    RefreshDartRows(Piece);
  finally
    FFilling := False;
  end;
  for Index := 0 to High(FFoldKeys) do
    if FFoldKeys[Index] = Piece.FoldEdgeKey then
      FFoldBox.ItemIndex := Index;
end;

// The materials can change while the piece stays selected
procedure TPieceSection.RefreshMaterialRows(Piece: TPieceObject);
var
  Pattern: TPattern;
  Index: integer;
begin
  Pattern := Panel.Document.Pattern;
  FMaterialBox.Items.Clear;
  for Index := 0 to Pattern.MaterialCount - 1 do
    FMaterialBox.Items.Add(Pattern.Materials[Index].Name);
  FMaterialBox.Items.Add(rsPropNoMaterial);
  FMaterialBox.ItemIndex := Pattern.MaterialCount;
  for Index := 0 to Pattern.MaterialCount - 1 do
    if Pattern.MaterialOf(Piece) = Pattern.Materials[Index] then
      FMaterialBox.ItemIndex := Index;
  FFillStyleBox.ItemIndex := Ord(Piece.FillStyle);
  FFillColorBox.Items.Clear;
  FFillColorBox.Items.Add(rsPropFromMaterial);
  if Piece.FillColor <> '' then
    FFillColorBox.Items.Add(Piece.FillColor);
  FFillColorBox.Items.Add(rsPropChooseColor);
  FFillColorBox.ItemIndex := Ord(Piece.FillColor <> '');
end;

procedure TPieceSection.MaterialChange(Sender: TObject);
var
  Node: TEvalNode;
  MaterialIndex: integer;
  Reason: string;
begin
  Node := Panel.SelectedNode;
  if FFilling or not (Node is TPieceObject) or (FMaterialBox.ItemIndex < 0) then
    Exit;
  MaterialIndex := FMaterialBox.ItemIndex;
  if MaterialIndex >= Panel.Document.Pattern.MaterialCount then
    MaterialIndex := -1;
  Panel.BeginStep;
  Panel.EndStep(SetPieceMaterialStep(Panel.Document, Node, MaterialIndex, Reason), Reason);
  Refresh(Panel.SelectedNode);
end;

procedure TPieceSection.ChangePieceFill(const AColor: string; Style: TPieceFillStyle);
var
  Node: TEvalNode;
  Reason: string;
begin
  Node := Panel.SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Panel.BeginStep;
  Panel.EndStep(SetPieceFillStep(Panel.Document, Node, AColor, Style, Reason), Reason);
  Refresh(Panel.SelectedNode);
end;

procedure TPieceSection.FillStyleChange(Sender: TObject);
var
  Node: TEvalNode;
begin
  Node := Panel.SelectedNode;
  if FFilling or not (Node is TPieceObject) or (FFillStyleBox.ItemIndex < 0) then
    Exit;
  ChangePieceFill(TPieceObject(Node).FillColor, TPieceFillStyle(FFillStyleBox.ItemIndex));
end;

procedure TPieceSection.FillColorChange(Sender: TObject);
var
  Node: TEvalNode;
  Piece: TPieceObject;
  Chosen: string;
begin
  Node := Panel.SelectedNode;
  if FFilling or not (Node is TPieceObject) then
    Exit;
  Piece := TPieceObject(Node);
  if FFillColorBox.ItemIndex = 0 then
    ChangePieceFill('', Piece.FillStyle)
  else if FFillColorBox.ItemIndex = FFillColorBox.Items.Count - 1 then
  begin
    // Start on the colour it is drawn in: its own, else its material's
    Chosen := Piece.FillColor;
    if (Chosen = '') and Assigned(Panel.Document.Pattern.MaterialOf(Piece)) then
      Chosen := Panel.Document.Pattern.MaterialOf(Piece).Color;
    if Chosen = '' then
      Chosen := Panel.Document.Pattern.Materials[0].Color;
    if ChooseMaterialColor(Panel, Chosen) then
      ChangePieceFill(Chosen, Piece.FillStyle)
    else
      Refresh(Piece);
  end;
end;

// Runs of spin clicks merge into one undo step
procedure TPieceSection.CutChange(Sender: TObject);
var
  Node: TEvalNode;
  Reason: string;
begin
  if FFilling then
    Exit;
  Node := Panel.SelectedNode;
  if not (Node is TPieceObject) then
    Exit;
  Panel.BeginStep;
  Panel.EndStep(SetCutStep(Panel.Document, Node, FCutEdit.Value, FMirrorBox.Checked, Reason, 'cut:' + Node.Key), Reason);
end;

procedure TPieceSection.AddDartRows(Piece: TPieceObject);
var
  Index: integer;
  Box: TComboBox;
begin
  FDarts := PieceDarts(Panel.Document.Pattern, Piece);
  FDartBoxes := nil;
  for Index := 0 to High(FDarts) do
  begin
    Box := Panel.AddChoiceRow(Format(rsPropDartCap, [FDarts[Index].Caption]), DartCapChoices(Panel.Document.Pattern,
      FDarts[Index].Legs), @DartChange);
    Box.Tag := Index;
    Box.Hint := rsPropDartCapHint;
    Box.ShowHint := True;
    Insert(Box, FDartBoxes, Length(FDartBoxes));
  end;
end;

procedure TPieceSection.RefreshDartRows(Piece: TPieceObject);
var
  Index: integer;
begin
  for Index := 0 to High(FDartBoxes) do
    FDartBoxes[Index].ItemIndex := Ord(DartPress(Piece, FDarts[Index].Legs));
end;

procedure TPieceSection.DartChange(Sender: TObject);
var
  Reason: string;
begin
  if FFilling then
    Exit;
  Panel.BeginStep;
  Panel.EndStep(SetDartCapStep(Panel.Document, Panel.SelectedNode, FDarts[TComboBox(Sender).Tag].Legs,
    TDartPress(TComboBox(Sender).ItemIndex), Reason), Reason);
end;

procedure TPieceSection.FoldChange(Sender: TObject);
var
  Reason: string;
begin
  if FFoldBox.ItemIndex < 0 then
    Exit;
  Panel.BeginStep;
  Panel.EndStep(SetFoldStep(Panel.Document, Panel.SelectedNode, FFoldKeys[FFoldBox.ItemIndex], Reason), Reason);
end;

// Adding a field rebuilds the panel, box and all
procedure TPieceSection.AllowanceChange(Sender: TObject);
begin
  if FAllowanceBox.ItemIndex <= 0 then
    Exit;
  Panel.QueueChange(Self, QUEUED_ADD_ALLOWANCE, FAllowanceIndexes[FAllowanceBox.ItemIndex - 1]);
end;

// Starts at the piece's own allowance, with its row ready to type in. The
// commit rebuilds the panel, which frees this section, so only the panel is
// used after it.
procedure TPieceSection.AddEdgeAllowance(PathIndex: integer);
var
  APanel: TPropertiesPanel;
  Node: TEvalNode;
  Reason: string;
begin
  APanel := Panel;
  APanel.BeginStep;
  APanel.EndStep(SetOwnAllowanceStep(APanel.Document, APanel.SelectedNode, PathIndex, True, Reason), Reason);
  // The commit may have replaced the piece
  Node := APanel.SelectedNode;
  if Node is TPieceObject then
    APanel.FocusFormulaRow(TPieceObject(Node).OverrideField(PathIndex));
end;

procedure TPieceSection.AddGrainRows(Piece: TPieceObject);
var
  Index: integer;
  PointNames: TStringArray;
begin
  // In the order of TGrainKind
  FGrainBox := Panel.AddChoiceRow(rsPropGrainline, [rsPropGrainNone, rsPropGrainAngle, rsPropGrainPoints], @GrainChange);
  for Index := 0 to Piece.FieldCount - 1 do
    if Piece.Fields[Index].Name = GRAIN_ANGLE_FIELD then
      Panel.AddEditRow(FieldCaption(GRAIN_ANGLE_FIELD), frFormula, GRAIN_ANGLE_FIELD);
  FGrainPointKeys := GrainPointKeys(Panel.Document.Pattern);
  PointNames := GrainPointChoices(Panel.Document.Pattern);
  FGrainStartBox := Panel.AddChoiceRow(rsPropGrainFrom, PointNames, @GrainChange);
  FGrainEndBox := Panel.AddChoiceRow(rsPropGrainTo, PointNames, @GrainChange);
end;

procedure TPieceSection.RefreshGrainRows(Piece: TPieceObject);

  function PlaceOf(const Key: string): integer;
  begin
    for Result := 0 to High(FGrainPointKeys) do
      if (Key <> '') and (FGrainPointKeys[Result] = Key) then
        Exit;
    Result := 0;
  end;

begin
  FGrainBox.ItemIndex := Ord(Piece.GrainKind);
  if Piece.GrainKind = gkPoints then
  begin
    FGrainStartBox.ItemIndex := PlaceOf(Piece.GrainStartKey);
    FGrainEndBox.ItemIndex := PlaceOf(Piece.GrainEndKey);
  end
  else
  begin
    FGrainStartBox.ItemIndex := 0;
    FGrainEndBox.ItemIndex := 0;
  end;
  FGrainStartBox.Enabled := Piece.GrainKind = gkPoints;
  FGrainEndBox.Enabled := Piece.GrainKind = gkPoints;
end;

// Between two points takes effect once both are chosen. Changing the kind
// adds or removes the angle's row, so the change is queued.
procedure TPieceSection.GrainChange(Sender: TObject);
var
  Points: boolean;
begin
  if FFilling then
    Exit;
  Points := FGrainBox.ItemIndex = Ord(gkPoints);
  FGrainStartBox.Enabled := Points;
  FGrainEndBox.Enabled := Points;
  if Points and ((FGrainStartBox.ItemIndex <= 0) or (FGrainEndBox.ItemIndex <= 0)) then
    Exit;
  Panel.QueueChange(Self, QUEUED_GRAIN, FGrainBox.ItemIndex);
end;

// The commit may rebuild the panel, which frees this section, so only the
// panel is used after it
procedure TPieceSection.ChangeGrain(Kind: TGrainKind);
var
  APanel: TPropertiesPanel;
  Reason: string;
begin
  APanel := Panel;
  APanel.BeginStep;
  APanel.EndStep(SetGrainStep(APanel.Document, APanel.SelectedNode, Kind, FGrainPointKeys[FGrainStartBox.ItemIndex],
    FGrainPointKeys[FGrainEndBox.ItemIndex], Reason), Reason);
end;

end.
