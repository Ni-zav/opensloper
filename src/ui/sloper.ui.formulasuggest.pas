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

// The list of formula suggestions under a field of the properties panel: a
// row of the panel, not a popup, so it stays open while the point is dragged
// on the canvas. Each row shows a formula, its value and how far off it is.
// When nothing is close, it says so and shows the nearest formula.
unit Sloper.UI.FormulaSuggest;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, LCLType, Sloper.Core.Units, Sloper.Editor.Suggestion, Sloper.Editor.SuggestionGrade;

type
  // Index is a row of the list, or -1 when the pointer is on none
  TSuggestHoverEvent = procedure(Sender: TObject; Index: integer) of object;

  TFormulaSuggestList = class(TListBox)
  private
    FRows: TSuggestionArray;
    // The row saying nothing is close, which cannot be chosen; -1 when none
    FNoneRow: integer;
    FKind: TSuggestionKind;
    FUnits: TMeasureUnit;
    // The most rows shown since it opened: it does not shrink while dragging
    FShownRows: integer;
    FHoverIndex: integer;
    FGrade: TGradeCheck;
    FOnChoose: TNotifyEvent;
    FOnHover: TSuggestHoverEvent;
    procedure DrawRow(Control: TWinControl; Index: integer; ARect: TRect; State: TOwnerDrawState);
    function ColumnGap: integer;
    function FormulaWidth(RowWidth: integer): integer;
    function Graded: boolean;
    procedure SetHover(Index: integer);
    procedure Choose;
  protected
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Fills the list, keeping the row chosen with the keys when its formula is still there
    procedure ShowSuggestions(const Found: TSuggestions; Kind: TSuggestionKind; Units: TMeasureUnit);
    // Shows from the top again, at the height of what it holds
    procedure Restart;
    // The suggestion in a row, False for the row saying nothing is close
    function RowSuggestion(Index: integer; out Suggestion: TSuggestion): boolean;
    // Up, Down and Enter from the field while the list is open; True when used
    function HandleKey(var Key: word): boolean;
    // A row was clicked, or Enter pressed on one: ItemIndex says which
    property OnChoose: TNotifyEvent read FOnChoose write FOnChoose;
    property OnHover: TSuggestHoverEvent read FOnHover write FOnHover;
    // With a size table, each row also shows its values at the first and last
    // sizes, and its tooltip the value at every size; nil for none. The panel owns it.
    property Grade: TGradeCheck read FGrade write FGrade;
  end;

resourcestring
  // The tolerance: 5 mm
  rsSuggestNone = 'No formulas within %s; the nearest:';
  // The first and last sizes, and the formula's values at them: S–L: 450–510
  rsSuggestSizeRange = '%s–%s: %s';

implementation

uses
  Math, Forms, Sloper.UI.GridColumns;

const
  // Rows shown before the list scrolls
  MAX_VISIBLE_ROWS = 6;
  // The nothing-close row and the nearest one
  MIN_VISIBLE_ROWS = 2;
  // Between the columns and at the sides, at 96 pixels per inch
  COLUMN_GAP96 = 12;
  // Room for the list's frame, in pixels
  FRAME_PIXELS = 4;
  // A row, at 96 pixels per inch
  ROW_HEIGHT96 = 22;
  // Text for the width of the value and difference columns
  VALUE_COLUMN_SAMPLE = '0000.00';
  DELTA_COLUMN_SAMPLE = '+00.00';

constructor TFormulaSuggestList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := lbOwnerDrawFixed;
  OnDrawItem := @DrawRow;
  TabStop := False;
  FNoneRow := -1;
  FHoverIndex := -1;
end;

procedure TFormulaSuggestList.Restart;
begin
  FShownRows := 0;
  SetHover(-1);
end;

procedure TFormulaSuggestList.ShowSuggestions(const Found: TSuggestions; Kind: TSuggestionKind; Units: TMeasureUnit);
var
  Item: TSuggestion;
  Chosen: string;
  Index, Rows: integer;
begin
  Chosen := '';
  if (ItemIndex >= 0) and (ItemIndex <= High(FRows)) then
    Chosen := FRows[ItemIndex].Text;
  FKind := Kind;
  FUnits := Units;
  FRows := Copy(Found.Items);
  FNoneRow := -1;
  if (Length(FRows) = 0) and Found.HasNearest then
  begin
    FNoneRow := 0;
    FRows := [Default(TSuggestion), Found.Nearest];
  end;
  Items.BeginUpdate;
  try
    Items.Clear;
    for Item in FRows do
      Items.Add(Item.Text);
  finally
    Items.EndUpdate;
  end;
  ItemIndex := -1;
  for Index := 0 to High(FRows) do
    if (Chosen <> '') and (Index <> FNoneRow) and (FRows[Index].Text = Chosen) then
      ItemIndex := Index;
  // An owner-drawn list has no row height of its own; a size table's range
  // takes a second line
  ItemHeight := Scale96ToForm(ROW_HEIGHT96);
  if Graded then
    ItemHeight := 2 * ItemHeight;
  Rows := Max(MIN_VISIBLE_ROWS, Min(Length(FRows), MAX_VISIBLE_ROWS));
  FShownRows := Max(FShownRows, Rows);
  Height := FShownRows * ItemHeight + FRAME_PIXELS;
  if FHoverIndex > High(FRows) then
    SetHover(-1);
end;

function TFormulaSuggestList.RowSuggestion(Index: integer; out Suggestion: TSuggestion): boolean;
begin
  Suggestion := Default(TSuggestion);
  Result := (Index >= 0) and (Index <= High(FRows)) and (Index <> FNoneRow);
  if Result then
    Suggestion := FRows[Index];
end;

// Formula on the left; value and difference in columns on the right
// The formula's column: what the value and difference leave of a row
function TFormulaSuggestList.FormulaWidth(RowWidth: integer): integer;
begin
  Result := RowWidth - Canvas.TextWidth(DELTA_COLUMN_SAMPLE) - Canvas.TextWidth(VALUE_COLUMN_SAMPLE) - 3 * ColumnGap;
end;

function TFormulaSuggestList.ColumnGap: integer;
begin
  Result := Scale96ToForm(COLUMN_GAP96) div 2;
end;

function TFormulaSuggestList.Graded: boolean;
begin
  Result := Assigned(FGrade) and FGrade.Available;
end;

// Formula on the left, cut short with an ellipsis when it does not fit, and
// its value and difference in columns on the right. With a size table, its
// values at the first and last sizes go on a second line, so they take no
// room from the formula.
procedure TFormulaSuggestList.DrawRow(Control: TWinControl; Index: integer; ARect: TRect; State: TOwnerDrawState);
var
  Gap, LineHeight, TextTop: integer;
  Row: TSuggestion;
  ValueText, DeltaText, RangeText: string;
begin
  Canvas.FillRect(ARect);
  if (Index < 0) or (Index > High(FRows)) then
    Exit;
  Gap := ColumnGap;
  LineHeight := ARect.Height;
  if Graded then
    LineHeight := ARect.Height div 2;
  TextTop := ARect.Top + (LineHeight - Canvas.TextHeight('Ag')) div 2;
  if Index = FNoneRow then
  begin
    if not (odSelected in State) then
      Canvas.Font.Color := clGrayText;
    Canvas.TextRect(ARect, ARect.Left + Gap, TextTop, Format(rsSuggestNone, [SuggestionToleranceText(FKind, FUnits)]));
    Exit;
  end;
  Row := FRows[Index];
  ValueText := SuggestionValueText(Row.Value, FKind, FUnits);
  DeltaText := SuggestionDeltaText(Row.Delta, FKind, FUnits);
  Canvas.TextOut(ARect.Left + Gap, TextTop, FitText(Row.Text, FormulaWidth(ARect.Width), @Canvas.TextWidth));
  Canvas.TextOut(ARect.Right - Canvas.TextWidth(DELTA_COLUMN_SAMPLE) - 2 * Gap - Canvas.TextWidth(ValueText), TextTop, ValueText);
  if not (odSelected in State) then
    Canvas.Font.Color := clGrayText;
  Canvas.TextOut(ARect.Right - Gap - Canvas.TextWidth(DeltaText), TextTop, DeltaText);
  if not Graded then
    Exit;
  RangeText := SizeRangeText(FGrade.Values(Row.Text), FKind, FUnits);
  if RangeText = '' then
    RangeText := rsGradeNoValue;
  Canvas.TextOut(ARect.Left + 2 * Gap, TextTop + LineHeight, FitText(Format(rsSuggestSizeRange,
    [FGrade.Sizes[0], FGrade.Sizes[FGrade.SizeCount - 1], RangeText]), ARect.Width - 3 * Gap, @Canvas.TextWidth));
end;

procedure TFormulaSuggestList.SetHover(Index: integer);
var
  Suggestion: TSuggestion;
begin
  if Index = FHoverIndex then
    Exit;
  FHoverIndex := Index;
  // The tooltip gives a formula cut short in full, and the row's value at every size
  Application.CancelHint;
  Hint := '';
  if RowSuggestion(Index, Suggestion) then
  begin
    if Canvas.TextWidth(Suggestion.Text) > FormulaWidth(ClientWidth) then
      Hint := Suggestion.Text;
    if Graded and (Hint <> '') then
      Hint := Hint + LineEnding;
    if Graded then
      Hint := Hint + SizeValuesText(FGrade, FGrade.Values(Suggestion.Text), FKind, FUnits);
  end;
  ShowHint := Hint <> '';
  if Assigned(FOnHover) then
    FOnHover(Self, Index);
end;

procedure TFormulaSuggestList.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Index: integer;
begin
  inherited MouseMove(Shift, X, Y);
  Index := GetIndexAtXY(X, Y);
  if Index = FNoneRow then
    Index := -1;
  SetHover(Index);
end;

procedure TFormulaSuggestList.MouseLeave;
begin
  inherited MouseLeave;
  SetHover(-1);
end;

procedure TFormulaSuggestList.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Index: integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  Index := GetIndexAtXY(X, Y);
  if (Button = mbLeft) and (Index >= 0) and (Index <> FNoneRow) then
  begin
    ItemIndex := Index;
    Choose;
  end;
end;

procedure TFormulaSuggestList.Choose;
var
  Suggestion: TSuggestion;
begin
  if RowSuggestion(ItemIndex, Suggestion) and Assigned(FOnChoose) then
    FOnChoose(Self);
end;

// The rows are previewed as the keys reach them, as hovering does
function TFormulaSuggestList.HandleKey(var Key: word): boolean;
var
  Next: integer;
begin
  Result := True;
  case Key of
    VK_UP, VK_DOWN:
    begin
      if Key = VK_UP then
        Next := Max(ItemIndex - 1, 0)
      else
        Next := Min(ItemIndex + 1, Count - 1);
      if Next = FNoneRow then
        Next := Min(Next + 1, Count - 1);
      ItemIndex := Next;
      if Next <> FNoneRow then
        SetHover(Next);
    end;
    VK_RETURN:
    begin
      Result := ItemIndex >= 0;
      if Result then
        Choose;
    end;
    else
      Result := False;
  end;
  if Result then
    Key := 0;
end;

procedure TFormulaSuggestList.KeyDown(var Key: word; Shift: TShiftState);
begin
  if not HandleKey(Key) then
    inherited KeyDown(Key, Shift);
end;

end.
