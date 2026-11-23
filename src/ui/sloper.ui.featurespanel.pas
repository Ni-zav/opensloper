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
// zip along the selected edge of a piece, a dart in it, a hem or a facing
// along the selected edges, or buttons down a front. Each feature's fields,
// their captions and starting values, and Apply come from
// Sloper.Editor.FeatureForms, which the web editor uses too; this panel only
// builds the controls. Apply adds ordinary objects, as one undo step.
unit Sloper.UI.FeaturesPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Sloper.Document.PatternDocument, Sloper.Editor.FeatureForms;

type
  TFeaturesMessageEvent = procedure(Sender: TObject; const AText: string) of object;

  // A field's control, with the caption above it, if it has one
  TFeatureControl = record
    Id: string;
    Kind: TFeatureFieldKind;
    Caption: TLabel;
    Control: TControl;
  end;

  TFeatureGroup = record
    Group: TGroupBox;
    Header: TLabel;
    Controls: array of TFeatureControl;
    Apply: TButton;
    // The values when last shown, for a change to know what a field held before
    Shown: TFeatureValues;
  end;

  TFeaturesPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    // The pattern the fields' starting values were set for
    FGeneration: integer;
    // The canvas's selection
    FKeys: TStringArray;
    FKinds: TListBox;
    FGroups: array[TFeatureKind] of TFeatureGroup;
    // The panel is setting the controls, so their changes are not the user's
    FUpdating: boolean;
    FOnMessage: TFeaturesMessageEvent;
    procedure SetDocument(ADocument: TPatternDocument);
    procedure DocumentChanged(Document: TPatternDocument; Changes: TDocumentChanges);
    procedure Build(Kind: TFeatureKind; const Form: TFeatureForm);
    function ValuesOf(Kind: TFeatureKind): TFeatureValues;
    procedure SetValues(Kind: TFeatureKind; const Values: TFeatureValues);
    procedure Refresh;
    procedure RefreshKind(Kind: TFeatureKind);
    procedure KindClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
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
  rsFeaturesApply = '&Apply';

implementation

uses
  Graphics, Math, Sloper.Core.Pattern, Sloper.UI.Spacing;

const
  // The list of features, about four rows, at 96 pixels per inch
  KIND_LIST_HEIGHT96 = 90;
  // A control's Tag: its feature times this, plus its place in the group
  TAG_KIND = 1000;

constructor TFeaturesPanel.Create(AOwner: TComponent);
var
  Kind: TFeatureKind;
  Pattern: TPattern;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  SpaceChildren(Self);
  FGeneration := -1;
  FKinds := TListBox.Create(Self);
  FKinds.Parent := Self;
  FKinds.Align := alTop;
  FKinds.Height := Scale96ToScreen(KIND_LIST_HEIGHT96);
  FKinds.OnClick := @KindClick;
  // A feature's fields are the same for any pattern, so an empty one lays them out
  Pattern := TPattern.Create;
  try
    for Kind in TFeatureKind do
    begin
      FKinds.Items.Add(FeatureCaption(Kind));
      Build(Kind, FeatureForm(Pattern, Kind, Default(TFeatureSelection), FeatureStartingValues(Pattern, Kind, nil)));
      SetValues(Kind, FeatureStartingValues(Pattern, Kind, nil));
    end;
  finally
    FreeAndNil(Pattern);
  end;
  FKinds.ItemIndex := Ord(fkZip);
  KindClick(nil);
end;

destructor TFeaturesPanel.Destroy;
begin
  SetDocument(nil);
  inherited Destroy;
end;

// The fields down the group in order, each caption over its field, then
// Apply and the note saying what it adds
procedure TFeaturesPanel.Build(Kind: TFeatureKind; const Form: TFeatureForm);
var
  Group: TGroupBox;
  Next: integer;
  Index: integer;
  Field: TFeatureField;
  Item: TFeatureControl;
  Edit: TEdit;
  Box: TComboBox;
  Check: TCheckBox;
  Note: TLabel;

  procedure Place(Control: TControl);
  begin
    Control.Parent := Group;
    Control.Align := alTop;
    // Each below the one before
    Inc(Next, Control.Height + 1);
    Control.Top := Next;
  end;

begin
  Group := TGroupBox.Create(Self);
  Group.Parent := Self;
  Group.Align := alClient;
  Group.Caption := FeatureCaption(Kind);
  SpaceChildren(Group);
  Next := 0;
  FGroups[Kind].Group := Group;
  FGroups[Kind].Header := TLabel.Create(Self);
  FGroups[Kind].Header.Font.Style := [fsBold];
  FGroups[Kind].Header.WordWrap := True;
  Place(FGroups[Kind].Header);
  FGroups[Kind].Controls := nil;
  for Index := 0 to High(Form.Fields) do
  begin
    Field := Form.Fields[Index];
    Item := Default(TFeatureControl);
    Item.Id := Field.Id;
    Item.Kind := Field.Kind;
    if (Field.Kind <> ffkCheck) and (Field.Caption <> '') then
    begin
      Item.Caption := TLabel.Create(Self);
      Place(Item.Caption);
    end;
    case Field.Kind of
      ffkText:
      begin
        Edit := TEdit.Create(Self);
        Edit.OnChange := @FieldChange;
        Item.Control := Edit;
      end;
      ffkChoice, ffkCombo:
      begin
        Box := TComboBox.Create(Self);
        if Field.Kind = ffkChoice then
          Box.Style := csDropDownList
        else
          Box.Style := csDropDown;
        Box.OnChange := @FieldChange;
        Item.Control := Box;
      end;
      ffkCheck:
      begin
        Check := TCheckBox.Create(Self);
        Check.OnClick := @FieldChange;
        Item.Control := Check;
      end;
    end;
    Item.Control.Tag := Ord(Kind) * TAG_KIND + Index;
    Place(Item.Control);
    Insert(Item, FGroups[Kind].Controls, Length(FGroups[Kind].Controls));
  end;
  FGroups[Kind].Apply := TButton.Create(Self);
  FGroups[Kind].Apply.Caption := rsFeaturesApply;
  FGroups[Kind].Apply.AutoSize := True;
  FGroups[Kind].Apply.Tag := Ord(Kind) * TAG_KIND;
  FGroups[Kind].Apply.OnClick := @ApplyClick;
  Place(FGroups[Kind].Apply);
  FGroups[Kind].Apply.Align := alNone;
  FGroups[Kind].Apply.Anchors := [akLeft, akTop];
  FGroups[Kind].Apply.AnchorSide[akTop].Control := FGroups[Kind].Controls[High(FGroups[Kind].Controls)].Control;
  FGroups[Kind].Apply.AnchorSide[akTop].Side := asrBottom;
  FGroups[Kind].Apply.BorderSpacing.Top := ControlGap;
  Note := TLabel.Create(Self);
  Note.Parent := Group;
  Note.WordWrap := True;
  Note.AutoSize := True;
  Note.Caption := Form.Note;
  Note.Anchors := [akLeft, akRight, akTop];
  Note.AnchorSide[akLeft].Control := Group;
  Note.AnchorSide[akRight].Control := Group;
  Note.AnchorSide[akRight].Side := asrBottom;
  Note.AnchorSide[akTop].Control := FGroups[Kind].Apply;
  Note.AnchorSide[akTop].Side := asrBottom;
  Note.BorderSpacing.Top := ControlGap;
end;

function SameItems(Items: TStrings; const Choices: TStringArray): boolean;
var
  Index: integer;
begin
  Result := Items.Count = Length(Choices);
  for Index := 0 to High(Choices) do
    if Result and (Items[Index] <> Choices[Index]) then
      Result := False;
end;

function TFeaturesPanel.ValuesOf(Kind: TFeatureKind): TFeatureValues;
var
  Item: TFeatureControl;
  Value: string;
begin
  Result := nil;
  for Item in FGroups[Kind].Controls do
  begin
    case Item.Kind of
      ffkChoice: Value := IntToStr(TComboBox(Item.Control).ItemIndex);
      ffkCheck:
        if TCheckBox(Item.Control).Checked then
          Value := FEATURE_CHECKED
        else
          Value := FEATURE_UNCHECKED;
      ffkCombo: Value := TComboBox(Item.Control).Text;
      else
        Value := TEdit(Item.Control).Text;
    end;
    SetFeatureValue(Result, Item.Id, Value);
  end;
end;

procedure TFeaturesPanel.SetValues(Kind: TFeatureKind; const Values: TFeatureValues);
var
  Item: TFeatureControl;
  Value: string;
begin
  FUpdating := True;
  try
    for Item in FGroups[Kind].Controls do
    begin
      Value := FeatureValue(Values, Item.Id, #0);
      if Value = #0 then
        Continue;
      case Item.Kind of
        ffkChoice: TComboBox(Item.Control).ItemIndex := StrToIntDef(Value, 0);
        ffkCheck: TCheckBox(Item.Control).Checked := Value = FEATURE_CHECKED;
        ffkCombo: TComboBox(Item.Control).Text := Value;
        else
          TEdit(Item.Control).Text := Value;
      end;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TFeaturesPanel.KindClick(Sender: TObject);
var
  Kind: TFeatureKind;
begin
  for Kind in TFeatureKind do
    FGroups[Kind].Group.Visible := FKinds.ItemIndex = Ord(Kind);
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
  FKeys := Copy(Keys);
  Refresh;
end;

// A new or opened pattern starts the fields again, keeping each style chosen
procedure TFeaturesPanel.Refresh;
var
  Kind: TFeatureKind;
begin
  if not Assigned(FDocument) then
    Exit;
  if FGeneration <> FDocument.Generation then
  begin
    for Kind in TFeatureKind do
      SetValues(Kind, FeatureStartingValues(FDocument.Pattern, Kind, ValuesOf(Kind)));
    FGeneration := FDocument.Generation;
  end;
  for Kind in TFeatureKind do
    RefreshKind(Kind);
end;

// Shows the feature's form: what it goes along, each field's caption and
// choices, and what can be changed or applied now
procedure TFeaturesPanel.RefreshKind(Kind: TFeatureKind);
var
  Form: TFeatureForm;
  Index, Chosen: integer;
  Item: TFeatureControl;
  Field: TFeatureField;
  Box: TComboBox;
  Choice: string;
begin
  FGroups[Kind].Shown := ValuesOf(Kind);
  Form := FeatureForm(FDocument.Pattern, Kind, FeatureSelectionOf(FDocument.Pattern, FKeys), FGroups[Kind].Shown);
  FGroups[Kind].Header.Caption := Form.Header;
  FGroups[Kind].Apply.Enabled := Form.CanApply;
  FUpdating := True;
  try
    for Index := 0 to High(FGroups[Kind].Controls) do
    begin
      Item := FGroups[Kind].Controls[Index];
      Field := Form.Fields[Index];
      if Assigned(Item.Caption) then
      begin
        Item.Caption.Caption := Field.Caption;
        Item.Caption.Enabled := Field.Enabled;
      end;
      Item.Control.Enabled := Field.Enabled;
      case Item.Kind of
        ffkCheck: TCheckBox(Item.Control).Caption := Field.Caption;
        ffkChoice, ffkCombo:
        begin
          Box := TComboBox(Item.Control);
          // Choices put back only when they change, as an edge's ends do, keeping what is chosen or typed
          if not SameItems(Box.Items, Field.Choices) then
          begin
            Chosen := Max(StrToIntDef(Field.Text, 0), 0);
            Box.Items.Clear;
            for Choice in Field.Choices do
              Box.Items.Add(Choice);
            if Item.Kind = ffkCombo then
              Box.Text := Field.Text
            else if Chosen < Box.Items.Count then
              Box.ItemIndex := Chosen
            else if Box.Items.Count > 0 then
              Box.ItemIndex := 0;
          end;
        end;
      end;
    end;
  finally
    FUpdating := False;
  end;
end;

// Another style starts again at its own widths, and a hem's topstitching
// follows its depth, then the form is shown again
procedure TFeaturesPanel.FieldChange(Sender: TObject);
var
  Kind: TFeatureKind;
  Id: string;
begin
  if FUpdating or not Assigned(FDocument) then
    Exit;
  Kind := TFeatureKind(TControl(Sender).Tag div TAG_KIND);
  Id := FGroups[Kind].Controls[TControl(Sender).Tag mod TAG_KIND].Id;
  SetValues(Kind, FeatureValueChanged(FDocument.Pattern, Kind, ValuesOf(Kind), Id,
    FeatureValue(FGroups[Kind].Shown, Id)));
  RefreshKind(Kind);
end;

// One undo step, or none when the feature cannot go there
procedure TFeaturesPanel.ApplyClick(Sender: TObject);
var
  Kind: TFeatureKind;
  Message: string;
begin
  if not Assigned(FDocument) then
    Exit;
  Kind := TFeatureKind(TControl(Sender).Tag div TAG_KIND);
  ApplyFeature(FDocument, Kind, FeatureSelectionOf(FDocument.Pattern, FKeys), ValuesOf(Kind), Message);
  if Assigned(FOnMessage) then
    FOnMessage(Self, Message);
end;

end.
