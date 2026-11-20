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

// The drape app's one window: the 3D view of the body and the placed pieces,
// with the patterns, the pieces, the selected piece's placement and the
// problems in tabs beside it. Every edit goes through TDrapeDocument. Built
// in code, so it has no form file.
unit Sloper.Drape.MainForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Menus, Spin, Dialogs, ActnList, fpjson, Sloper.API.AppLink,
  Sloper.Core.PatternSources, Sloper.Core.DrapeFile, Sloper.Core.DrapePlacement, Sloper.Core.Seam, Sloper.Document.DrapeDocument, Sloper.Drape.View,
  Sloper.UI.Commands, Sloper.Core.Shortcuts, Sloper.UI.RecentMenu, Sloper.UI.SideTabs, Sloper.UI.SavePrompt, Sloper.UI.ProblemsPanel,
  Sloper.UI.AssistantPanel;

type
  TDrapeForm = class(TForm)
  private
    FDocument: TDrapeDocument;
    FView: TDrapeCanvas;
    FTabs: TSideTabs;
    FColumnSplitter: TSplitter;
    FPatternsSide, FPiecesSide, FPropertiesSide, FProblemsSide, FRowParent, FGroupOuter: TWinControl;
    FNextRowTop: integer;
    FStatus: TStatusBar;
    FProblemsList: TProblemsPanel;
    FAssistant: TAssistantPanel;
    FSourceBox, FPieceBox: TListBox;
    FRemoveSourceButton, FBodySetButton, FBodyPatternSetButton: TButton;
    FBodyKindBox, FBodySizeBox: TComboBox;
    FBodySetLabel, FSelectionLabel: TLabel;
    FGapEdit: TFloatSpinEdit;
    FPositionEdits, FRotationEdits: array[0..2] of TFloatSpinEdit;
    // The seams the selected piece can be aligned along, as listed
    FSeamBox: TListBox;
    FSeams: TSeamObjectArray;
    FAlignButton, FFoldButton: TButton;
    // What each line of the Pieces tab stands for
    FPieceCopies: TDrapePieceCopyArray;
    FCommands: TCommandSet;
    FSaveAction, FSaveAsAction, FUndoAction, FRedoAction, FReloadAction, FGuessAction, FFlipAction, FUnplaceAction,
    FPerspectiveAction, FBlenderAction: TAction;
    FRecent: TRecentMenu;
    FWatch: TTimer;
    FAppLink: TAppLink;
    FRefreshing: boolean;
    procedure BuildMenu;
    procedure BuildPatternsTab;
    procedure BuildPiecesTab;
    procedure BuildPropertiesTab;
    procedure PlaceRow(Row: TControl);
    procedure BeginGroup(const ACaption: string);
    procedure EndGroup;
    function AddLabel(const ACaption: string): TLabel;
    function AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
    function AddSpin(const ACaption: string; AMin, AMax, AIncrement: double): TFloatSpinEdit;
    function ScrollingRows(Side: TWinControl): TScrollBox;
    procedure DocumentChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure RefreshControls;
    procedure RefreshPatternsTab;
    procedure RefreshPiecesTab;
    procedure RefreshPropertiesTab;
    procedure RefreshProblems;
    procedure RefreshCommands;
    procedure ShowStatus(const AText: string);
    function SelectedCopy(out Copy: TDrapePieceCopy): boolean;
    function CopyCaption(const Copy: TDrapePieceCopy): string;
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure QuitClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure PreferencesClick(Sender: TObject);
    procedure BlenderClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ViewClick(Sender: TObject);
    procedure PerspectiveClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure GuessClick(Sender: TObject);
    procedure FlipClick(Sender: TObject);
    procedure UnplaceClick(Sender: TObject);
    procedure AboutClick(Sender: TObject);
    procedure UserGuideClick(Sender: TObject);
    procedure AddSourceClick(Sender: TObject);
    procedure RemoveSourceClick(Sender: TObject);
    procedure BodyKindChange(Sender: TObject);
    procedure BodySetClick(Sender: TObject);
    procedure BodyPatternSetClick(Sender: TObject);
    procedure BodySizeChange(Sender: TObject);
    procedure GapChange(Sender: TObject);
    procedure PieceBoxClick(Sender: TObject);
    procedure PieceBoxDoubleClick(Sender: TObject);
    procedure PlacementEditChange(Sender: TObject);
    procedure AlignClick(Sender: TObject);
    procedure SeamBoxClick(Sender: TObject);
    procedure ProblemSelect(Sender: TObject; const Key: string);
    procedure ViewKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure TabsCollapsedChange(Sender: TObject);
    procedure WatchTick(Sender: TObject);
    function AppLinkMessage(const Method: string; Params: TJSONObject): boolean;
    procedure CloseAsked(Sender: TObject; var CanClose: boolean);
    function ConfirmDiscard: boolean;
    procedure OpenPath(const Path: string);
    procedure RecentOpen(Sender: TObject; const FileName: string);
    function SaveTo(const FileName: string): boolean;
    function Save: boolean;
    function SaveAs: boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

resourcestring
  rsDrapeTitle = 'OpenSloper Drape';
  rsDrapeTitleFile = '%s%s - OpenSloper Drape';
  rsAboutSummary = 'Placing pattern pieces on a body, for draping in Blender.';
  rsMenuFile = '&File';
  rsMenuNew = '&New from Pattern...';
  rsMenuOpen = '&Open...';
  rsMenuSave = '&Save';
  rsMenuSaveAs = 'Save &As...';
  rsMenuQuit = '&Quit';
  rsMenuBlender = '&Drape in Blender...';
  rsBlenderNotFound = 'Blender was not found, so the files for it were written but not draped: %s. Install Blender %s, ' +
    'or choose its program in Edit -> Preferences -> Drape.';
  rsBlenderExportFailed = 'The files for Blender could not be written: %s';
  rsBlenderNoScript = 'The Blender script is missing from the program''s data folder; reinstall OpenSloper.';
  rsMenuEdit = '&Edit';
  rsMenuUndo = '&Undo';
  rsMenuUndoNamed = '&Undo %s';
  rsMenuRedo = '&Redo';
  rsMenuPreferences = 'Pre&ferences...';
  rsMenuView = '&View';
  rsMenuZoomIn = 'Zoom &In';
  rsMenuZoomOut = 'Zoom &Out';
  rsMenuFit = '&Fit Body';
  rsMenuFront = 'F&ront';
  rsMenuBack = '&Back';
  rsMenuLeft = '&Left Side';
  rsMenuRight = 'Ri&ght Side';
  rsMenuTop = '&Top';
  rsMenuThreeQuarter = 'Three-&Quarter';
  rsMenuPerspective = '&Perspective';
  rsMenuReload = 'Re&load Patterns';
  rsMenuPieces = '&Pieces';
  rsMenuGuess = '&Guess Placements';
  rsMenuFlip = '&Flip';
  rsMenuUnplace = '&Unplace';
  rsMenuHelp = '&Help';
  rsMenuUserGuide = '&User Guide';
  rsMenuAbout = '&About %s';
  rsTabPatterns = 'Patterns';
  rsTabPieces = 'Pieces';
  rsTabProperties = 'Properties';
  rsTabClaude = 'Claude';
  rsTabProblems = 'Problems';
  rsTabProblemsCount = 'Problems (%d)';
  rsPatternsLabel = 'Patterns';
  rsAddPattern = 'Add Pattern...';
  rsRemovePattern = 'Remove Pattern';
  rsBodyGroup = 'Body';
  rsBodyFigure = 'Figure';
  rsBodyNone = 'No body';
  rsBodySet = 'Measurements:';
  rsBodySetOfPattern = 'The first pattern''s';
  rsBodyChooseSet = 'Choose Measurements...';
  rsBodyPatternSet = 'Use the First Pattern''s';
  rsBodySize = 'Size:';
  rsBodySizeOfPattern = '(the pattern''s)';
  rsGap = 'Gap (mm):';
  rsPiecesHint = 'Double-click a piece that is not placed to place it by a guess';
  rsPlaced = '%s';
  rsNotPlaced = '%s - not placed';
  rsNothingSelected = 'Select a piece in the view or on the Pieces tab';
  rsPosition = 'Position (mm)';
  rsRotation = 'Turn (degrees)';
  rsAxisX = 'X, to the body''s left:';
  rsAxisY = 'Y, towards the back:';
  rsAxisZ = 'Z, up:';
  rsTurnX = 'About X, first:';
  rsTurnY = 'About Y:';
  rsTurnZ = 'About Z, last:';
  rsSeamsGroup = 'Seams to placed pieces';
  rsSeamsNone = 'No seam joins this piece to a placed one';
  rsAlignToSeam = 'Align to Seam';
  rsFoldOverSeam = 'Fold Over Seam';
  rsAlignChange = 'Align to Seam';
  rsCopyCaption = '%s, %s (copy %d of %d)';
  rsCopyCaptionOne = '%s, %s';
  rsNoProblems = 'No problems';
  rsProblemCount = 'Problems: %d';
  rsProblemsHint = 'Click to list the problems';
  rsReloaded = '%s changed on disk, so it was read again';
  rsGuessed = 'Placed %d pieces';
  rsNothingToGuess = 'Every piece is placed';
  rsFilterDrape = 'Drape files (*.sdrape)|*.sdrape';
  rsFilterOpen = 'Drape files and patterns (*.sdrape;*.sloper)|*.sdrape;*.sloper';
  rsFilterPattern = 'Patterns (*.sloper)|*.sloper';
  rsFilterMeasurements = 'Measurements (*.slm)|*.slm';
  rsAddPatternChange = 'Add Pattern';
  rsRemovePatternChange = 'Remove Pattern';
  rsBodyChange = 'Change Body';
  rsGapChange = 'Change Gap';
  rsPlaceChange = 'Place Piece';
  rsGuessChange = 'Guess Placements';
  rsFlipChange = 'Flip Piece';
  rsUnplaceChange = 'Unplace Piece';

implementation

uses
  LCLType, Math, StrUtils, Sloper.Core.Geometry3, Sloper.Core.Piece, Sloper.Core.RecentFiles, Sloper.Core.Settings,
  Sloper.Core.IconSet, Sloper.Core.JSON, Sloper.UI.Spacing, Sloper.UI.About, Sloper.UI.Help, Sloper.UI.Preferences,
  Sloper.API.Endpoint, Sloper.Core.DrapeMesh, Sloper.Core.AppPaths, Sloper.Output.DrapeExport, Sloper.Output.BlenderRun,
  Sloper.Drape.BlenderDialog, Sloper.UI.AssistantHosts;

const
  SIDE_WIDTH = 320;
  SIDE_ROW_STEP = 100;
  LIST_HEIGHT = 110;
  PANEL_PROBLEMS = 0;
  PANEL_MESSAGE = 1;
  PROBLEMS_PANEL_WIDTH96 = 150;
  PANEL_PADDING96 = 16;
  MIN_MESSAGE_WIDTH = 50;
  WATCH_MILLISECONDS = 1000;
  PATTERN_EXTENSION = '.sloper';
  MODIFIED_MARK: array[boolean] of string = ('', '*');
  PROBLEMS_SECTION = 'problems';
  PROPERTIES_SECTION = 'properties';
  CLAUDE_SECTION = 'claude';
  // A problem's key in the Problems tab: the item it is about, by index
  ITEM_KEY = 'item:';
  // Fields: how far a position may go (mm), and the decimals shown
  MAX_POSITION = 5000;
  POSITION_STEP = 5;
  TURN_STEP = 5;
  FIELD_DECIMALS = 1;
  MAX_GAP = 500;
  // A step in a field joins the last one with the same key
  PLACEMENT_MERGE_KEY = 'placement';
  GAP_MERGE_KEY = 'gap';
  HALF_TURN = 180;
  WHEEL_ZOOM_STEP = 1.25;
  BODY_KIND_ITEMS: array[TDrapeBodyKind] of string = (rsBodyFigure, rsBodyNone);
  VIEW_CAPTIONS: array[TDrapeView] of string = (rsMenuFront, rsMenuBack, rsMenuLeft, rsMenuRight, rsMenuTop, rsMenuThreeQuarter);

constructor TDrapeForm.Create(AOwner: TComponent);
var
  Reason: string;
begin
  inherited CreateNew(AOwner);
  Caption := rsDrapeTitle;
  Width := 1100;
  Height := 750;
  Position := poScreenCenter;
  OnCloseQuery := @CloseAsked;
  FDocument := TDrapeDocument.Create;
  FDocument.OnChange := @DocumentChanged;
  BuildMenu;
  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := False;
  FStatus.Panels.Add;
  FStatus.Panels.Add;
  FStatus.Panels[PANEL_MESSAGE].Width := MIN_MESSAGE_WIDTH;
  FTabs := TSideTabs.Create(Self);
  FTabs.Parent := Self;
  FTabs.Align := alRight;
  FTabs.Width := SIDE_WIDTH;
  FColumnSplitter := TSplitter.Create(Self);
  FColumnSplitter.Parent := Self;
  FColumnSplitter.Align := alRight;
  FColumnSplitter.Left := FTabs.Left - FColumnSplitter.Width;
  FTabs.OnCollapsedChange := @TabsCollapsedChange;
  FPatternsSide := FTabs.AddSection('patterns', rsTabPatterns, aiPatternsTab);
  FPiecesSide := FTabs.AddSection('pieces', rsTabPieces, aiPiecesTab);
  FPropertiesSide := FTabs.AddSection(PROPERTIES_SECTION, rsTabProperties, aiPropertiesTab);
  FAssistant := TAssistantPanel.Create(Self);
  FAssistant.Parent := FTabs.AddSection(CLAUDE_SECTION, rsTabClaude, aiClaudeTab);
  FAssistant.Align := alClient;
  FAssistant.Host := TDrapeAssistantHost.Create(FDocument);
  FProblemsSide := FTabs.AddSection(PROBLEMS_SECTION, rsTabProblems, aiProblems, True);
  FProblemsList := TProblemsPanel.Create(Self);
  FProblemsList.Parent := FProblemsSide;
  FProblemsList.Align := alClient;
  FProblemsList.OnSelect := @ProblemSelect;
  FView := TDrapeCanvas.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.Document := FDocument;
  FView.OnSelectionChange := @SelectionChanged;
  FView.OnKeyDown := @ViewKeyDown;
  FRowParent := ScrollingRows(FPatternsSide);
  BuildPatternsTab;
  FRowParent := FPiecesSide;
  BuildPiecesTab;
  FRowParent := ScrollingRows(FPropertiesSide);
  BuildPropertiesTab;
  FTabs.ActiveKey := UserDrapeTab;
  FDocument.NewEmpty;
  FWatch := TTimer.Create(Self);
  FWatch.Interval := WATCH_MILLISECONDS;
  FWatch.OnTimer := @WatchTick;
  if (ParamCount >= 1) and FileExists(ParamStr(1)) then
    OpenPath(ParamStr(1));
  FAppLink := TAppLink.Start(DRAPE_KIND, @AppLinkMessage, True, Reason);
end;

destructor TDrapeForm.Destroy;
begin
  FreeAndNil(FAppLink);
  // Stops a question in progress, which works on the document
  FAssistant.Host := nil;
  // The view reads the document while it goes
  FView.Document := nil;
  FreeAndNil(FDocument);
  inherited Destroy;
end;

procedure TDrapeForm.BuildMenu;
var
  Bar: TMainMenu;

  function AddMenu(const ACaption: string): TMenuItem;
  begin
    Result := TMenuItem.Create(Bar);
    Result.Caption := ACaption;
    Bar.Items.Add(Result);
  end;

  // A menu command with no icon
  function Plain(AAction: TAction): TAction;
  begin
    AAction.ImageIndex := -1;
    Result := AAction;
  end;

var
  Group, OpenItem: TMenuItem;
  NewAction, OpenAction, ZoomInAction, ZoomOutAction, FitAction: TAction;
  View: TDrapeView;
begin
  Bar := TMainMenu.Create(Self);
  Menu := Bar;
  FCommands := TCommandSet.Create(Self, Bar);
  NewAction := FCommands.NewAction(rsMenuNew, aiNew, @NewClick, CommandShortCut(kcNew));
  OpenAction := FCommands.NewAction(rsMenuOpen, aiOpen, @OpenClick, CommandShortCut(kcOpen));
  FSaveAction := FCommands.NewAction(rsMenuSave, aiSave, @SaveClick, CommandShortCut(kcSave));
  FSaveAsAction := FCommands.NewAction(rsMenuSaveAs, aiSaveAs, @SaveAsClick, CommandShortCut(kcSaveAs));
  FUndoAction := FCommands.NewAction(rsMenuUndo, aiUndo, @UndoClick, CommandShortCut(kcUndo));
  FRedoAction := FCommands.NewAction(rsMenuRedo, aiRedo, @RedoClick, CommandShortCut(kcRedo));
  ZoomInAction := FCommands.NewAction(rsMenuZoomIn, aiZoomIn, @ZoomInClick, CommandShortCut(kcZoomIn));
  ZoomOutAction := FCommands.NewAction(rsMenuZoomOut, aiZoomOut, @ZoomOutClick, CommandShortCut(kcZoomOut));
  FitAction := FCommands.NewAction(rsMenuFit, aiFit, @FitClick, CommandShortCut(kcFit));
  FReloadAction := FCommands.NewAction(rsMenuReload, aiReload, @ReloadClick, CommandShortCut(kcReload));
  FGuessAction := FCommands.NewAction(rsMenuGuess, aiWand, @GuessClick, CommandShortCut(kcGuessPlacements));
  FFlipAction := FCommands.NewAction(rsMenuFlip, aiMirror, @FlipClick);
  FUnplaceAction := FCommands.NewAction(rsMenuUnplace, aiDelete, @UnplaceClick);
  FBlenderAction := FCommands.NewAction(rsMenuBlender, aiDrape, @BlenderClick);

  Group := AddMenu(rsMenuFile);
  FCommands.AddMenuItem(Group, NewAction);
  OpenItem := FCommands.AddMenuItem(Group, OpenAction);
  FRecent := TRecentMenu.Create(Self, Group, OpenItem, rlDrapes, @RecentOpen);
  FCommands.AddMenuItem(Group, FSaveAction);
  FCommands.AddMenuItem(Group, FSaveAsAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FBlenderAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuQuit, aiQuit, @QuitClick, CommandShortCut(kcQuit)));
  Group := AddMenu(rsMenuEdit);
  FCommands.AddMenuItem(Group, FUndoAction);
  FCommands.AddMenuItem(Group, FRedoAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuPreferences, aiPreferences, @PreferencesClick, CommandShortCut(kcPreferences)));
  Group := AddMenu(rsMenuView);
  FCommands.AddMenuItem(Group, ZoomInAction);
  FCommands.AddMenuItem(Group, ZoomOutAction);
  FCommands.AddMenuItem(Group, FitAction);
  Group.AddSeparator;
  for View := Low(TDrapeView) to High(TDrapeView) do
    FCommands.AddMenuItem(Group, Plain(FCommands.NewAction(VIEW_CAPTIONS[View], Low(TAppIcon), @ViewClick, 0, Ord(View))));
  FPerspectiveAction := Plain(FCommands.NewAction(rsMenuPerspective, Low(TAppIcon), @PerspectiveClick));
  FPerspectiveAction.AutoCheck := True;
  FCommands.AddMenuItem(Group, FPerspectiveAction);
  Group.AddSeparator;
  FCommands.AddMenuItem(Group, FReloadAction);
  Group := AddMenu(rsMenuPieces);
  FCommands.AddMenuItem(Group, FGuessAction);
  FCommands.AddMenuItem(Group, FFlipAction);
  FCommands.AddMenuItem(Group, FUnplaceAction);
  Group := AddMenu(rsMenuHelp);
  FCommands.AddMenuItem(Group, FCommands.NewAction(rsMenuUserGuide, aiUserGuide, @UserGuideClick));
  FCommands.AddMenuItem(Group, FCommands.NewAction(Format(rsMenuAbout, [rsDrapeTitle]), aiAbout, @AboutClick));

  FCommands.AddButton(NewAction);
  FCommands.AddButton(OpenAction);
  FCommands.AddButton(FSaveAction);
  FCommands.AddDivider;
  FCommands.AddButton(FUndoAction);
  FCommands.AddButton(FRedoAction);
  FCommands.AddDivider;
  FCommands.AddButton(ZoomInAction);
  FCommands.AddButton(ZoomOutAction);
  FCommands.AddButton(FitAction);
  FCommands.AddButton(FReloadAction);
  FCommands.AddDivider;
  FCommands.AddButton(FGuessAction);
  FCommands.AddButton(FFlipAction);
  FCommands.AddButton(FUnplaceAction);
  FCommands.AddDivider;
  FCommands.AddButton(FBlenderAction);
end;

function TDrapeForm.ScrollingRows(Side: TWinControl): TScrollBox;
begin
  Result := TScrollBox.Create(Self);
  Result.Parent := Side;
  Result.Align := alClient;
  Result.BorderStyle := bsNone;
  Result.HorzScrollBar.Visible := False;
end;

procedure TDrapeForm.PlaceRow(Row: TControl);
begin
  Inc(FNextRowTop, SIDE_ROW_STEP);
  Row.Top := FNextRowTop;
  Row.Align := alTop;
  Row.BorderSpacing.Left := ControlGap;
  Row.BorderSpacing.Right := ControlGap;
  Row.BorderSpacing.Top := ControlGap;
  Row.Parent := FRowParent;
end;

procedure TDrapeForm.BeginGroup(const ACaption: string);
var
  Group: TGroupBox;
begin
  EndGroup;
  Group := TGroupBox.Create(Self);
  Group.Caption := ACaption;
  Group.AutoSize := True;
  PlaceRow(Group);
  SpaceChildren(Group);
  FGroupOuter := FRowParent;
  FRowParent := Group;
end;

procedure TDrapeForm.EndGroup;
begin
  if Assigned(FGroupOuter) then
    FRowParent := FGroupOuter;
  FGroupOuter := nil;
end;

function TDrapeForm.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Result.WordWrap := True;
  Result.BorderSpacing.Top := ControlGap;
  PlaceRow(Result);
end;

function TDrapeForm.AddButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Caption := ACaption;
  Result.BorderSpacing.Top := ControlGap;
  Result.OnClick := AHandler;
  PlaceRow(Result);
end;

function TDrapeForm.AddSpin(const ACaption: string; AMin, AMax, AIncrement: double): TFloatSpinEdit;
begin
  AddLabel(ACaption);
  Result := TFloatSpinEdit.Create(Self);
  PlaceRow(Result);
  Result.DecimalPlaces := FIELD_DECIMALS;
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Increment := AIncrement;
end;

procedure TDrapeForm.BuildPatternsTab;
var
  Kind: TDrapeBodyKind;
begin
  BeginGroup(rsPatternsLabel);
  FSourceBox := TListBox.Create(Self);
  PlaceRow(FSourceBox);
  FSourceBox.Height := LIST_HEIGHT;
  AddButton(rsAddPattern, @AddSourceClick);
  FRemoveSourceButton := AddButton(rsRemovePattern, @RemoveSourceClick);
  BeginGroup(rsBodyGroup);
  FBodyKindBox := TComboBox.Create(Self);
  PlaceRow(FBodyKindBox);
  FBodyKindBox.Style := csDropDownList;
  for Kind := Low(TDrapeBodyKind) to High(TDrapeBodyKind) do
    FBodyKindBox.Items.Add(BODY_KIND_ITEMS[Kind]);
  FBodyKindBox.OnChange := @BodyKindChange;
  AddLabel(rsBodySet);
  FBodySetLabel := AddLabel('');
  FBodySetButton := AddButton(rsBodyChooseSet, @BodySetClick);
  FBodyPatternSetButton := AddButton(rsBodyPatternSet, @BodyPatternSetClick);
  AddLabel(rsBodySize);
  FBodySizeBox := TComboBox.Create(Self);
  PlaceRow(FBodySizeBox);
  FBodySizeBox.Style := csDropDownList;
  FBodySizeBox.OnChange := @BodySizeChange;
  FGapEdit := AddSpin(rsGap, 0, MAX_GAP, 1);
  FGapEdit.OnChange := @GapChange;
  EndGroup;
end;

procedure TDrapeForm.BuildPiecesTab;
var
  Advice: TLabel;
begin
  Advice := TLabel.Create(Self);
  Advice.Parent := FPiecesSide;
  Advice.Align := alTop;
  Advice.WordWrap := True;
  Advice.Caption := rsPiecesHint;
  Advice.BorderSpacing.Around := ControlGap;
  FPieceBox := TListBox.Create(Self);
  FPieceBox.Parent := FPiecesSide;
  FPieceBox.Align := alClient;
  FPieceBox.BorderSpacing.Around := ControlGap;
  FPieceBox.OnClick := @PieceBoxClick;
  FPieceBox.OnDblClick := @PieceBoxDoubleClick;
end;

procedure TDrapeForm.BuildPropertiesTab;
const
  AXIS_CAPTIONS: array[0..2] of string = (rsAxisX, rsAxisY, rsAxisZ);
  TURN_CAPTIONS: array[0..2] of string = (rsTurnX, rsTurnY, rsTurnZ);
var
  Axis: integer;
begin
  FSelectionLabel := AddLabel(rsNothingSelected);
  BeginGroup(rsPosition);
  for Axis := 0 to 2 do
  begin
    FPositionEdits[Axis] := AddSpin(AXIS_CAPTIONS[Axis], -MAX_POSITION, MAX_POSITION, POSITION_STEP);
    FPositionEdits[Axis].OnChange := @PlacementEditChange;
  end;
  BeginGroup(rsRotation);
  for Axis := 0 to 2 do
  begin
    FRotationEdits[Axis] := AddSpin(TURN_CAPTIONS[Axis], -HALF_TURN, HALF_TURN, TURN_STEP);
    FRotationEdits[Axis].OnChange := @PlacementEditChange;
  end;
  BeginGroup(rsSeamsGroup);
  FSeamBox := TListBox.Create(Self);
  PlaceRow(FSeamBox);
  FSeamBox.Height := LIST_HEIGHT;
  FSeamBox.OnClick := @SeamBoxClick;
  FSeamBox.OnDblClick := @AlignClick;
  FAlignButton := AddButton(rsAlignToSeam, @AlignClick);
  FFoldButton := AddButton(rsFoldOverSeam, @AlignClick);
  FFoldButton.Tag := 1;
  EndGroup;
end;

procedure TDrapeForm.DocumentChanged(Sender: TObject);
begin
  FView.Invalidate;
  RefreshControls;
end;

procedure TDrapeForm.SelectionChanged(Sender: TObject);
begin
  RefreshPiecesTab;
  RefreshPropertiesTab;
  RefreshCommands;
end;

procedure TDrapeForm.RefreshControls;
var
  FileTitle: string;
begin
  // The view keeps an index, which a change may have taken away
  FView.Selected := FView.Selected;
  FileTitle := ExtractFileName(FDocument.Drape.FileName);
  if FileTitle = '' then
    Caption := rsDrapeTitle
  else
    Caption := Format(rsDrapeTitleFile, [MODIFIED_MARK[FDocument.Modified], FileTitle]);
  FRefreshing := True;
  try
    RefreshPatternsTab;
    RefreshPiecesTab;
    RefreshPropertiesTab;
  finally
    FRefreshing := False;
  end;
  RefreshProblems;
  RefreshCommands;
end;

procedure TDrapeForm.RefreshPatternsTab;
var
  Keep, Index: integer;
  Source: TPatternSource;
  Drape: TDrape;
  SizeSet: boolean;
begin
  Drape := FDocument.Drape;
  Keep := Max(FSourceBox.ItemIndex, 0);
  FSourceBox.Items.BeginUpdate;
  try
    FSourceBox.Items.Clear;
    for Source in Drape.Sources do
      FSourceBox.Items.Add(ExtractFileName(Source.PatternFile));
  finally
    FSourceBox.Items.EndUpdate;
  end;
  FSourceBox.ItemIndex := Min(Keep, FSourceBox.Items.Count - 1);
  FRemoveSourceButton.Enabled := FSourceBox.ItemIndex >= 0;
  FBodyKindBox.ItemIndex := Ord(Drape.Body.Kind);
  if Drape.Body.MeasurementFile = '' then
    FBodySetLabel.Caption := rsBodySetOfPattern
  else
    FBodySetLabel.Caption := ExtractFileName(Drape.Body.MeasurementFile);
  FBodySetButton.Enabled := Drape.Body.Kind <> bkNone;
  FBodyPatternSetButton.Enabled := (Drape.Body.Kind <> bkNone) and (Drape.Body.MeasurementFile <> '');
  // The sizes of the set the body reads, with the pattern's own first
  FBodySizeBox.Items.Clear;
  FBodySizeBox.Items.Add(rsBodySizeOfPattern);
  if (Drape.Body.MeasurementFile = '') and (Drape.Sources.Count > 0) and Assigned(Drape.Sources[0].Measurements) then
    for Index := 0 to Drape.Sources[0].Measurements.SizeCount - 1 do
      FBodySizeBox.Items.Add(Drape.Sources[0].Measurements.Sizes[Index]);
  SizeSet := (Drape.Body.Size <> '') and (FBodySizeBox.Items.IndexOf(Drape.Body.Size) > 0);
  if Drape.Body.Size = '' then
    FBodySizeBox.ItemIndex := 0
  else if SizeSet then
    FBodySizeBox.ItemIndex := FBodySizeBox.Items.IndexOf(Drape.Body.Size)
  else
    FBodySizeBox.ItemIndex := FBodySizeBox.Items.Add(Drape.Body.Size);
  FBodySizeBox.Enabled := (Drape.Body.Kind <> bkNone) and (FBodySizeBox.Items.Count > 1);
  FGapEdit.Value := Drape.Gap;
end;

function TDrapeForm.CopyCaption(const Copy: TDrapePieceCopy): string;
var
  Piece: TPieceObject;
  Source: TPatternSource;
begin
  Result := Copy.PieceKey;
  Source := FDocument.Drape.FindSource(Copy.SourceId);
  if not Assigned(Source) or not FDocument.Drape.FindPiece(Copy, Piece) then
    Exit;
  if Piece.CutCount > 1 then
    Result := Format(rsCopyCaption, [ChangeFileExt(ExtractFileName(Source.PatternFile), ''), Piece.DisplayName, Copy.Copy, Piece.CutCount])
  else
    Result := Format(rsCopyCaptionOne, [ChangeFileExt(ExtractFileName(Source.PatternFile), ''), Piece.DisplayName]);
end;

procedure TDrapeForm.RefreshPiecesTab;
var
  Item: TDrapeItem;
  Copy: TDrapePieceCopy;
  Selected: integer;
begin
  FPieceCopies := nil;
  Selected := -1;
  FPieceBox.Items.BeginUpdate;
  try
    FPieceBox.Items.Clear;
    for Item in FDocument.Drape.Items do
    begin
      if FDocument.Drape.IndexOf(Item.Piece) = FView.Selected then
        Selected := FPieceBox.Items.Count;
      FPieceBox.Items.Add(Format(rsPlaced, [CopyCaption(Item.Piece)]));
      Insert(Item.Piece, FPieceCopies, Length(FPieceCopies));
    end;
    for Copy in FDocument.Drape.Unplaced do
    begin
      FPieceBox.Items.Add(Format(rsNotPlaced, [CopyCaption(Copy)]));
      Insert(Copy, FPieceCopies, Length(FPieceCopies));
    end;
  finally
    FPieceBox.Items.EndUpdate;
  end;
  FPieceBox.ItemIndex := Selected;
end;

procedure TDrapeForm.RefreshPropertiesTab;
var
  Axis, Keep: integer;
  Seam: TSeamObject;
  Placement: TDrapePlacement;
  Copy: TDrapePieceCopy;
  Has: boolean;
  Values: array[0..2] of double;
begin
  Has := SelectedCopy(Copy);
  FRefreshing := True;
  try
    if Has then
    begin
      FSelectionLabel.Caption := CopyCaption(Copy);
      Placement := FDocument.Drape.Items[FView.Selected].Placement;
    end
    else
    begin
      FSelectionLabel.Caption := rsNothingSelected;
      Placement := Default(TDrapePlacement);
    end;
    Values[0] := Placement.Position.X;
    Values[1] := Placement.Position.Y;
    Values[2] := Placement.Position.Z;
    for Axis := 0 to 2 do
    begin
      FPositionEdits[Axis].Value := Values[Axis];
      FPositionEdits[Axis].Enabled := Has;
    end;
    Values[0] := Placement.Rotation.X;
    Values[1] := Placement.Rotation.Y;
    Values[2] := Placement.Rotation.Z;
    for Axis := 0 to 2 do
    begin
      FRotationEdits[Axis].Value := Values[Axis];
      FRotationEdits[Axis].Enabled := Has;
    end;
    FSeams := nil;
    if Has then
      FSeams := FDocument.Drape.AlignableSeams(Copy);
    Keep := FSeamBox.ItemIndex;
    FSeamBox.Items.BeginUpdate;
    try
      FSeamBox.Items.Clear;
      for Seam in FSeams do
        FSeamBox.Items.Add(Seam.DisplayName);
      if Has and (Length(FSeams) = 0) then
        FSeamBox.Items.Add(rsSeamsNone);
    finally
      FSeamBox.Items.EndUpdate;
    end;
    if Length(FSeams) > 0 then
      FSeamBox.ItemIndex := EnsureRange(Keep, 0, High(FSeams));
    FSeamBox.Enabled := Length(FSeams) > 0;
    FAlignButton.Enabled := Length(FSeams) > 0;
    FFoldButton.Enabled := Length(FSeams) > 0;
  finally
    FRefreshing := False;
  end;
end;

procedure TDrapeForm.RefreshProblems;
var
  Problem: TDrapeProblem;
  Listed: TListedProblemArray;
  Index: integer;
  Shown: string;
begin
  Listed := nil;
  for Problem in Concat(FDocument.Drape.Problems, DrapeSeamProblems(FDocument.Drape)) do
  begin
    Index := Length(Listed);
    SetLength(Listed, Index + 1);
    Listed[Index].Text := Problem.Text;
    Listed[Index].Blocking := False;
    if Problem.Item >= 0 then
      Listed[Index].Key := ITEM_KEY + IntToStr(Problem.Item);
  end;
  FProblemsList.SetProblems(Listed);
  FTabs.SetSectionCount(FProblemsSide, Length(Listed));
  if Length(Listed) = 0 then
  begin
    Shown := rsNoProblems;
    FTabs.SetSectionCaption(FProblemsSide, rsTabProblems);
  end
  else
  begin
    Shown := Format(rsProblemCount, [Length(Listed)]);
    FTabs.SetSectionCaption(FProblemsSide, Format(rsTabProblemsCount, [Length(Listed)]));
  end;
  FStatus.Panels[PANEL_PROBLEMS].Text := Shown;
  FStatus.Panels[PANEL_PROBLEMS].Width := Max(Scale96ToForm(PROBLEMS_PANEL_WIDTH96), FStatus.Canvas.TextWidth(Shown) +
    Scale96ToForm(PANEL_PADDING96));
end;

procedure TDrapeForm.RefreshCommands;
var
  Copy: TDrapePieceCopy;
  HasSelection: boolean;
begin
  HasSelection := SelectedCopy(Copy);
  FSaveAction.Enabled := FDocument.Modified;
  FSaveAsAction.Enabled := FDocument.Modified or (FDocument.Drape.FileName <> '');
  FUndoAction.Enabled := FDocument.CanUndo;
  FRedoAction.Enabled := FDocument.CanRedo;
  if FDocument.CanUndo then
    FUndoAction.Caption := Format(rsMenuUndoNamed, [FDocument.UndoDescription])
  else
    FUndoAction.Caption := rsMenuUndo;
  FReloadAction.Enabled := FDocument.Drape.Sources.Count > 0;
  FGuessAction.Enabled := Length(FDocument.Drape.Unplaced) > 0;
  FFlipAction.Enabled := HasSelection;
  FUnplaceAction.Enabled := HasSelection;
  FBlenderAction.Enabled := Length(FDocument.Drape.Items) > 0;
end;

procedure TDrapeForm.ShowStatus(const AText: string);
begin
  FStatus.Panels[PANEL_MESSAGE].Text := AText;
  FStatus.Panels[PANEL_MESSAGE].Width := Max(MIN_MESSAGE_WIDTH, FStatus.ClientWidth - FStatus.Panels[PANEL_PROBLEMS].Width);
end;

function TDrapeForm.SelectedCopy(out Copy: TDrapePieceCopy): boolean;
begin
  Copy := Default(TDrapePieceCopy);
  Result := (FView.Selected >= 0) and (FView.Selected <= High(FDocument.Drape.Items));
  if Result then
    Copy := FDocument.Drape.Items[FView.Selected].Piece;
end;

procedure TDrapeForm.NewClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if not ConfirmDiscard then
    Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterPattern;
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Dialog.Execute then
      OpenPath(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDrapeForm.OpenClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  if not ConfirmDiscard then
    Exit;
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterOpen;
    if Dialog.Execute then
      OpenPath(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDrapeForm.OpenPath(const Path: string);
var
  Reason: string;
begin
  FView.Selected := -1;
  // A pattern starts a new drape file, which is remembered once it is saved
  if SameText(ExtractFileExt(Path), PATTERN_EXTENSION) then
    FDocument.NewForPattern(Path)
  else if FDocument.Open(Path, Reason) then
    FRecent.Remember(Path)
  else
  begin
    ShowStatus(Reason);
    Exit;
  end;
  FView.FitAll;
end;

procedure TDrapeForm.RecentOpen(Sender: TObject; const FileName: string);
begin
  if ConfirmDiscard then
    OpenPath(FileName);
end;

function TDrapeForm.SaveTo(const FileName: string): boolean;
var
  Reason: string;
begin
  Result := FDocument.Save(FileName, Reason);
  if Result then
    FRecent.Remember(FileName)
  else
    ShowStatus(Reason);
end;

function TDrapeForm.Save: boolean;
begin
  if FDocument.Drape.FileName = '' then
    Result := SaveAs
  else
    Result := SaveTo(FDocument.Drape.FileName);
end;

function TDrapeForm.SaveAs: boolean;
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Filter := rsFilterDrape;
    Dialog.DefaultExt := DRAPE_EXTENSION;
    Dialog.FileName := FDocument.Drape.FileName;
    Result := Dialog.Execute and SaveTo(Dialog.FileName);
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDrapeForm.SaveClick(Sender: TObject);
begin
  Save;
end;

procedure TDrapeForm.SaveAsClick(Sender: TObject);
begin
  SaveAs;
end;

procedure TDrapeForm.QuitClick(Sender: TObject);
begin
  Close;
end;

procedure TDrapeForm.UndoClick(Sender: TObject);
begin
  FView.CancelDrag;
  FDocument.Undo;
end;

procedure TDrapeForm.RedoClick(Sender: TObject);
begin
  FView.CancelDrag;
  FDocument.Redo;
end;

procedure TDrapeForm.PreferencesClick(Sender: TObject);
var
  Preferences: TPreferences;
begin
  if EditPreferences(Self, ptDrape, Preferences) then
  begin
    FAssistant.KeyChanged;
    TellApps(APP_LINK_PREFERENCES, FAppLink);
  end;
end;

// Writes the files Blender needs beside the drape file, then runs Blender on
// them while a window shows how far it is
procedure TDrapeForm.BlenderClick(Sender: TObject);
var
  Preferences: TPreferences;
  Files: TDrapeExportFiles;
  Problems: TDrapeProblemArray;
  Blender, Reason, Script: string;
  Written: boolean;
begin
  FView.CancelDrag;
  if (FDocument.Drape.FileName = '') and not SaveAs then
    Exit;
  Script := TAppPaths.BlenderScriptFile;
  if Script = '' then
  begin
    MessageDlg(rsBlenderNoScript, mtError, [mbOK], 0);
    Exit;
  end;
  Preferences := UserPreferences;
  Files := DrapeExportFiles(DrapeExportTarget(FDocument.Drape.FileName));
  Screen.BeginWaitCursor;
  try
    Written := ExportDrape(FDocument.Drape, Files.Scene, Preferences.DrapeSpacing, Script, Problems, Reason);
  finally
    Screen.EndWaitCursor;
  end;
  if not Written then
  begin
    MessageDlg(Format(rsBlenderExportFailed, [Reason]), mtError, [mbOK], 0);
    Exit;
  end;
  Blender := FindBlender(Preferences.BlenderProgram);
  if Blender = '' then
  begin
    MessageDlg(Format(rsBlenderNotFound, [Files.Script, BLENDER_SCRIPT_VERSION]), mtInformation, [mbOK], 0);
    Exit;
  end;
  DrapeInBlender(Self, Blender, Files, Preferences.DrapeFrames);
end;

procedure TDrapeForm.ZoomInClick(Sender: TObject);
begin
  FView.ZoomBy(WHEEL_ZOOM_STEP);
end;

procedure TDrapeForm.ZoomOutClick(Sender: TObject);
begin
  FView.ZoomBy(1 / WHEEL_ZOOM_STEP);
end;

procedure TDrapeForm.FitClick(Sender: TObject);
begin
  FView.FitAll;
end;

procedure TDrapeForm.ViewClick(Sender: TObject);
begin
  FView.ShowView(TDrapeView(TComponent(Sender).Tag));
end;

procedure TDrapeForm.PerspectiveClick(Sender: TObject);
var
  Camera: TDrapeCamera;
begin
  Camera := FView.Camera;
  Camera.Perspective := FPerspectiveAction.Checked;
  FView.Camera := Camera;
end;

procedure TDrapeForm.ReloadClick(Sender: TObject);
begin
  FDocument.Reload;
end;

procedure TDrapeForm.GuessClick(Sender: TObject);
var
  Placed: integer;
begin
  FDocument.BeginChange(rsGuessChange);
  Placed := FDocument.Drape.GuessPlacements;
  FDocument.EndChange;
  if Placed = 0 then
    ShowStatus(rsNothingToGuess)
  else
    ShowStatus(Format(rsGuessed, [Placed]));
end;

// Half a turn about the piece's own up, so it faces the other way in place
procedure TDrapeForm.FlipClick(Sender: TObject);
var
  Copy: TDrapePieceCopy;
  Placement: TDrapePlacement;
begin
  if not SelectedCopy(Copy) then
    Exit;
  Placement := FDocument.Drape.Items[FView.Selected].Placement;
  Placement.Rotation := Mat3ToEuler(Mat3Then(PlacementMatrix(Placement), Mat3TurnZ(HALF_TURN)));
  FDocument.BeginChange(rsFlipChange);
  FDocument.Drape.Place(Copy, Placement);
  FDocument.EndChange;
end;

procedure TDrapeForm.UnplaceClick(Sender: TObject);
var
  Copy: TDrapePieceCopy;
begin
  if not SelectedCopy(Copy) then
    Exit;
  FView.Selected := -1;
  FDocument.BeginChange(rsUnplaceChange);
  FDocument.Drape.Unplace(Copy);
  FDocument.EndChange;
end;

procedure TDrapeForm.AboutClick(Sender: TObject);
begin
  ShowAboutDialog(Self, rsDrapeTitle, rsAboutSummary);
end;

procedure TDrapeForm.UserGuideClick(Sender: TObject);
begin
  ShowUserGuide;
end;

procedure TDrapeForm.AddSourceClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterPattern;
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if not Dialog.Execute then
      Exit;
    FDocument.BeginChange(rsAddPatternChange);
    FDocument.Drape.AddSource(FDocument.Drape.StoredPath(Dialog.FileName), '', '');
    FDocument.Drape.LoadSources;
    FDocument.Drape.GuessPlacements;
    FDocument.EndChange;
    FView.FitAll;
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDrapeForm.RemoveSourceClick(Sender: TObject);
var
  Index: integer;
begin
  Index := FSourceBox.ItemIndex;
  if (Index < 0) or (Index >= FDocument.Drape.Sources.Count) then
    Exit;
  FView.Selected := -1;
  FDocument.BeginChange(rsRemovePatternChange);
  FDocument.Drape.RemoveSource(FDocument.Drape.Sources[Index]);
  FDocument.EndChange;
end;

procedure TDrapeForm.BodyKindChange(Sender: TObject);
begin
  if FRefreshing or (FBodyKindBox.ItemIndex < 0) then
    Exit;
  FDocument.BeginChange(rsBodyChange);
  FDocument.Drape.Body.Kind := TDrapeBodyKind(FBodyKindBox.ItemIndex);
  FDocument.Drape.LoadBody;
  FDocument.EndChange;
end;

procedure TDrapeForm.BodySetClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Filter := rsFilterMeasurements;
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if not Dialog.Execute then
      Exit;
    FDocument.BeginChange(rsBodyChange);
    FDocument.Drape.Body.MeasurementFile := FDocument.Drape.StoredPath(Dialog.FileName);
    FDocument.Drape.Body.Size := '';
    FDocument.Drape.LoadBody;
    FDocument.EndChange;
  finally
    FreeAndNil(Dialog);
  end;
end;

procedure TDrapeForm.BodyPatternSetClick(Sender: TObject);
begin
  FDocument.BeginChange(rsBodyChange);
  FDocument.Drape.Body.MeasurementFile := '';
  FDocument.Drape.Body.Size := '';
  FDocument.Drape.LoadBody;
  FDocument.EndChange;
end;

procedure TDrapeForm.BodySizeChange(Sender: TObject);
begin
  if FRefreshing or (FBodySizeBox.ItemIndex < 0) then
    Exit;
  FDocument.BeginChange(rsBodyChange);
  if FBodySizeBox.ItemIndex = 0 then
    FDocument.Drape.Body.Size := ''
  else
    FDocument.Drape.Body.Size := FBodySizeBox.Text;
  FDocument.EndChange;
end;

procedure TDrapeForm.GapChange(Sender: TObject);
begin
  if FRefreshing then
    Exit;
  FDocument.BeginChange(rsGapChange);
  FDocument.Drape.Gap := FGapEdit.Value;
  FDocument.EndChange(GAP_MERGE_KEY);
end;

procedure TDrapeForm.PieceBoxClick(Sender: TObject);
var
  Index: integer;
begin
  Index := FPieceBox.ItemIndex;
  if (Index < 0) or (Index > High(FPieceCopies)) then
    Exit;
  FView.Selected := FDocument.Drape.IndexOf(FPieceCopies[Index]);
end;

// Places an unplaced piece by a guess, as Guess Placements would, but only it
procedure TDrapeForm.PieceBoxDoubleClick(Sender: TObject);
var
  Index: integer;
  Copy: TDrapePieceCopy;
  Others: TDrapePieceCopyArray;
  Other: TDrapePieceCopy;
begin
  Index := FPieceBox.ItemIndex;
  if (Index < 0) or (Index > High(FPieceCopies)) or (FDocument.Drape.IndexOf(FPieceCopies[Index]) >= 0) then
    Exit;
  Copy := FPieceCopies[Index];
  Others := FDocument.Drape.Unplaced;
  FDocument.BeginChange(rsPlaceChange);
  FDocument.Drape.GuessPlacements;
  // Only the one asked for stays placed
  for Other in Others do
    if (Other.SourceId <> Copy.SourceId) or (Other.PieceKey <> Copy.PieceKey) or (Other.Copy <> Copy.Copy) then
      FDocument.Drape.Unplace(Other);
  FDocument.EndChange;
  FView.Selected := FDocument.Drape.IndexOf(Copy);
end;

procedure TDrapeForm.PlacementEditChange(Sender: TObject);
var
  Copy: TDrapePieceCopy;
  Placement: TDrapePlacement;
begin
  if FRefreshing or not SelectedCopy(Copy) then
    Exit;
  Placement.Position := Vec3(FPositionEdits[0].Value, FPositionEdits[1].Value, FPositionEdits[2].Value);
  Placement.Rotation := Vec3(FRotationEdits[0].Value, FRotationEdits[1].Value, FRotationEdits[2].Value);
  FDocument.BeginChange(rsPlaceChange);
  FDocument.Drape.Place(Copy, Placement);
  FDocument.EndChange(PLACEMENT_MERGE_KEY);
end;

// Align (Tag 0) lays the piece beside its partner across the seam; Fold Over
// (Tag 1) turns it over about the seam onto the partner
procedure TDrapeForm.AlignClick(Sender: TObject);
var
  Copy: TDrapePieceCopy;
  Placement: TDrapePlacement;
  Index: integer;
begin
  Index := FSeamBox.ItemIndex;
  if not SelectedCopy(Copy) or (Index < 0) or (Index > High(FSeams)) then
    Exit;
  if not FDocument.Drape.AlignToSeam(Copy, FSeams[Index], TComponent(Sender).Tag = 1, Placement) then
    Exit;
  FDocument.BeginChange(rsAlignChange);
  FDocument.Drape.Place(Copy, Placement);
  FDocument.EndChange;
end;

procedure TDrapeForm.SeamBoxClick(Sender: TObject);
begin
  RefreshCommands;
end;

procedure TDrapeForm.ProblemSelect(Sender: TObject; const Key: string);
begin
  if StartsStr(ITEM_KEY, Key) then
    FView.Selected := StrToIntDef(Copy(Key, Length(ITEM_KEY) + 1, Length(Key)), -1);
end;

procedure TDrapeForm.ViewKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key in [VK_DELETE, VK_BACK]) and (Shift = []) then
  begin
    UnplaceClick(Self);
    Key := 0;
  end;
end;

procedure TDrapeForm.TabsCollapsedChange(Sender: TObject);
begin
  FColumnSplitter.Visible := not FTabs.Collapsed;
  FColumnSplitter.Left := FTabs.Left - FColumnSplitter.Width;
end;

procedure TDrapeForm.WatchTick(Sender: TObject);
var
  Names: string;
begin
  Names := FDocument.CheckSources;
  if Names <> '' then
    ShowStatus(Format(rsReloaded, [Names]));
end;

// Comes to the front when asked to show the drape file open here. Nothing on
// screen reads the preferences yet.
function TDrapeForm.AppLinkMessage(const Method: string; Params: TJSONObject): boolean;
var
  DrapeFile: string;
begin
  if Method = APP_LINK_PREFERENCES then
  begin
    FAssistant.KeyChanged;
    Exit(True);
  end;
  Result := (Method = APP_LINK_SHOW) and GetJSONString(Params, APP_LINK_DRAPE_PARAM, DrapeFile) and
    (FDocument.Drape.FileName <> '') and SameFileName(ExpandFileName(FDocument.Drape.FileName), ExpandFileName(DrapeFile));
  if not Result then
    Exit;
  if WindowState = wsMinimized then
    WindowState := wsNormal;
  Application.Restore;
  ShowOnTop;
  Application.BringToFront;
end;

procedure TDrapeForm.CloseAsked(Sender: TObject; var CanClose: boolean);
var
  Err: string;
begin
  CanClose := ConfirmDiscard;
  if CanClose then
    SaveUserDrapeTab(FTabs.ActiveKey, Err);
end;

function TDrapeForm.ConfirmDiscard: boolean;
begin
  if not FDocument.Modified then
    Exit(True);
  case AskSaveChanges(ExtractFileName(FDocument.Drape.FileName)) of
    mrYes: Result := Save;
    mrNo: Result := True;
    else
      Result := False;
  end;
end;

end.
