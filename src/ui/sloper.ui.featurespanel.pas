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

// The Features tab: sewing details to apply to the pattern in one step: a
// zip along the selected edge of a piece, a dart in it, or a hem along the
// selected edges. Apply adds
// ordinary objects, as one undo step (Sloper.Core.Features).
unit Sloper.UI.FeaturesPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Sloper.Document.PatternDocument, Sloper.Core.Features;

type
  TFeaturesMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  TFeaturesPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    // The pattern the fields' starting values were set for
    FGeneration: integer;
    // The one edge and the one point selected, if any
    FEdgeKey, FPointKey: string;
    // Every edge selected, when nothing else is
    FEdgeKeys: TStringArray;
    FKinds: TListBox;
    // The group the next control goes in, and how far down it
    FGroup: TGroupBox;
    FNextTop: integer;
    FZipGroup: TGroupBox;
    FEdgeLabel, FLengthLabel, FAllowanceLabel, FStitchLabel, FShieldLabel: TLabel;
    FStyleBox, FFromBox: TComboBox;
    FLengthEdit, FAllowanceEdit, FStitchEdit, FShieldEdit: TEdit;
    FApply: TButton;
    FDartGroup: TGroupBox;
    FDartEdgeLabel, FDartPositionLabel, FDartWidthLabel, FDartDepthLabel, FDartHoleLabel: TLabel;
    FDartFromBox, FDartFoldBox: TComboBox;
    FDartPositionEdit, FDartWidthEdit, FDartDepthEdit, FDartHoleEdit: TEdit;
    FDartApply: TButton;
    FHemGroup: TGroupBox;
    FHemEdgeLabel, FHemDepthLabel, FHemTurnLabel, FHemStitchLabel: TLabel;
    FHemStyleBox: TComboBox;
    FHemDepthEdit, FHemTurnEdit, FHemStitchEdit: TEdit;
    FHemNotchBox: TCheckBox;
    FHemApply: TButton;
    // The depth the topstitching's distance was last worked out from
    FHemDepth: string;
    FOnMessage: TFeaturesMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    function AddGroup(const ACaption: string): TGroupBox;
    function AddLabel(const ACaption: string): TLabel;
    function AddEdit: TEdit;
    function AddChoices: TComboBox;
    function AddApply(Below: TControl; OnApply: TNotifyEvent): TButton;
    procedure AddNote(Below: TControl; const ACaption: string);
    procedure Place(Control: TControl);
    procedure BuildZip;
    procedure BuildDart;
    procedure BuildHem;
    procedure HemStartingValues;
    procedure RefreshHem;
    function EdgeNames: string;
    procedure HemStyleChange(Sender: TObject);
    procedure HemDepthChange(Sender: TObject);
    procedure HemApplyClick(Sender: TObject);
    procedure StartingValues;
    procedure Refresh;
    procedure RefreshZip(Edge: TObject);
    procedure RefreshDart(Edge: TObject);
    procedure KindClick(Sender: TObject);
    procedure StyleChange(Sender: TObject);
    // The style's own captions and which fields it takes
    procedure ShowStyle;
    procedure ApplyClick(Sender: TObject);
    procedure DartApplyClick(Sender: TObject);
    procedure Say(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // The canvas's selection: a zip goes along one selected edge, a dart
    // into one, to a selected point if there is one, and a hem along all
    procedure ShowSelection(const Keys: TStringArray);
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TFeaturesMessageEvent read FOnMessage write FOnMessage;
  end;

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
  rsFeaturesApply = '&Apply';
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

implementation

uses
  Graphics, Math, Sloper.Core.Draft, Sloper.Core.Units, Sloper.UI.Spacing;

const
  // The list of features, about four rows, at 96 pixels per inch
  KIND_LIST_HEIGHT96 = 90;
  KIND_ZIP = 0;
  KIND_DART = 1;
  KIND_HEM = 2;

constructor TFeaturesPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  SpaceChildren(Self);
  FGeneration := -1;
  FKinds := TListBox.Create(Self);
  FKinds.Parent := Self;
  FKinds.Align := alTop;
  FKinds.Items.Add(rsFeatureZip);
  FKinds.Items.Add(rsFeatureDart);
  FKinds.Items.Add(rsFeatureHem);
  FKinds.ItemIndex := KIND_ZIP;
  FKinds.Height := Scale96ToScreen(KIND_LIST_HEIGHT96);
  FKinds.OnClick := @KindClick;
  BuildZip;
  BuildDart;
  BuildHem;
  KindClick(nil);
end;

destructor TFeaturesPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

function TFeaturesPanel.AddGroup(const ACaption: string): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := Self;
  Result.Align := alClient;
  Result.Caption := ACaption;
  SpaceChildren(Result);
  FGroup := Result;
  FNextTop := 0;
end;

// A caption over the field after it, both down the group in order
function TFeaturesPanel.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Place(Result);
end;

function TFeaturesPanel.AddEdit: TEdit;
begin
  Result := TEdit.Create(Self);
  Place(Result);
end;

function TFeaturesPanel.AddChoices: TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Style := csDropDownList;
  Place(Result);
end;

function TFeaturesPanel.AddApply(Below: TControl; OnApply: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Caption := rsFeaturesApply;
  Result.AutoSize := True;
  Result.OnClick := OnApply;
  Place(Result);
  Result.Align := alNone;
  Result.Anchors := [akLeft, akTop];
  Result.AnchorSide[akTop].Control := Below;
  Result.AnchorSide[akTop].Side := asrBottom;
  Result.BorderSpacing.Top := ControlGap;
end;

procedure TFeaturesPanel.AddNote(Below: TControl; const ACaption: string);
var
  Note: TLabel;
begin
  Note := TLabel.Create(Self);
  Note.Parent := FGroup;
  Note.WordWrap := True;
  Note.AutoSize := True;
  Note.Caption := ACaption;
  Note.Anchors := [akLeft, akRight, akTop];
  Note.AnchorSide[akLeft].Control := FGroup;
  Note.AnchorSide[akRight].Control := FGroup;
  Note.AnchorSide[akRight].Side := asrBottom;
  Note.AnchorSide[akTop].Control := Below;
  Note.AnchorSide[akTop].Side := asrBottom;
  Note.BorderSpacing.Top := ControlGap;
end;

procedure TFeaturesPanel.Place(Control: TControl);
begin
  Control.Parent := FGroup;
  Control.Align := alTop;
  // Each below the one before
  Inc(FNextTop, Control.Height + 1);
  Control.Top := FNextTop;
end;

procedure TFeaturesPanel.BuildZip;
begin
  FZipGroup := AddGroup(rsFeatureZip);
  FEdgeLabel := AddLabel('');
  FEdgeLabel.Font.Style := [fsBold];
  AddLabel(rsFeaturesStyle);
  FStyleBox := AddChoices;
  FStyleBox.Items.Add(rsFeaturesCentred);
  FStyleBox.Items.Add(rsFeaturesInvisible);
  FStyleBox.Items.Add(rsFeaturesLapped);
  FStyleBox.Items.Add(rsFeaturesFlyFront);
  FStyleBox.ItemIndex := 0;
  FStyleBox.OnChange := @StyleChange;
  FLengthLabel := AddLabel('');
  FLengthEdit := AddEdit;
  AddLabel(rsFeaturesFrom);
  FFromBox := AddChoices;
  FAllowanceLabel := AddLabel('');
  FAllowanceEdit := AddEdit;
  FStitchLabel := AddLabel('');
  FStitchEdit := AddEdit;
  FShieldLabel := AddLabel('');
  FShieldEdit := AddEdit;
  FApply := AddApply(FShieldEdit, @ApplyClick);
  AddNote(FApply, rsFeaturesZipNote);
end;

procedure TFeaturesPanel.BuildDart;
begin
  FDartGroup := AddGroup(rsFeatureDart);
  FDartEdgeLabel := AddLabel('');
  FDartEdgeLabel.Font.Style := [fsBold];
  FDartEdgeLabel.WordWrap := True;
  FDartPositionLabel := AddLabel('');
  FDartPositionEdit := AddEdit;
  AddLabel(rsFeaturesFrom);
  FDartFromBox := AddChoices;
  FDartWidthLabel := AddLabel('');
  FDartWidthEdit := AddEdit;
  FDartDepthLabel := AddLabel('');
  FDartDepthEdit := AddEdit;
  FDartHoleLabel := AddLabel('');
  FDartHoleEdit := AddEdit;
  AddLabel(rsFeaturesDartFold);
  FDartFoldBox := AddChoices;
  FDartApply := AddApply(FDartFoldBox, @DartApplyClick);
  AddNote(FDartApply, rsFeaturesDartNote);
end;

procedure TFeaturesPanel.BuildHem;
begin
  FHemGroup := AddGroup(rsFeatureHem);
  FHemEdgeLabel := AddLabel('');
  FHemEdgeLabel.Font.Style := [fsBold];
  FHemEdgeLabel.WordWrap := True;
  AddLabel(rsFeaturesStyle);
  FHemStyleBox := AddChoices;
  // In the order of THemStyle
  FHemStyleBox.Items.Add(rsFeaturesHemSingle);
  FHemStyleBox.Items.Add(rsFeaturesHemDouble);
  FHemStyleBox.Items.Add(rsFeaturesHemNarrow);
  FHemStyleBox.Items.Add(rsFeaturesHemBlind);
  FHemStyleBox.ItemIndex := 0;
  FHemStyleBox.OnChange := @HemStyleChange;
  FHemDepthLabel := AddLabel('');
  FHemDepthEdit := AddEdit;
  FHemDepthEdit.OnChange := @HemDepthChange;
  FHemTurnLabel := AddLabel('');
  FHemTurnEdit := AddEdit;
  FHemStitchLabel := AddLabel('');
  FHemStitchEdit := AddEdit;
  FHemNotchBox := TCheckBox.Create(Self);
  FHemNotchBox.Caption := rsFeaturesHemNotches;
  FHemNotchBox.Checked := True;
  Place(FHemNotchBox);
  FHemApply := AddApply(FHemNotchBox, @HemApplyClick);
  AddNote(FHemApply, rsFeaturesHemNote);
end;

procedure TFeaturesPanel.KindClick(Sender: TObject);
begin
  FZipGroup.Visible := FKinds.ItemIndex = KIND_ZIP;
  FDartGroup.Visible := FKinds.ItemIndex = KIND_DART;
  FHemGroup.Visible := FKinds.ItemIndex = KIND_HEM;
end;

procedure TFeaturesPanel.SetDocument(ADocument: TPatternDocument);
begin
  if Assigned(FDocument) then
    FDocument.RemoveListener(@DocumentChanged);
  FDocument := ADocument;
  if Assigned(FDocument) then
    FDocument.AddListener(@DocumentChanged);
  Refresh;
end;

procedure TFeaturesPanel.DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
begin
  Refresh;
end;

procedure TFeaturesPanel.ShowSelection(const Keys: TStringArray);
var
  Key: string;
  Node: TObject;
  Edges, Points: integer;
begin
  FEdgeKey := '';
  FPointKey := '';
  FEdgeKeys := nil;
  Edges := 0;
  Points := 0;
  if Assigned(FDocument) then
    for Key in Keys do
    begin
      Node := FDocument.Pattern.FindNode(Key);
      if Node is TEdgeObject then
      begin
        FEdgeKey := Key;
        Insert(Key, FEdgeKeys, Length(FEdgeKeys));
        Inc(Edges);
      end
      else if Node is TPointObject then
      begin
        FPointKey := Key;
        Inc(Points);
      end;
    end;
  if Edges <> Length(Keys) then
    FEdgeKeys := nil;
  // One of each at most, and nothing else
  if (Edges <> 1) or (Points > 1) or (Edges + Points <> Length(Keys)) then
  begin
    FEdgeKey := '';
    FPointKey := '';
  end;
  Refresh;
end;

// A new or opened pattern, or another unit, starts the fields again, at the
// chosen style's widths
procedure TFeaturesPanel.StartingValues;
var
  Spec: TZipSpec;
  Dart: TDartSpec;
begin
  Spec := DefaultZip(FDocument.Pattern, '', TZipStyle(Max(FStyleBox.ItemIndex, 0)));
  FLengthEdit.Text := Spec.Length;
  FAllowanceEdit.Text := Spec.Allowance;
  FStitchEdit.Text := Spec.StitchDistance;
  FShieldEdit.Text := Spec.ShieldWidth;
  Dart := DefaultDart(FDocument.Pattern, '');
  FDartPositionEdit.Text := Dart.Position;
  FDartWidthEdit.Text := Dart.Width;
  FDartDepthEdit.Text := Dart.Depth;
  FDartHoleEdit.Text := Dart.HoleInset;
  HemStartingValues;
  FGeneration := FDocument.Generation;
  ShowStyle;
end;

// The hem's fields at the chosen style's starting widths
procedure TFeaturesPanel.HemStartingValues;
var
  Hem: THemSpec;
begin
  Hem := DefaultHem(FDocument.Pattern, [], THemStyle(Max(FHemStyleBox.ItemIndex, 0)));
  FHemDepth := Hem.Depth;
  FHemDepthEdit.Text := Hem.Depth;
  FHemTurnEdit.Text := Hem.TurnUnder;
  FHemStitchEdit.Text := Hem.StitchDistance;
end;

procedure TFeaturesPanel.ShowStyle;
var
  UnitText: string;
  Style: TZipStyle;
begin
  Style := TZipStyle(Max(FStyleBox.ItemIndex, 0));
  UnitText := MEASURE_UNIT_NAMES[muMillimetre];
  if Assigned(FDocument) then
    UnitText := MEASURE_UNIT_NAMES[FDocument.Pattern.Units];
  FLengthLabel.Caption := Format(rsFeaturesLength, [UnitText]);
  if Style = zsFlyFront then
    FAllowanceLabel.Caption := Format(rsFeaturesExtension, [UnitText])
  else
    FAllowanceLabel.Caption := Format(rsFeaturesAllowance, [UnitText]);
  case Style of
    zsLapped: FStitchLabel.Caption := Format(rsFeaturesLap, [UnitText]);
    zsFlyFront: FStitchLabel.Caption := Format(rsFeaturesFly, [UnitText]);
    else
      FStitchLabel.Caption := Format(rsFeaturesStitch, [UnitText]);
  end;
  FShieldLabel.Caption := Format(rsFeaturesShield, [UnitText]);
  FStitchEdit.Enabled := Style <> zsInvisible;
  FStitchLabel.Enabled := FStitchEdit.Enabled;
  FShieldEdit.Enabled := Style = zsFlyFront;
  FShieldLabel.Enabled := FShieldEdit.Enabled;
  FDartPositionLabel.Caption := Format(rsFeaturesDartPosition, [UnitText]);
  FDartWidthLabel.Caption := Format(rsFeaturesDartWidth, [UnitText]);
  FDartHoleLabel.Caption := Format(rsFeaturesDartHole, [UnitText]);
  FHemDepthLabel.Caption := Format(rsFeaturesHemDepth, [UnitText]);
  FHemTurnLabel.Caption := Format(rsFeaturesHemTurnUnder, [UnitText]);
  FHemStitchLabel.Caption := Format(rsFeaturesHemStitch, [UnitText]);
  FHemTurnEdit.Enabled := THemStyle(Max(FHemStyleBox.ItemIndex, 0)) in [hsDouble, hsNarrow];
  FHemTurnLabel.Enabled := FHemTurnEdit.Enabled;
  FHemStitchEdit.Enabled := THemStyle(Max(FHemStyleBox.ItemIndex, 0)) <> hsBlind;
  FHemStitchLabel.Enabled := FHemStitchEdit.Enabled;
end;

function PointName(Document: TPatternDocument; const Key: string): string;
var
  Node: TObject;
begin
  Node := Document.Pattern.FindNode(Key);
  if Node is TDraftObject then
    Result := TDraftObject(Node).DisplayName
  else
    Result := Key;
end;

// The edge's two ends as choices, keeping the one chosen
procedure ShowEnds(Box: TComboBox; Document: TPatternDocument; Edge: TEdgeObject; const Caption: string);
var
  Index: integer;
begin
  Index := Max(Box.ItemIndex, 0);
  Box.Items.Clear;
  if not Assigned(Edge) then
    Exit;
  Box.Items.Add(Format(Caption, [PointName(Document, Edge.StartKey)]));
  Box.Items.Add(Format(Caption, [PointName(Document, Edge.EndKey)]));
  Box.ItemIndex := Index;
end;

procedure TFeaturesPanel.Refresh;
var
  Node: TObject;
  Edge: TEdgeObject;
begin
  Edge := nil;
  if Assigned(FDocument) then
  begin
    if FGeneration <> FDocument.Generation then
      StartingValues;
    Node := FDocument.Pattern.FindNode(FEdgeKey);
    if (Node is TEdgeObject) and not TEdgeObject(Node).IsClosed then
      Edge := TEdgeObject(Node);
  end;
  RefreshZip(Edge);
  RefreshDart(Edge);
  RefreshHem;
end;

// The selected edges' names, in the order selected
function TFeaturesPanel.EdgeNames: string;
var
  Key: string;
begin
  Result := '';
  for Key in FEdgeKeys do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + PointName(FDocument, Key);
  end;
end;

procedure TFeaturesPanel.RefreshHem;
begin
  FHemApply.Enabled := Assigned(FDocument) and (Length(FEdgeKeys) > 0);
  if FHemApply.Enabled then
    FHemEdgeLabel.Caption := Format(rsFeaturesAlong, [EdgeNames])
  else
    FHemEdgeLabel.Caption := rsFeaturesHemChoose;
end;

// A style starts with its own depth: a narrow hem is much smaller
procedure TFeaturesPanel.HemStyleChange(Sender: TObject);
begin
  if Assigned(FDocument) then
    HemStartingValues;
  ShowStyle;
end;

// The topstitching follows the depth, until it is typed in itself
procedure TFeaturesPanel.HemDepthChange(Sender: TObject);
begin
  if not Assigned(FDocument) then
    Exit;
  if Trim(FHemStitchEdit.Text) = HemStitchDistance(FDocument.Pattern, FHemDepth) then
    FHemStitchEdit.Text := HemStitchDistance(FDocument.Pattern, Trim(FHemDepthEdit.Text));
  FHemDepth := Trim(FHemDepthEdit.Text);
end;

// One undo step, or none when the hem cannot go there
procedure TFeaturesPanel.HemApplyClick(Sender: TObject);
var
  Spec: THemSpec;
  Made: THemMade;
  Done, Problem: string;
begin
  if not Assigned(FDocument) or FDocument.ChangeOpen then
    Exit;
  Spec := DefaultHem(FDocument.Pattern, FEdgeKeys, THemStyle(Max(FHemStyleBox.ItemIndex, 0)));
  Spec.Depth := Trim(FHemDepthEdit.Text);
  Spec.TurnUnder := Trim(FHemTurnEdit.Text);
  Spec.StitchDistance := Trim(FHemStitchEdit.Text);
  Spec.Notches := FHemNotchBox.Checked;
  Done := Format(rsFeaturesHemDone, [EdgeNames]);
  FDocument.BeginChange(rsFeaturesUndoHem);
  if not InsertHem(FDocument.Pattern, Spec, Made) then
  begin
    Done := FDocument.Pattern.LastError;
    FDocument.CancelChange;
    Say(Done);
    Exit;
  end;
  FDocument.EndChange;
  if FDocument.ChangeRefused then
  begin
    Say(FDocument.Pattern.LastError);
    Exit;
  end;
  for Problem in Made.Problems do
    Done := Format(rsFeaturesHemProblem, [Done, Problem]);
  Say(Done);
end;

procedure TFeaturesPanel.RefreshZip(Edge: TObject);
begin
  FApply.Enabled := Assigned(Edge) and (FPointKey = '');
  FFromBox.Enabled := FApply.Enabled;
  if not FApply.Enabled then
  begin
    FEdgeLabel.Caption := rsFeaturesChooseEdge;
    FFromBox.Items.Clear;
    Exit;
  end;
  FEdgeLabel.Caption := Format(rsFeaturesAlong, [TEdgeObject(Edge).DisplayName]);
  ShowEnds(FFromBox, FDocument, TEdgeObject(Edge), rsFeaturesFromPoint);
  StyleChange(nil);
end;

procedure TFeaturesPanel.RefreshDart(Edge: TObject);
var
  UnitText: string;
begin
  FDartApply.Enabled := Assigned(Edge);
  FDartFromBox.Enabled := FDartApply.Enabled;
  FDartFoldBox.Enabled := FDartApply.Enabled;
  UnitText := MEASURE_UNIT_NAMES[muMillimetre];
  if Assigned(FDocument) then
    UnitText := MEASURE_UNIT_NAMES[FDocument.Pattern.Units];
  FDartDepthEdit.Enabled := FPointKey = '';
  if FPointKey = '' then
    FDartDepthLabel.Caption := Format(rsFeaturesDartDepth, [UnitText])
  else
    FDartDepthLabel.Caption := Format(rsFeaturesDartToPoint, [PointName(FDocument, FPointKey)]);
  if not Assigned(Edge) then
  begin
    FDartEdgeLabel.Caption := rsFeaturesDartChoose;
    FDartFromBox.Items.Clear;
    FDartFoldBox.Items.Clear;
    Exit;
  end;
  FDartEdgeLabel.Caption := Format(rsFeaturesDartIn, [TEdgeObject(Edge).DisplayName]);
  ShowEnds(FDartFromBox, FDocument, TEdgeObject(Edge), rsFeaturesFromPoint);
  ShowEnds(FDartFoldBox, FDocument, TEdgeObject(Edge), rsFeaturesFromPoint);
end;

// A style starts with its own widths: a fly is wider than a lap
procedure TFeaturesPanel.StyleChange(Sender: TObject);
begin
  if Assigned(FDocument) and Assigned(Sender) then
    StartingValues
  else
    ShowStyle;
end;

procedure TFeaturesPanel.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(Self, AText);
end;

// One undo step, or none when the zip cannot go there
procedure TFeaturesPanel.ApplyClick(Sender: TObject);
var
  Spec: TZipSpec;
  Made: TZipMade;
  EdgeName, Done: string;
begin
  if not Assigned(FDocument) or FDocument.ChangeOpen then
    Exit;
  Spec := DefaultZip(FDocument.Pattern, FEdgeKey, TZipStyle(FStyleBox.ItemIndex));
  Spec.FromEnd := FFromBox.ItemIndex = 1;
  Spec.Length := Trim(FLengthEdit.Text);
  Spec.Allowance := Trim(FAllowanceEdit.Text);
  Spec.StitchDistance := Trim(FStitchEdit.Text);
  Spec.ShieldWidth := Trim(FShieldEdit.Text);
  EdgeName := PointName(FDocument, FEdgeKey);
  FDocument.BeginChange(rsFeaturesUndoZip);
  if not InsertZip(FDocument.Pattern, Spec, Made) then
  begin
    Done := FDocument.Pattern.LastError;
    FDocument.CancelChange;
    Say(Done);
    Exit;
  end;
  FDocument.EndChange;
  if FDocument.ChangeRefused then
  begin
    Say(FDocument.Pattern.LastError);
    Exit;
  end;
  Done := Format(rsFeaturesZipDone, [EdgeName]);
  if Made.ShieldKey <> '' then
    Done := Format(rsFeaturesZipShield, [Done]);
  if Made.OtherSide then
    Done := Format(rsFeaturesZipOtherSide, [Done]);
  Say(Done);
end;

// One undo step, or none when the dart cannot go there
procedure TFeaturesPanel.DartApplyClick(Sender: TObject);
var
  Spec: TDartSpec;
  Made: TDartMade;
  Reason: string;
begin
  if not Assigned(FDocument) or FDocument.ChangeOpen then
    Exit;
  Spec := DefaultDart(FDocument.Pattern, FEdgeKey);
  Spec.FromEnd := FDartFromBox.ItemIndex = 1;
  Spec.TowardsEnd := FDartFoldBox.ItemIndex = 1;
  Spec.Position := Trim(FDartPositionEdit.Text);
  Spec.Width := Trim(FDartWidthEdit.Text);
  Spec.Depth := Trim(FDartDepthEdit.Text);
  Spec.HoleInset := Trim(FDartHoleEdit.Text);
  FDocument.BeginChange(rsFeaturesUndoDart);
  if FPointKey <> '' then
    Spec.ApexKey := FDocument.Pattern.UsePoint(FPointKey);
  if not InsertDart(FDocument.Pattern, Spec, Made) then
  begin
    Reason := FDocument.Pattern.LastError;
    FDocument.CancelChange;
    Say(Reason);
    Exit;
  end;
  FDocument.EndChange;
  if FDocument.ChangeRefused then
  begin
    Say(FDocument.Pattern.LastError);
    Exit;
  end;
  Say(Format(rsFeaturesDartDone, [PointName(FDocument, Made.PieceKey)]));
end;

end.
