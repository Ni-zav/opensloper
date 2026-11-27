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

// Edits the user's profiles as a group. Layouts keep their profile names.
unit Sloper.Publish.ProfilesDialog;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Sloper.Core.MachineProfiles, Sloper.Core.OutputProfiles;

// True after Save writes the user profiles; False when the window is cancelled.
function EditUserProfiles(Owner: TComponent; out Machines: TMachineProfileArray; out Outputs: TOutputProfileArray): boolean;

implementation

uses
  SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ButtonPanel, Dialogs, Grids, CheckLst, Types,
  Sloper.Core.Settings, Sloper.Core.AppPaths, Sloper.Core.Draft, Sloper.Editor.PropertyText;

resourcestring
  rsProfilesTitle = 'Output and Machine Profiles';
  rsProfilesOutput = 'Output profiles';
  rsProfilesMachine = 'Machine profiles';
  rsProfilesAdd = 'Add...';
  rsProfilesRemove = 'Remove';
  rsProfilesName = 'Profile name';
  rsProfilesNameTaken = 'Choose a new, non-empty profile name';
  rsProfilesReservedName = 'That name belongs to a built-in profile';
  rsProfilesEmpty = 'Choose Add to create a profile';
  rsProfilesLine = 'Line';
  rsProfilesInclude = 'Include';
  rsProfilesColor = 'Colour';
  rsProfilesLayer = 'Layer';
  rsProfilesWidth = 'Width (mm)';
  rsProfilesDashes = 'Dash lengths (mm)';
  rsProfilesKeepAllowance = 'Keep seam allowance';
  rsProfilesMarks = 'Piece marks';
  rsProfilesSeamLine = 'Seam line';
  rsProfilesNotches = 'Notches';
  rsProfilesGrainline = 'Grainline';
  rsProfilesFold = 'Fold bracket';
  rsProfilesLabels = 'Labels';
  rsProfilesHoles = 'Holes';
  rsProfilesStitchHoles = 'Stitch holes';
  rsProfilesCut = 'Cut';
  rsProfilesScore = 'Score';
  rsProfilesMark = 'Mark';
  rsProfilesEngrave = 'Engrave';
  rsProfilesHole = 'Hole';
  rsProfilesBadLine = '%s: use a colour in #rrggbb form, a layer name, and a positive width';
  rsProfilesBadStyle = '%s: enter a #rrggbb colour and positive width, or leave both blank. Enter up to four positive dash lengths separated by spaces';
  rsProfilesHelp = 'Create a named profile to use in a layout. Leave the colour and width blank to use the default output line style';

const
  CHECKED_VALUE = '1';
  UNCHECKED_VALUE = '0';
  MARK_CAPTIONS: array[TPieceMark] of string = (rsProfilesSeamLine, rsProfilesNotches, rsProfilesGrainline, rsProfilesFold,
    rsProfilesLabels, rsProfilesHoles, rsProfilesStitchHoles);
  LINE_CAPTIONS: array[TLineType] of string = (rsProfilesCut, rsProfilesScore, rsProfilesMark, rsProfilesEngrave, rsProfilesHole);
  COL_INCLUDE = 1;
  COL_COLOR = 2;
  COL_LAYER_OR_DASH = 3;
  COL_WIDTH = 4;

type
  TProfileKind = (prOutput, prMachine);

  TProfilesDialog = class(TForm)
  private
    FKindBox, FProfileBox: TComboBox;
    FRemove, FAdd: TButton;
    FEmpty: TLabel;
    FMarksPanel: TPanel;
    FGrid: TStringGrid;
    FMarks: TCheckListBox;
    FAllowance: TCheckBox;
    FMachines: TMachineProfileArray;
    FOutputs: TOutputProfileArray;
    FKind: TProfileKind;
    FIndex: integer;
    FUpdating: boolean;
    procedure RefreshProfiles(Index: integer);
    procedure ShowProfile;
    function ReadProfile: boolean;
    function ReadMachine: boolean;
    function ReadOutput: boolean;
    procedure PickProfile(Sender: TObject);
    procedure AddProfile(Sender: TObject);
    procedure RemoveProfile(Sender: TObject);
    procedure SaveProfiles(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; Settings: TAppSettings);
  end;

function CheckedText(Checked: boolean): string;
begin
  if Checked then
    Result := CHECKED_VALUE
  else
    Result := UNCHECKED_VALUE;
end;

function DashText(const Values: TDashPattern): string;
var
  Value: double;
begin
  Result := '';
  for Value in Values do
    if Value > 0 then
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + FloatToStr(Value);
    end;
end;

constructor TProfilesDialog.CreateDialog(AOwner: TComponent; Settings: TAppSettings);
var
  TopBar: TPanel;
  Buttons: TButtonPanel;
  HintLabel, MarkLabel: TLabel;
  Column: TGridColumn;
  Mark: TPieceMark;

  function AddColumn(const ATitle: string; AWidth: integer): TGridColumn;
  begin
    Result := FGrid.Columns.Add;
    Result.Title.Caption := ATitle;
    Result.Width := Scale96ToForm(AWidth);
  end;

begin
  inherited CreateNew(AOwner);
  Caption := rsProfilesTitle;
  Position := poMainFormCenter;
  Width := Scale96ToForm(710);
  Height := Scale96ToForm(510);
  FMachines := Copy(Settings.MachineProfiles);
  FOutputs := Copy(Settings.OutputProfiles);
  FIndex := -1;

  Buttons := TButtonPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.ShowButtons := [pbOK, pbCancel];
  Buttons.OKButton.ModalResult := mrNone;
  Buttons.OKButton.OnClick := @SaveProfiles;

  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := Scale96ToForm(36);
  TopBar.BevelOuter := bvNone;
  TopBar.BorderSpacing.Around := Scale96ToForm(8);
  FKindBox := TComboBox.Create(Self);
  FKindBox.Parent := TopBar;
  FKindBox.Align := alLeft;
  FKindBox.Style := csDropDownList;
  FKindBox.Width := Scale96ToForm(155);
  FKindBox.Items.Add(rsProfilesOutput);
  FKindBox.Items.Add(rsProfilesMachine);
  FKindBox.ItemIndex := Ord(FKind);

  FRemove := TButton.Create(Self);
  FRemove.Parent := TopBar;
  FRemove.Align := alRight;
  FRemove.Caption := rsProfilesRemove;
  FRemove.OnClick := @RemoveProfile;
  FAdd := TButton.Create(Self);
  FAdd.Parent := TopBar;
  FAdd.Align := alRight;
  FAdd.Caption := rsProfilesAdd;
  FAdd.OnClick := @AddProfile;

  FProfileBox := TComboBox.Create(Self);
  FProfileBox.Parent := TopBar;
  FProfileBox.Align := alClient;
  FProfileBox.Style := csDropDownList;
  FKindBox.OnChange := @PickProfile;
  FProfileBox.OnChange := @PickProfile;

  HintLabel := TLabel.Create(Self);
  HintLabel.Parent := Self;
  HintLabel.Align := alTop;
  HintLabel.BorderSpacing.Around := Scale96ToForm(8);
  HintLabel.WordWrap := True;
  HintLabel.Caption := rsProfilesHelp;

  FMarksPanel := TPanel.Create(Self);
  FMarksPanel.Parent := Self;
  FMarksPanel.Align := alRight;
  FMarksPanel.Width := Scale96ToForm(145);
  FMarksPanel.BevelOuter := bvNone;
  FMarksPanel.BorderSpacing.Around := Scale96ToForm(8);
  MarkLabel := TLabel.Create(Self);
  MarkLabel.Parent := FMarksPanel;
  MarkLabel.Align := alTop;
  MarkLabel.Caption := rsProfilesMarks;
  FAllowance := TCheckBox.Create(Self);
  FAllowance.Parent := FMarksPanel;
  FAllowance.Align := alBottom;
  FAllowance.Caption := rsProfilesKeepAllowance;
  FMarks := TCheckListBox.Create(Self);
  FMarks.Parent := FMarksPanel;
  FMarks.Align := alClient;
  for Mark := Low(TPieceMark) to High(TPieceMark) do
    FMarks.Items.Add(MARK_CAPTIONS[Mark]);

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.BorderSpacing.Around := Scale96ToForm(8);
  FGrid.FixedCols := 0;
  FGrid.Options := FGrid.Options + [goEditing, goColSizing] - [goRangeSelect];
  AddColumn(rsProfilesLine, 100).ReadOnly := True;
  Column := AddColumn(rsProfilesInclude, 60);
  Column.ButtonStyle := cbsCheckboxColumn;
  Column.ValueChecked := CHECKED_VALUE;
  Column.ValueUnchecked := UNCHECKED_VALUE;
  AddColumn(rsProfilesColor, 85);
  AddColumn(rsProfilesDashes, 130);
  AddColumn(rsProfilesWidth, 90);
  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alTop;
  FEmpty.BorderSpacing.Around := Scale96ToForm(8);
  FEmpty.Caption := rsProfilesEmpty;
  RefreshProfiles(0);
end;

procedure TProfilesDialog.DoShow;
var
  Needed, MarksWidth, ColumnWidth, Index, PreferredWidth, PreferredHeight: integer;
  Mark: TPieceMark;
  Role: TEdgeRole;
  Kind: TLineType;
  Limit: TRect;
begin
  inherited DoShow;
  if Assigned(Monitor) then
    Limit := Monitor.WorkareaRect
  else
    Limit := Screen.WorkAreaRect;
  FGrid.Canvas.Font := FGrid.Font;
  Needed := Scale96ToForm(32);
  for Index := 0 to FGrid.Columns.Count - 1 do
  begin
    FGrid.Canvas.Font := FGrid.TitleFont;
    ColumnWidth := FGrid.Canvas.TextWidth(FGrid.Columns[Index].Title.Caption);
    if Index = COL_LAYER_OR_DASH then
      ColumnWidth := Max(ColumnWidth, FGrid.Canvas.TextWidth(rsProfilesDashes));
    if Index = 0 then
    begin
      FGrid.Canvas.Font := FGrid.Font;
      for Role := Low(TEdgeRole) to High(TEdgeRole) do
        if Role in MARKING_ROLES then
          ColumnWidth := Max(ColumnWidth, FGrid.Canvas.TextWidth(RoleCaption(Role)));
      for Kind := Low(TLineType) to High(TLineType) do
        ColumnWidth := Max(ColumnWidth, FGrid.Canvas.TextWidth(LINE_CAPTIONS[Kind]));
    end;
    FGrid.Columns[Index].Width := Max(FGrid.Columns[Index].Width, ColumnWidth + Scale96ToForm(24));
    Inc(Needed, FGrid.Columns[Index].Width);
  end;
  PreferredWidth := 0;
  PreferredHeight := 0;
  FAllowance.GetPreferredSize(PreferredWidth, PreferredHeight, True);
  FAllowance.Height := Max(FAllowance.Height, PreferredHeight);
  MarksWidth := Max(PreferredWidth, Canvas.TextWidth(rsProfilesKeepAllowance) + Scale96ToForm(32));
  for Mark := Low(TPieceMark) to High(TPieceMark) do
    MarksWidth := Max(MarksWidth, Canvas.TextWidth(MARK_CAPTIONS[Mark]) + Scale96ToForm(32));
  FMarksPanel.Width := Max(FMarksPanel.Width, MarksWidth);
  Needed := Needed + FMarksPanel.Width + Scale96ToForm(16);
  Width := Min(Limit.Width, Width + Max(0, Needed - ClientWidth));
  Height := Min(Height, Limit.Height);
  MoveToDefaultPosition;
end;

procedure TProfilesDialog.RefreshProfiles(Index: integer);
var
  Machine: TMachineProfile;
  Output: TOutputProfile;
begin
  FUpdating := True;
  try
    FKindBox.ItemIndex := Ord(FKind);
    FProfileBox.Items.Clear;
    if FKind = prMachine then
      for Machine in FMachines do
        FProfileBox.Items.Add(Machine.Name)
    else
      for Output in FOutputs do
        FProfileBox.Items.Add(Output.Name);
    FIndex := Min(Index, FProfileBox.Items.Count - 1);
    FProfileBox.ItemIndex := FIndex;
    ShowProfile;
  finally
    FUpdating := False;
  end;
end;

procedure TProfilesDialog.ShowProfile;
var
  Role: TEdgeRole;
  Kind: TLineType;
  Mark: TPieceMark;
  Style: TRoleStyle;
  Line: TLineStyle;
  Row: integer;
begin
  FGrid.Enabled := FIndex >= 0;
  FGrid.Visible := FGrid.Enabled;
  FEmpty.Visible := not FGrid.Enabled;
  FRemove.Enabled := FGrid.Enabled;
  FMarks.Parent.Visible := FKind = prOutput;
  FMarks.Enabled := FGrid.Enabled;
  FAllowance.Enabled := FGrid.Enabled;
  FGrid.RowCount := 2;
  for Row := 0 to FGrid.ColCount - 1 do
    FGrid.Cells[Row, 1] := '';
  FAllowance.Checked := False;
  for Mark := Low(TPieceMark) to High(TPieceMark) do
    FMarks.Checked[Ord(Mark)] := False;
  if FKind = prMachine then
    FGrid.Columns[COL_LAYER_OR_DASH].Title.Caption := rsProfilesLayer
  else
    FGrid.Columns[COL_LAYER_OR_DASH].Title.Caption := rsProfilesDashes;
  if FIndex < 0 then
    Exit;
  if FKind = prMachine then
  begin
    FGrid.RowCount := Succ(Ord(High(TLineType))) + 1;
    for Kind := Low(TLineType) to High(TLineType) do
    begin
      Row := Ord(Kind) + 1;
      Line := FMachines[FIndex].Lines[Kind];
      FGrid.Cells[0, Row] := LINE_CAPTIONS[Kind];
      FGrid.Cells[COL_INCLUDE, Row] := CheckedText(Line.Enabled);
      FGrid.Cells[COL_COLOR, Row] := Line.Color;
      FGrid.Cells[COL_LAYER_OR_DASH, Row] := Line.Layer;
      FGrid.Cells[COL_WIDTH, Row] := FloatToStr(Line.Width);
    end;
    Exit;
  end;
  Row := 1;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    if Role in MARKING_ROLES then
    begin
      FGrid.RowCount := Row + 1;
      FGrid.Cells[0, Row] := RoleCaption(Role);
      FGrid.Cells[COL_INCLUDE, Row] := CheckedText(Role in FOutputs[FIndex].Roles);
      Style := FOutputs[FIndex].Styles[Role];
      if Style.Custom then
      begin
        FGrid.Cells[COL_COLOR, Row] := Style.Color;
        FGrid.Cells[COL_LAYER_OR_DASH, Row] := DashText(Style.Dashes);
        FGrid.Cells[COL_WIDTH, Row] := FloatToStr(Style.Width);
      end;
      Inc(Row);
    end;
  for Mark := Low(TPieceMark) to High(TPieceMark) do
    FMarks.Checked[Ord(Mark)] := Mark in FOutputs[FIndex].PieceMarks;
  FAllowance.Checked := FOutputs[FIndex].Allowance = apKeep;
end;

function TProfilesDialog.ReadMachine: boolean;
var
  Profile: TMachineProfile;
  Kind: TLineType;
  Row: integer;
begin
  Profile := FMachines[FIndex];
  for Kind := Low(TLineType) to High(TLineType) do
  begin
    Row := Ord(Kind) + 1;
    if not TryMachineLineStyle(FGrid.Cells[COL_INCLUDE, Row] = CHECKED_VALUE, FGrid.Cells[COL_COLOR, Row],
      FGrid.Cells[COL_LAYER_OR_DASH, Row], FGrid.Cells[COL_WIDTH, Row], Profile.Lines[Kind]) then
    begin
      MessageDlg(Format(rsProfilesBadLine, [LINE_CAPTIONS[Kind]]), mtError, [mbOK], 0);
      Exit(False);
    end;
  end;
  FMachines[FIndex] := Profile;
  Result := True;
end;

function TProfilesDialog.ReadOutput: boolean;
var
  Profile: TOutputProfile;
  Style: TRoleStyle;
  Role: TEdgeRole;
  Mark: TPieceMark;
  Row: integer;
begin
  Profile := FOutputs[FIndex];
  Row := 1;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    if Role in MARKING_ROLES then
    begin
      if FGrid.Cells[COL_INCLUDE, Row] = CHECKED_VALUE then
        Include(Profile.Roles, Role)
      else
        Exclude(Profile.Roles, Role);
      if not TryOutputRoleStyle(FGrid.Cells[COL_COLOR, Row], FGrid.Cells[COL_LAYER_OR_DASH, Row],
        FGrid.Cells[COL_WIDTH, Row], Style) then
      begin
        MessageDlg(Format(rsProfilesBadStyle, [RoleCaption(Role)]), mtError, [mbOK], 0);
        Exit(False);
      end;
      Profile.Styles[Role] := Style;
      Inc(Row);
    end;
  Profile.PieceMarks := [];
  for Mark := Low(TPieceMark) to High(TPieceMark) do
    if FMarks.Checked[Ord(Mark)] then
      Include(Profile.PieceMarks, Mark);
  if FAllowance.Checked then
    Profile.Allowance := apKeep
  else
    Profile.Allowance := apNone;
  FOutputs[FIndex] := Profile;
  Result := True;
end;

function TProfilesDialog.ReadProfile: boolean;
begin
  FGrid.EditorMode := False;
  if FIndex < 0 then
    Exit(True);
  if FKind = prMachine then
    Result := ReadMachine
  else
    Result := ReadOutput;
end;

procedure TProfilesDialog.PickProfile(Sender: TObject);
var
  Index: integer;
  Kind: TProfileKind;
begin
  if FUpdating or (FKindBox.ItemIndex < 0) then
    Exit;
  Index := FProfileBox.ItemIndex;
  Kind := TProfileKind(FKindBox.ItemIndex);
  if not ReadProfile then
  begin
    FUpdating := True;
    try
      FKindBox.ItemIndex := Ord(FKind);
      FProfileBox.ItemIndex := FIndex;
    finally
      FUpdating := False;
    end;
    Exit;
  end;
  if Kind <> FKind then
    Index := 0;
  FKind := Kind;
  RefreshProfiles(Index);
end;

procedure TProfilesDialog.AddProfile(Sender: TObject);
var
  Machine: TMachineProfile;
  Output: TOutputProfile;
  ProfileName: string;
begin
  if not ReadProfile then
    Exit;
  ProfileName := '';
  if not InputQuery(rsProfilesAdd, rsProfilesName, ProfileName) then
    Exit;
  ProfileName := Trim(ProfileName);
  if ((FKind = prMachine) and (IsBuiltInMachineProfile(ProfileName) or SameText(ProfileName, rsProfileNone))) or
    ((FKind = prOutput) and (IsBuiltInOutputProfile(ProfileName) or SameText(ProfileName, rsOutputProfileAll))) then
  begin
    MessageDlg(rsProfilesReservedName, mtError, [mbOK], 0);
    Exit;
  end;
  if (ProfileName = '') or ((FKind = prMachine) and FindMachineProfile(FMachines, ProfileName, Machine)) or
    ((FKind = prOutput) and FindOutputProfile(FOutputs, ProfileName, Output)) then
  begin
    MessageDlg(rsProfilesNameTaken, mtError, [mbOK], 0);
    Exit;
  end;
  if FKind = prMachine then
  begin
    if FIndex >= 0 then
      Machine := FMachines[FIndex]
    else
      Machine := StandardProfile;
    Machine.Name := ProfileName;
    Insert(Machine, FMachines, Length(FMachines));
    RefreshProfiles(High(FMachines));
  end
  else
  begin
    if FIndex >= 0 then
      Output := FOutputs[FIndex]
    else
      Output := FullOutputProfile;
    Output.Name := ProfileName;
    Insert(Output, FOutputs, Length(FOutputs));
    RefreshProfiles(High(FOutputs));
  end;
end;

procedure TProfilesDialog.RemoveProfile(Sender: TObject);
begin
  if FIndex < 0 then
    Exit;
  FGrid.EditorMode := False;
  if FKind = prMachine then
    Delete(FMachines, FIndex, 1)
  else
    Delete(FOutputs, FIndex, 1);
  RefreshProfiles(FIndex);
end;

procedure TProfilesDialog.SaveProfiles(Sender: TObject);
var
  Reason: string;
begin
  if not ReadProfile then
    Exit;
  TAppPaths.ForceDir(TAppPaths.ConfigDir);
  if SaveProfilesToFile(TAppPaths.SettingsFile, FMachines, FOutputs, Reason) then
    ModalResult := mrOk
  else
    MessageDlg(Reason, mtError, [mbOK], 0);
end;

function EditUserProfiles(Owner: TComponent; out Machines: TMachineProfileArray; out Outputs: TOutputProfileArray): boolean;
var
  Settings: TAppSettings;
  Dialog: TProfilesDialog;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  Dialog := nil;
  try
    if not Settings.LoadFromFile(TAppPaths.SettingsFile, Reason) then
    begin
      MessageDlg(Reason, mtError, [mbOK], 0);
      Exit(False);
    end;
    Dialog := TProfilesDialog.CreateDialog(Owner, Settings);
    Result := Dialog.ShowModal = mrOk;
    if Result then
    begin
      Machines := Dialog.FMachines;
      Outputs := Dialog.FOutputs;
    end;
  finally
    FreeAndNil(Dialog);
    FreeAndNil(Settings);
  end;
end;

end.
