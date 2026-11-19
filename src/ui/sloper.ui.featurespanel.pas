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

// The Features tab: sewing details to apply to the pattern in one step,
// starting with a zip along the selected edge of a piece. Apply adds
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
    FEdgeKey: string;
    FKinds: TListBox;
    FSettings: TGroupBox;
    FEdgeLabel, FLengthLabel, FAllowanceLabel, FStitchLabel, FNote: TLabel;
    FStyleBox, FFromBox: TComboBox;
    FLengthEdit, FAllowanceEdit, FStitchEdit: TEdit;
    FApply: TButton;
    FNextTop: integer;
    FOnMessage: TFeaturesMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    function AddLabel(const ACaption: string): TLabel;
    procedure Place(Control: TControl);
    procedure StartingValues;
    procedure Refresh;
    procedure StyleChange(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure Say(const AText: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // The canvas's selection: a zip goes along one selected edge
    procedure ShowSelection(const Keys: TStringArray);
    property Document: TPatternDocument read FDocument write SetDocument;
    property OnMessage: TFeaturesMessageEvent read FOnMessage write FOnMessage;
  end;

resourcestring
  rsFeaturesStyle = 'Style';
  rsFeaturesCentred = 'Centred, topstitched either side';
  rsFeaturesInvisible = 'Invisible, nothing showing';
  rsFeaturesLength = 'Length (%s)';
  rsFeaturesFrom = 'Starts from';
  rsFeaturesFromPoint = 'The %s end';
  rsFeaturesAllowance = 'Allowance along the zip (%s)';
  rsFeaturesStitch = 'Topstitching from the seam (%s)';
  rsFeaturesApply = '&Apply';
  rsFeaturesAlong = 'Along %s';
  rsFeaturesChooseEdge = 'Select an edge of a piece on the canvas.';
  rsFeaturesZipNote = 'Apply splits the edge where the zip stops, gives the opening its allowance, notches the stop and, ' +
    'for a centred zip, adds the topstitching. They are ordinary objects, to change as you like; one Undo takes them all off.';
  rsFeaturesUndoZip = 'Insert Zip';
  rsFeaturesZipDone = 'Zip added along %s';
  rsFeaturesZipOtherSide = '%s; its seam joins another edge, which needs a zip too';

implementation

uses
  Graphics, Math, Sloper.Core.Draft, Sloper.Core.Units, Sloper.UI.Spacing;

const
  // The list of features, about four rows, at 96 pixels per inch
  KIND_LIST_HEIGHT96 = 90;

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
  FKinds.ItemIndex := 0;
  FKinds.Height := Scale96ToScreen(KIND_LIST_HEIGHT96);
  FSettings := TGroupBox.Create(Self);
  FSettings.Parent := Self;
  FSettings.Align := alClient;
  FSettings.Caption := rsFeatureZip;
  SpaceChildren(FSettings);
  FEdgeLabel := AddLabel('');
  FEdgeLabel.Font.Style := [fsBold];
  AddLabel(rsFeaturesStyle);
  FStyleBox := TComboBox.Create(Self);
  FStyleBox.Style := csDropDownList;
  FStyleBox.Items.Add(rsFeaturesCentred);
  FStyleBox.Items.Add(rsFeaturesInvisible);
  FStyleBox.ItemIndex := 0;
  FStyleBox.OnChange := @StyleChange;
  Place(FStyleBox);
  FLengthLabel := AddLabel('');
  FLengthEdit := TEdit.Create(Self);
  Place(FLengthEdit);
  AddLabel(rsFeaturesFrom);
  FFromBox := TComboBox.Create(Self);
  FFromBox.Style := csDropDownList;
  Place(FFromBox);
  FAllowanceLabel := AddLabel('');
  FAllowanceEdit := TEdit.Create(Self);
  Place(FAllowanceEdit);
  FStitchLabel := AddLabel('');
  FStitchEdit := TEdit.Create(Self);
  Place(FStitchEdit);
  FApply := TButton.Create(Self);
  FApply.Caption := rsFeaturesApply;
  FApply.AutoSize := True;
  FApply.OnClick := @ApplyClick;
  Place(FApply);
  FApply.Align := alNone;
  FApply.Anchors := [akLeft, akTop];
  FApply.AnchorSide[akTop].Control := FStitchEdit;
  FApply.AnchorSide[akTop].Side := asrBottom;
  FApply.BorderSpacing.Top := ControlGap;
  FNote := TLabel.Create(Self);
  FNote.Parent := FSettings;
  FNote.WordWrap := True;
  FNote.AutoSize := True;
  FNote.Caption := rsFeaturesZipNote;
  FNote.Anchors := [akLeft, akRight, akTop];
  FNote.AnchorSide[akLeft].Control := FSettings;
  FNote.AnchorSide[akRight].Control := FSettings;
  FNote.AnchorSide[akRight].Side := asrBottom;
  FNote.AnchorSide[akTop].Control := FApply;
  FNote.AnchorSide[akTop].Side := asrBottom;
  FNote.BorderSpacing.Top := ControlGap;
  Refresh;
end;

destructor TFeaturesPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

// A caption over the field after it, both down the group in order
function TFeaturesPanel.AddLabel(const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := ACaption;
  Place(Result);
end;

procedure TFeaturesPanel.Place(Control: TControl);
begin
  Control.Parent := FSettings;
  Control.Align := alTop;
  // Each below the one before
  Inc(FNextTop, Control.Height + 1);
  Control.Top := FNextTop;
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
begin
  FEdgeKey := '';
  if Length(Keys) = 1 then
    FEdgeKey := Keys[0];
  Refresh;
end;

// A new or opened pattern, or another unit, starts the fields again
procedure TFeaturesPanel.StartingValues;
var
  Spec: TZipSpec;
  UnitText: string;
begin
  Spec := DefaultZip(FDocument.Pattern, '');
  FLengthEdit.Text := Spec.Length;
  FAllowanceEdit.Text := Spec.Allowance;
  FStitchEdit.Text := Spec.StitchDistance;
  UnitText := MEASURE_UNIT_NAMES[FDocument.Pattern.Units];
  FLengthLabel.Caption := Format(rsFeaturesLength, [UnitText]);
  FAllowanceLabel.Caption := Format(rsFeaturesAllowance, [UnitText]);
  FStitchLabel.Caption := Format(rsFeaturesStitch, [UnitText]);
  FGeneration := FDocument.Generation;
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

procedure TFeaturesPanel.Refresh;
var
  Node: TObject;
  Edge: TEdgeObject;
  Index: integer;
begin
  Edge := nil;
  if Assigned(FDocument) then
  begin
    if FGeneration <> FDocument.Generation then
      StartingValues;
    Node := FDocument.Pattern.FindNode(FEdgeKey);
    if Node is TEdgeObject then
      Edge := TEdgeObject(Node);
  end;
  FApply.Enabled := Assigned(Edge) and not Edge.IsClosed;
  FFromBox.Enabled := FApply.Enabled;
  if not FApply.Enabled then
  begin
    FEdgeLabel.Caption := rsFeaturesChooseEdge;
    FFromBox.Items.Clear;
    Exit;
  end;
  FEdgeLabel.Caption := Format(rsFeaturesAlong, [Edge.DisplayName]);
  Index := Max(FFromBox.ItemIndex, 0);
  FFromBox.Items.Clear;
  FFromBox.Items.Add(Format(rsFeaturesFromPoint, [PointName(FDocument, Edge.StartKey)]));
  FFromBox.Items.Add(Format(rsFeaturesFromPoint, [PointName(FDocument, Edge.EndKey)]));
  FFromBox.ItemIndex := Index;
  StyleChange(nil);
end;

procedure TFeaturesPanel.StyleChange(Sender: TObject);
begin
  FStitchEdit.Enabled := FStyleBox.ItemIndex = Ord(zsCentred);
  FStitchLabel.Enabled := FStitchEdit.Enabled;
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
  Spec := DefaultZip(FDocument.Pattern, FEdgeKey);
  Spec.Style := TZipStyle(FStyleBox.ItemIndex);
  Spec.FromEnd := FFromBox.ItemIndex = 1;
  Spec.Length := Trim(FLengthEdit.Text);
  Spec.Allowance := Trim(FAllowanceEdit.Text);
  Spec.StitchDistance := Trim(FStitchEdit.Text);
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
  if Made.OtherSide then
    Done := Format(rsFeaturesZipOtherSide, [Done]);
  Say(Done);
end;

end.
