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

// The Preferences dialog, the same in every app: a General tab with the
// unit and Claude, which every app's Claude tab uses, a Design tab with the
// grid, a Publish tab with the printer calibration and a Drape tab with
// Blender. What it saves goes straight to settings.json, read again first
// so the other apps' settings stay.
unit Sloper.UI.Preferences;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Sloper.Core.Settings;

type
  TPreferencesTab = (ptGeneral, ptDesign, ptPublish, ptDrape);

// Opens on FirstTab. True when the user saved changes, which Preferences
// then holds; a file that cannot be written is reported and gives False.
function EditPreferences(AOwner: TComponent; FirstTab: TPreferencesTab; out Preferences: TPreferences): boolean;

resourcestring
  rsPreferencesTitle = 'Preferences';
  rsPreferencesGeneral = 'General';
  rsPreferencesDesign = 'Design';
  rsPreferencesPublish = 'Publish';
  rsPreferencesUnitGroup = 'Units';
  rsPreferencesUnit = 'Unit';
  rsPreferencesUnitMillimetre = 'Millimetres (mm)';
  rsPreferencesUnitCentimetre = 'Centimetres (cm)';
  rsPreferencesUnitInch = 'Inches (in)';
  rsPreferencesUnitNote = 'Measurements, and the drafting app''s rulers, grid and cursor position, are shown in this unit. ' +
    'New patterns will start in it once patterns can have units other than millimetres.';
  rsPreferencesGrid = 'Grid Spacing';
  rsPreferencesGridNote = 'Each unit keeps its own spacing. Zoomed out too far to see the lines, the grid spaces them further apart, always on multiples of this spacing.';
  rsPreferencesRoleStyles = 'Line Styles';
  rsPreferencesRole = 'Role';
  rsPreferencesRoleColor = 'Colour';
  rsPreferencesRoleDash = 'Line pattern';
  rsPreferencesRoleWidth = 'Width (px)';
  rsPreferencesRoleDefault = 'Default';
  rsPreferencesRoleSolid = 'Solid';
  rsPreferencesRoleDashed = 'Dashed';
  rsPreferencesRoleDotted = 'Dotted';
  rsPreferencesRoleDashDot = 'Dash-dot';
  rsPreferencesRoleReset = 'Reset this role';
  rsPreferencesRoleNote = 'These styles apply to the Design canvas. A width of 0 uses the default.';
  rsPreferencesCalibrationX = 'Calibration across';
  rsPreferencesCalibrationY = 'Calibration down';
  rsPreferencesCalibration = 'Printer Calibration';
  rsPreferencesCalibrationNote = 'Everything printed at true size is scaled by these factors, for a printer that is consistently a little off.';
  rsPreferencesTestPrint = 'Work Out From a Test Print';
  rsPreferencesTestPrintNote = 'Print a layout with the factors above, measure the test square on its first page, and type what you measured.';
  rsPreferencesTestSquare = 'Test square';
  rsPreferencesSquareMetric = '10 cm (A4, A3 and others)';
  rsPreferencesSquareInch = '4 in (Letter)';
  rsPreferencesMeasuredX = 'Measured across (%s)';
  rsPreferencesMeasuredY = 'Measured down (%s)';
  rsPreferencesWorkOut = 'Work Out Factors';
  rsPreferencesGarment = 'Garment View';
  rsPreferencesGarmentShade = 'Shade pieces as if round a body';
  rsPreferencesGarmentLight = 'Light from (degrees)';
  rsPreferencesGarmentStrength = 'Shading strength (%)';
  rsPreferencesGarmentNote = 'How the Garment tab lights the pieces. 0° is from the right and 90° from above, so 135° is the upper left.';
  rsPreferencesDrape = 'Drape';
  rsPreferencesBlender = 'Blender';
  rsPreferencesBlenderProgram = 'Program';
  rsPreferencesBlenderBrowse = 'Choose...';
  rsPreferencesBlenderNote = 'Leave it empty to use Blender on the path, or where its installer puts it. Draping is ' +
    'written for Blender %s; download it from blender.org.';
  rsPreferencesBlenderFound = 'Blender to run: %s';
  rsPreferencesBlenderMissing = 'Blender was not found.';
  rsPreferencesDraping = 'Draping';
  rsPreferencesDrapeSpacing = 'Mesh spacing (mm)';
  rsPreferencesDrapeFrames = 'Frames to simulate';
  rsPreferencesDrapingNote = 'Pieces are meshed with points about this far apart. Closer points follow curves better ' +
    'but simulate more slowly; 20 mm is quick for a first look. The seams are sewn in the first 40 frames, then the ' +
    'garment settles.';
  rsPreferencesNotSaved = 'The preferences could not be saved: %s';
  rsPreferencesClaude = 'AI assistants';
  rsPreferencesClaudeKey = 'Anthropic API key';
  rsPreferencesClaudeNote = 'Every app''s Claude tab uses this key, billed to its account. It sends your questions and ' +
    'what you have open to Anthropic: a pattern''s names, formulas and drawings, or a layout''s or a drape''s pieces and ' +
    'images. Folders and the measurement file''s name are never sent. The key is kept in a file only you can read.';
  rsPreferencesClaudeMeasurements = 'Let AI assistants read the measurements';
  rsPreferencesClaudeMeasurementsNote = 'Off, the design app''s Claude tab and any AI assistant connected to its window can neither ' +
    'read nor change the measurement values. The pattern''s points and lengths are still sent, and they are worked out ' +
    'from the measurements.';
  rsPreferencesClaudeFromEnvironment = 'Using the key in ANTHROPIC_API_KEY.';
  rsPreferencesKeyNotSaved = 'The API key could not be saved: %s';

implementation

uses
  SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls, Spin, ButtonPanel, Dialogs, Sloper.Core.Measurements,
  Sloper.Core.Units, Sloper.Core.Draft, Sloper.Editor.PropertyText, Sloper.UI.Spacing, Sloper.UI.MaterialGrid,
  Sloper.Assistant.Key, Sloper.Output.BlenderRun, Types;

const
  DIALOG_WIDTH = 560;
  DIALOG_HEIGHT = 700;
  // Room left round the dialog for its title bar and frame
  FRAME_MARGIN = 48;
  CALIBRATION_DECIMALS = 4;
  MEASURED_DECIMALS: array[TMeasureUnit] of integer = (1, 2, 3);
  GRID_DECIMALS: array[TMeasureUnit] of integer = (1, 2, 4);
  GRID_INCREMENTS: array[TMeasureUnit] of double = (1, 0.1, 0.0625);
  CALIBRATION_INCREMENT = 0.001;
  DRAPE_SPACING_DECIMALS = 1;
  DRAPE_SPACING_INCREMENT = 1;
  DRAPE_FRAMES_INCREMENT = 10;
  UNIT_CAPTIONS: array[TMeasureUnit] of string = (rsPreferencesUnitMillimetre, rsPreferencesUnitCentimetre, rsPreferencesUnitInch);
  DASH_CAPTIONS: array[TRoleDashStyle] of string = (rsPreferencesRoleDefault, rsPreferencesRoleSolid, rsPreferencesRoleDashed,
    rsPreferencesRoleDotted, rsPreferencesRoleDashDot);

type
  // Holds the controls while the dialog is open
  TPreferencesDialog = class(TForm)
  private
    FPages: TPageControl;
    FUnitBox, FSquareBox: TComboBox;
    FGridEdits: array[TMeasureUnit] of TFloatSpinEdit;
    FRoleBox, FRoleDashBox: TComboBox;
    FRoleColorButton: TButton;
    FRoleWidthEdit: TFloatSpinEdit;
    FRole: TEdgeRole;
    FRoleStyles: TRoleDisplayStyles;
    FCalibrationXEdit, FCalibrationYEdit, FMeasuredXEdit, FMeasuredYEdit: TFloatSpinEdit;
    FShadeBox: TCheckBox;
    FShareMeasurementsBox: TCheckBox;
    FLightEdit, FStrengthEdit: TFloatSpinEdit;
    FMeasuredXLabel, FMeasuredYLabel: TLabel;
    FKeyEdit, FBlenderEdit: TEdit;
    FBlenderFound: TLabel;
    FSpacingEdit, FFramesEdit: TFloatSpinEdit;
    FKeyShown: string;
    // The unit the measured sizes are typed in, which follows the Units box
    FMeasuredUnit: TMeasureUnit;
    // Each tab's contents, and the caption and control rows, which the
    // dialog is sized to show in full
    FHosts: array of TScrollBox;
    FRowPanels: array of TPanel;
    function AddTab(const ACaption: string): TScrollBox;
    function AddGroup(Host: TScrollBox; const ACaption: string): TGroupBox;
    function AddRows(Host: TWinControl): TPanel;
    function AddNote(Host: TWinControl; const AText: string): TLabel;
    function AddRow(Rows: TPanel; const ACaption: string; Control: TControl): TLabel;
    function NewSpin(MinValue, MaxValue, Increment: double; Decimals: integer): TFloatSpinEdit;
    procedure BuildGeneralTab;
    procedure BuildDesignTab;
    procedure BuildRoleStylesGroup(Host: TScrollBox);
    procedure ShowRoleStyle;
    procedure StoreRoleStyle;
    procedure RoleChange(Sender: TObject);
    procedure RoleColorClick(Sender: TObject);
    procedure RoleResetClick(Sender: TObject);
    procedure BuildGarmentGroup(Host: TScrollBox);
    procedure BuildClaudeGroup(Host: TScrollBox);
    procedure BuildPublishTab;
    procedure BuildDrapeTab;
    procedure BlenderChange(Sender: TObject);
    procedure BlenderBrowseClick(Sender: TObject);
    function ExpectedSide: double;
    procedure ShowMeasuredUnit;
    procedure UnitChange(Sender: TObject);
    procedure SquareChange(Sender: TObject);
    procedure WorkOutClick(Sender: TObject);
    function WorkArea: TRect;
    // Sizes the dialog to its contents, within the screen
    procedure FitContents;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent);
    procedure ShowPreferences(const Preferences: TPreferences);
    function ReadPreferences: TPreferences;
    // Writes the key file when the key was changed; False with a message
    function SaveKey(out ErrorMessage: string): boolean;
  end;

constructor TPreferencesDialog.CreateDialog(AOwner: TComponent);
var
  Buttons: TButtonPanel;
begin
  inherited CreateNew(AOwner);
  Caption := rsPreferencesTitle;
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  Width := Scale96ToForm(DIALOG_WIDTH);
  Height := Scale96ToForm(DIALOG_HEIGHT);
  Buttons := TButtonPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.ShowButtons := [pbOK, pbCancel];
  SpaceButtons(Buttons);
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.BorderSpacing.Around := ControlGap;
  BuildGeneralTab;
  BuildDesignTab;
  BuildPublishTab;
  BuildDrapeTab;
end;

// A sheet scrolls only when the screen is too small for the whole dialog
function TPreferencesDialog.AddTab(const ACaption: string): TScrollBox;
var
  Sheet: TTabSheet;
begin
  Sheet := FPages.AddTabSheet;
  Sheet.Caption := ACaption;
  Result := TScrollBox.Create(Self);
  Result.BorderStyle := bsNone;
  Result.Align := alClient;
  Result.HorzScrollBar.Visible := False;
  Result.Parent := Sheet;
  Insert(Result, FHosts, Length(FHosts));
end;

// Below everything already in Host, since top-aligned controls are stacked
// in the order of their tops
procedure StackIn(Host: TWinControl; Control: TControl);
var
  Index, Bottom: integer;
begin
  Bottom := 0;
  for Index := 0 to Host.ControlCount - 1 do
    if Host.Controls[Index] <> Control then
      Bottom := Max(Bottom, Host.Controls[Index].Top + Host.Controls[Index].Height);
  Control.Top := Bottom + 1;
  Control.Align := alTop;
  Control.BorderSpacing.Around := ControlGap;
  Control.Parent := Host;
end;

// A captioned box around one section of a sheet
function TPreferencesDialog.AddGroup(Host: TScrollBox; const ACaption: string): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Caption := ACaption;
  Result.AutoSize := True;
  StackIn(Host, Result);
end;

// Controls in two columns, captions on the left
function TPreferencesDialog.AddRows(Host: TWinControl): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  Result.ChildSizing.ControlsPerLine := 2;
  Result.ChildSizing.HorizontalSpacing := ControlGap;
  Result.ChildSizing.VerticalSpacing := ControlGap;
  Result.ChildSizing.EnlargeHorizontal := crsHomogenousChildResize;
  StackIn(Host, Result);
  Insert(Result, FRowPanels, Length(FRowPanels));
end;

// Wrapped text across the host
function TPreferencesDialog.AddNote(Host: TWinControl; const AText: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.Caption := AText;
  StackIn(Host, Result);
end;

function TPreferencesDialog.AddRow(Rows: TPanel; const ACaption: string; Control: TControl): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.Layout := tlCenter;
  Result.Parent := Rows;
  Control.Parent := Rows;
end;

function TPreferencesDialog.NewSpin(MinValue, MaxValue, Increment: double; Decimals: integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.DecimalPlaces := Decimals;
  Result.MinValue := MinValue;
  Result.MaxValue := MaxValue;
  Result.Increment := Increment;
end;

procedure TPreferencesDialog.BuildGeneralTab;
var
  Group: TGroupBox;
  Host: TScrollBox;
begin
  Host := AddTab(rsPreferencesGeneral);
  Group := AddGroup(Host, rsPreferencesUnitGroup);
  FUnitBox := TComboBox.Create(Self);
  FUnitBox.Style := csDropDownList;
  // In the order of TMeasureUnit
  FUnitBox.Items.Add(rsPreferencesUnitMillimetre);
  FUnitBox.Items.Add(rsPreferencesUnitCentimetre);
  FUnitBox.Items.Add(rsPreferencesUnitInch);
  FUnitBox.OnChange := @UnitChange;
  AddRow(AddRows(Group), rsPreferencesUnit, FUnitBox);
  AddNote(Group, rsPreferencesUnitNote);
  BuildClaudeGroup(Host);
end;

procedure TPreferencesDialog.BuildDesignTab;
var
  Group: TGroupBox;
  Rows: TPanel;
  AUnit: TMeasureUnit;
  Host: TScrollBox;
begin
  Host := AddTab(rsPreferencesDesign);
  Group := AddGroup(Host, rsPreferencesGrid);
  Rows := AddRows(Group);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
  begin
    FGridEdits[AUnit] := NewSpin(IntPower(10, -GRID_DECIMALS[AUnit]), MAX_GRID_STEP / MILLIMETRES_PER_UNIT[AUnit], GRID_INCREMENTS[AUnit],
      GRID_DECIMALS[AUnit]);
    AddRow(Rows, UNIT_CAPTIONS[AUnit], FGridEdits[AUnit]);
  end;
  AddNote(Group, rsPreferencesGridNote);
  BuildRoleStylesGroup(Host);
  BuildGarmentGroup(Host);
end;

procedure TPreferencesDialog.BuildRoleStylesGroup(Host: TScrollBox);
var
  Group: TGroupBox;
  Rows: TPanel;
  Role: TEdgeRole;
  Dash: TRoleDashStyle;
  ResetButton: TButton;
begin
  Group := AddGroup(Host, rsPreferencesRoleStyles);
  Rows := AddRows(Group);
  FRoleBox := TComboBox.Create(Self);
  FRoleBox.Style := csDropDownList;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
    FRoleBox.Items.Add(RoleCaption(Role));
  FRoleBox.OnChange := @RoleChange;
  AddRow(Rows, rsPreferencesRole, FRoleBox);
  FRoleColorButton := TButton.Create(Self);
  FRoleColorButton.OnClick := @RoleColorClick;
  AddRow(Rows, rsPreferencesRoleColor, FRoleColorButton);
  FRoleDashBox := TComboBox.Create(Self);
  FRoleDashBox.Style := csDropDownList;
  for Dash := Low(TRoleDashStyle) to High(TRoleDashStyle) do
    FRoleDashBox.Items.Add(DASH_CAPTIONS[Dash]);
  AddRow(Rows, rsPreferencesRoleDash, FRoleDashBox);
  FRoleWidthEdit := NewSpin(0, MAX_ROLE_WIDTH, 0.5, 1);
  AddRow(Rows, rsPreferencesRoleWidth, FRoleWidthEdit);
  ResetButton := TButton.Create(Self);
  ResetButton.Caption := rsPreferencesRoleReset;
  ResetButton.OnClick := @RoleResetClick;
  AddRow(Rows, '', ResetButton);
  AddNote(Group, rsPreferencesRoleNote);
end;

procedure TPreferencesDialog.ShowRoleStyle;
begin
  if FRoleStyles[FRole].Color = '' then
    FRoleColorButton.Caption := rsPreferencesRoleDefault
  else
    FRoleColorButton.Caption := FRoleStyles[FRole].Color;
  FRoleDashBox.ItemIndex := Ord(FRoleStyles[FRole].Dash);
  FRoleWidthEdit.Value := FRoleStyles[FRole].Width;
end;

procedure TPreferencesDialog.StoreRoleStyle;
begin
  if FRoleDashBox.ItemIndex >= 0 then
    FRoleStyles[FRole].Dash := TRoleDashStyle(FRoleDashBox.ItemIndex);
  FRoleStyles[FRole].Width := FRoleWidthEdit.Value;
end;

procedure TPreferencesDialog.RoleChange(Sender: TObject);
begin
  if FRoleBox.ItemIndex < 0 then
    Exit;
  StoreRoleStyle;
  FRole := TEdgeRole(FRoleBox.ItemIndex);
  ShowRoleStyle;
end;

procedure TPreferencesDialog.RoleColorClick(Sender: TObject);
var
  ChosenColor: string;
begin
  ChosenColor := RoleDisplayColor(FRole, FRoleStyles[FRole]);
  if ChooseMaterialColor(Self, ChosenColor) then
  begin
    FRoleStyles[FRole].Color := ChosenColor;
    FRoleColorButton.Caption := ChosenColor;
  end;
end;

procedure TPreferencesDialog.RoleResetClick(Sender: TObject);
begin
  FRoleStyles[FRole] := Default(TRoleDisplayStyle);
  ShowRoleStyle;
end;

procedure TPreferencesDialog.BuildGarmentGroup(Host: TScrollBox);
var
  Group: TGroupBox;
  Rows: TPanel;
begin
  Group := AddGroup(Host, rsPreferencesGarment);
  FShadeBox := TCheckBox.Create(Self);
  FShadeBox.Caption := rsPreferencesGarmentShade;
  StackIn(Group, FShadeBox);
  Rows := AddRows(Group);
  FLightEdit := NewSpin(0, 359, 15, 0);
  AddRow(Rows, rsPreferencesGarmentLight, FLightEdit);
  FStrengthEdit := NewSpin(0, 100, 10, 0);
  AddRow(Rows, rsPreferencesGarmentStrength, FStrengthEdit);
  AddNote(Group, rsPreferencesGarmentNote);
end;

// The key is shown masked; from the environment it cannot be changed here
procedure TPreferencesDialog.BuildClaudeGroup(Host: TScrollBox);
var
  Group: TGroupBox;
  Source: TKeySource;
begin
  Group := AddGroup(Host, rsPreferencesClaude);
  FKeyEdit := TEdit.Create(Self);
  FKeyEdit.PasswordChar := '*';
  FKeyShown := AssistantKey(Source);
  FKeyEdit.Text := FKeyShown;
  FKeyEdit.Enabled := Source <> ksEnvironment;
  AddRow(AddRows(Group), rsPreferencesClaudeKey, FKeyEdit);
  if Source = ksEnvironment then
    AddNote(Group, rsPreferencesClaudeFromEnvironment);
  AddNote(Group, rsPreferencesClaudeNote);
  FShareMeasurementsBox := TCheckBox.Create(Self);
  FShareMeasurementsBox.Caption := rsPreferencesClaudeMeasurements;
  StackIn(Group, FShareMeasurementsBox);
  AddNote(Group, rsPreferencesClaudeMeasurementsNote);
end;

function TPreferencesDialog.SaveKey(out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  Result := not FKeyEdit.Enabled or (FKeyEdit.Text = FKeyShown) or SaveAssistantKey(FKeyEdit.Text, ErrorMessage);
end;

procedure TPreferencesDialog.BuildPublishTab;
var
  Host: TScrollBox;
  Group: TGroupBox;
  Rows: TPanel;
  WorkOut: TButton;
begin
  Host := AddTab(rsPreferencesPublish);
  Group := AddGroup(Host, rsPreferencesCalibration);
  Rows := AddRows(Group);
  FCalibrationXEdit := NewSpin(MIN_CALIBRATION, MAX_CALIBRATION, CALIBRATION_INCREMENT, CALIBRATION_DECIMALS);
  AddRow(Rows, rsPreferencesCalibrationX, FCalibrationXEdit);
  FCalibrationYEdit := NewSpin(MIN_CALIBRATION, MAX_CALIBRATION, CALIBRATION_INCREMENT, CALIBRATION_DECIMALS);
  AddRow(Rows, rsPreferencesCalibrationY, FCalibrationYEdit);
  AddNote(Group, rsPreferencesCalibrationNote);
  Group := AddGroup(Host, rsPreferencesTestPrint);
  AddNote(Group, rsPreferencesTestPrintNote);
  Rows := AddRows(Group);
  FSquareBox := TComboBox.Create(Self);
  FSquareBox.Style := csDropDownList;
  FSquareBox.Items.Add(rsPreferencesSquareMetric);
  FSquareBox.Items.Add(rsPreferencesSquareInch);
  FSquareBox.ItemIndex := 0;
  FSquareBox.OnChange := @SquareChange;
  AddRow(Rows, rsPreferencesTestSquare, FSquareBox);
  FMeasuredXEdit := NewSpin(0, 1000, 0.1, 1);
  FMeasuredXLabel := AddRow(Rows, '', FMeasuredXEdit);
  FMeasuredYEdit := NewSpin(0, 1000, 0.1, 1);
  FMeasuredYLabel := AddRow(Rows, '', FMeasuredYEdit);
  WorkOut := TButton.Create(Self);
  WorkOut.Caption := rsPreferencesWorkOut;
  WorkOut.AutoSize := True;
  WorkOut.OnClick := @WorkOutClick;
  AddRow(Rows, '', WorkOut);
end;

procedure TPreferencesDialog.BuildDrapeTab;
var
  Host: TScrollBox;
  Group: TGroupBox;
  Rows: TPanel;
  Browse: TButton;
begin
  Host := AddTab(rsPreferencesDrape);
  Group := AddGroup(Host, rsPreferencesBlender);
  Rows := AddRows(Group);
  FBlenderEdit := TEdit.Create(Self);
  FBlenderEdit.OnChange := @BlenderChange;
  AddRow(Rows, rsPreferencesBlenderProgram, FBlenderEdit);
  Browse := TButton.Create(Self);
  Browse.Caption := rsPreferencesBlenderBrowse;
  Browse.AutoSize := True;
  Browse.OnClick := @BlenderBrowseClick;
  AddRow(Rows, '', Browse);
  FBlenderFound := AddNote(Group, '');
  AddNote(Group, Format(rsPreferencesBlenderNote, [BLENDER_SCRIPT_VERSION]));
  Group := AddGroup(Host, rsPreferencesDraping);
  Rows := AddRows(Group);
  FSpacingEdit := NewSpin(MIN_DRAPE_SPACING, MAX_DRAPE_SPACING, DRAPE_SPACING_INCREMENT, DRAPE_SPACING_DECIMALS);
  AddRow(Rows, rsPreferencesDrapeSpacing, FSpacingEdit);
  FFramesEdit := NewSpin(MIN_DRAPE_FRAMES, MAX_DRAPE_FRAMES, DRAPE_FRAMES_INCREMENT, 0);
  AddRow(Rows, rsPreferencesDrapeFrames, FFramesEdit);
  AddNote(Group, rsPreferencesDrapingNote);
end;

// Says which Blender will run, as the program is typed
procedure TPreferencesDialog.BlenderChange(Sender: TObject);
var
  Found: string;
begin
  Found := FindBlender(Trim(FBlenderEdit.Text));
  if Found = '' then
    FBlenderFound.Caption := rsPreferencesBlenderMissing
  else
    FBlenderFound.Caption := Format(rsPreferencesBlenderFound, [Found]);
end;

procedure TPreferencesDialog.BlenderBrowseClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.FileName := FBlenderEdit.Text;
    if Dialog.Execute then
      FBlenderEdit.Text := Dialog.FileName;
  finally
    FreeAndNil(Dialog);
  end;
end;

// The screen the dialog opens on, less the panels and a margin for the
// window frame, which the form's size leaves out
function TPreferencesDialog.WorkArea: TRect;
var
  Frame: integer;
begin
  if Owner is TCustomForm then
    Result := TCustomForm(Owner).Monitor.WorkareaRect
  else
    Result := Screen.WorkAreaRect;
  Frame := Scale96ToForm(FRAME_MARGIN);
  Result.Right := Result.Right - Frame;
  Result.Bottom := Result.Bottom - Frame;
end;

// The sizes are only known once the controls are laid out with the real font,
// which can be larger than the screen resolution alone gives. The width
// comes first, since wrapped notes are taller in a narrower dialog.
procedure TPreferencesDialog.FitContents;
var
  Index, Content, Extra, PreferredWidth, PreferredHeight: integer;
  Limit: TRect;
  Control: TControl;
begin
  Limit := WorkArea;
  Extra := 0;
  for Index := 0 to High(FRowPanels) do
  begin
    PreferredWidth := 0;
    PreferredHeight := 0;
    FRowPanels[Index].GetPreferredSize(PreferredWidth, PreferredHeight, True);
    Extra := Max(Extra, PreferredWidth - FRowPanels[Index].Width);
  end;
  Width := Min(Width + Extra, Limit.Width);
  // Laid out again at the new width before the notes are measured
  DisableAutoSizing;
  EnableAutoSizing;
  Extra := Low(integer);
  for Index := 0 to High(FHosts) do
  begin
    Content := 0;
    for Control in FHosts[Index].GetEnumeratorControls do
      Content := Max(Content, Control.Top + Control.Height + Control.BorderSpacing.Around + Control.BorderSpacing.Bottom);
    Extra := Max(Extra, Content - FHosts[Index].ClientHeight);
  end;
  Height := Min(Height + Extra, Limit.Height);
end;

// Only a shown dialog is laid out, so it is fitted here and centred again
procedure TPreferencesDialog.DoShow;
begin
  inherited DoShow;
  FitContents;
  MoveToDefaultPosition;
end;

procedure TPreferencesDialog.ShowPreferences(const Preferences: TPreferences);
var
  AUnit: TMeasureUnit;
begin
  FUnitBox.ItemIndex := Ord(Preferences.MeasureUnit);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    FGridEdits[AUnit].Value := Preferences.GridSteps[AUnit];
  FRole := Low(TEdgeRole);
  FRoleBox.ItemIndex := Ord(FRole);
  FRoleStyles := Preferences.RoleStyles;
  ShowRoleStyle;
  FCalibrationXEdit.Value := Preferences.Calibration.X;
  FCalibrationYEdit.Value := Preferences.Calibration.Y;
  FShadeBox.Checked := Preferences.GarmentShading;
  FShareMeasurementsBox.Checked := Preferences.AssistantMeasurements;
  FLightEdit.Value := Preferences.GarmentLightAngle;
  FStrengthEdit.Value := Preferences.GarmentShadeStrength * 100;
  FBlenderEdit.Text := Preferences.BlenderProgram;
  BlenderChange(nil);
  FSpacingEdit.Value := Preferences.DrapeSpacing;
  FFramesEdit.Value := Preferences.DrapeFrames;
  FSquareBox.ItemIndex := 0;
  FMeasuredUnit := Preferences.MeasureUnit;
  ShowMeasuredUnit;
  FMeasuredXEdit.Value := ExpectedSide / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.Value := FMeasuredXEdit.Value;
end;

function TPreferencesDialog.ReadPreferences: TPreferences;
var
  AUnit: TMeasureUnit;
begin
  Result := DefaultPreferences;
  StoreRoleStyle;
  Result.RoleStyles := FRoleStyles;
  if FUnitBox.ItemIndex >= 0 then
    Result.MeasureUnit := TMeasureUnit(FUnitBox.ItemIndex);
  for AUnit := Low(TMeasureUnit) to High(TMeasureUnit) do
    if GridStepIsUsable(FGridEdits[AUnit].Value, AUnit) then
      Result.GridSteps[AUnit] := FGridEdits[AUnit].Value;
  Result.Calibration.X := FCalibrationXEdit.Value;
  Result.Calibration.Y := FCalibrationYEdit.Value;
  if not CalibrationIsUsable(Result.Calibration) then
    Result.Calibration := NoCalibration;
  Result.GarmentShading := FShadeBox.Checked;
  Result.AssistantMeasurements := FShareMeasurementsBox.Checked;
  Result.GarmentLightAngle := FLightEdit.Value;
  Result.GarmentShadeStrength := EnsureRange(FStrengthEdit.Value / 100, 0, 1);
  Result.BlenderProgram := Trim(FBlenderEdit.Text);
  Result.DrapeSpacing := EnsureRange(FSpacingEdit.Value, MIN_DRAPE_SPACING, MAX_DRAPE_SPACING);
  Result.DrapeFrames := EnsureRange(Round(FFramesEdit.Value), MIN_DRAPE_FRAMES, MAX_DRAPE_FRAMES);
end;

// The side of the test square chosen, in mm
function TPreferencesDialog.ExpectedSide: double;
begin
  if FSquareBox.ItemIndex = 1 then
    Result := INCH_TEST_SQUARE_SIDE
  else
    Result := METRIC_TEST_SQUARE_SIDE;
end;

procedure TPreferencesDialog.ShowMeasuredUnit;
begin
  FMeasuredXLabel.Caption := Format(rsPreferencesMeasuredX, [MEASURE_UNIT_NAMES[FMeasuredUnit]]);
  FMeasuredYLabel.Caption := Format(rsPreferencesMeasuredY, [MEASURE_UNIT_NAMES[FMeasuredUnit]]);
  FMeasuredXEdit.DecimalPlaces := MEASURED_DECIMALS[FMeasuredUnit];
  FMeasuredYEdit.DecimalPlaces := MEASURED_DECIMALS[FMeasuredUnit];
  FMeasuredXEdit.Increment := IntPower(10, -MEASURED_DECIMALS[FMeasuredUnit]);
  FMeasuredYEdit.Increment := FMeasuredXEdit.Increment;
  FMeasuredXEdit.MaxValue := 2 * INCH_TEST_SQUARE_SIDE / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.MaxValue := FMeasuredXEdit.MaxValue;
end;

// The measured sizes keep their length in the new unit
procedure TPreferencesDialog.UnitChange(Sender: TObject);
var
  Across, Down: double;
begin
  if FUnitBox.ItemIndex < 0 then
    Exit;
  Across := FMeasuredXEdit.Value * MILLIMETRES_PER_UNIT[FMeasuredUnit];
  Down := FMeasuredYEdit.Value * MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredUnit := TMeasureUnit(FUnitBox.ItemIndex);
  ShowMeasuredUnit;
  FMeasuredXEdit.Value := Across / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.Value := Down / MILLIMETRES_PER_UNIT[FMeasuredUnit];
end;

// Starts the measured sizes at the square's own, so only what differs is typed
procedure TPreferencesDialog.SquareChange(Sender: TObject);
begin
  FMeasuredXEdit.Value := ExpectedSide / MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FMeasuredYEdit.Value := FMeasuredXEdit.Value;
end;

procedure TPreferencesDialog.WorkOutClick(Sender: TObject);
var
  Scale: double;
begin
  Scale := MILLIMETRES_PER_UNIT[FMeasuredUnit];
  FCalibrationXEdit.Value := CorrectedCalibration(FCalibrationXEdit.Value, ExpectedSide, FMeasuredXEdit.Value * Scale);
  FCalibrationYEdit.Value := CorrectedCalibration(FCalibrationYEdit.Value, ExpectedSide, FMeasuredYEdit.Value * Scale);
  // The new factors would print the square true, so the next print starts afresh
  SquareChange(nil);
end;

function EditPreferences(AOwner: TComponent; FirstTab: TPreferencesTab; out Preferences: TPreferences): boolean;
var
  Dialog: TPreferencesDialog;
  Reason: string;
begin
  Preferences := UserPreferences;
  Dialog := TPreferencesDialog.CreateDialog(AOwner);
  try
    Dialog.ShowPreferences(Preferences);
    Dialog.FPages.PageIndex := Ord(FirstTab);
    if Dialog.ShowModal <> mrOk then
      Exit(False);
    Preferences := Dialog.ReadPreferences;
    if not Dialog.SaveKey(Reason) then
      MessageDlg(Format(rsPreferencesKeyNotSaved, [Reason]), mtError, [mbOK], 0);
  finally
    FreeAndNil(Dialog);
  end;
  Result := SaveUserPreferences(Preferences, Reason);
  if not Result then
    MessageDlg(Format(rsPreferencesNotSaved, [Reason]), mtError, [mbOK], 0);
end;

end.
