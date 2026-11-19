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

// The Problems tab every app's side panel ends with: each problem in full,
// wrapped to the panel's width. Pointing at one or choosing it tells the
// window what it is about, by a key the window gave it, so the window can
// show it. It knows nothing of documents, so each app fills it its own way.
unit Sloper.UI.ProblemsPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, ExtCtrls, Grids, Graphics;

type
  TListedProblem = record
    // What the problem is about, in the window's own terms; empty for none
    Key: string;
    Text: string;
    // It stops printing or exporting, rather than only warning
    Blocking: boolean;
  end;

  TListedProblemArray = array of TListedProblem;

  TProblemKeyEvent = procedure(Sender: TObject; const Key: string) of object;

  TProblemsPanel = class(TPanel)
  private
    FGrid: TStringGrid;
    FEmpty: TLabel;
    FProblems: TListedProblemArray;
    // The row the user chose, so the grid's own current row is not drawn as
    // chosen when nothing was
    FChosen: integer;
    FHoverRow: integer;
    FRowBeforePress: integer;
    // Moving the grid's current row in code must not read as a user's choice
    FUpdating: boolean;
    FOnSelect: TProblemKeyEvent;
    FOnHover: TProblemKeyEvent;
    FOnZoom: TProblemKeyEvent;
    function GetCount: integer;
    function RowKey(RowIndex: integer): string;
    procedure FitRows;
    procedure Choose(RowIndex: integer);
    procedure SetHoverRow(RowIndex: integer);
    procedure GridSelection(Sender: TObject; ACol, ARow: integer);
    procedure GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
    procedure GridClick(Sender: TObject);
    procedure GridDoubleClick(Sender: TObject);
    procedure GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
    procedure GridMouseLeave(Sender: TObject);
    procedure GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
    procedure GridResize(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    // Lists these, keeping the chosen one chosen if it is still listed
    procedure SetProblems(const Problems: TListedProblemArray);
    property Count: integer read GetCount;
    // The user chose a problem, by clicking it or moving to it with the keys
    property OnSelect: TProblemKeyEvent read FOnSelect write FOnSelect;
    // The pointer moved onto a problem, or off them all with an empty key
    property OnHover: TProblemKeyEvent read FOnHover write FOnHover;
    // The user double-clicked a problem
    property OnZoom: TProblemKeyEvent read FOnZoom write FOnZoom;
  end;

resourcestring
  rsProblemsNone = 'No problems';

implementation

uses
  LCLIntf, LCLType, Math, Sloper.UI.Spacing;

const
  BLOCKING_INK = TColor($2020C0);
  // Between a problem's text and its cell's edges, at 96 pixels per inch
  CELL_PADDING96 = 4;

constructor TProblemsPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  Caption := '';
  FChosen := -1;
  FHoverRow := -1;
  SpaceChildren(Self);
  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alTop;
  FEmpty.Caption := rsProblemsNone;
  FEmpty.Font.Color := clGrayText;
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 0;
  FGrid.ColCount := 1;
  FGrid.RowCount := 0;
  FGrid.AutoFillColumns := True;
  FGrid.ScrollBars := ssAutoVertical;
  FGrid.Options := [goRowSelect, goThumbTracking, goSmoothScroll];
  FGrid.FocusRectVisible := False;
  FGrid.Visible := False;
  FGrid.OnSelection := @GridSelection;
  FGrid.OnMouseDown := @GridMouseDown;
  FGrid.OnClick := @GridClick;
  FGrid.OnDblClick := @GridDoubleClick;
  FGrid.OnMouseMove := @GridMouseMove;
  FGrid.OnMouseLeave := @GridMouseLeave;
  FGrid.OnPrepareCanvas := @GridPrepareCanvas;
  FGrid.OnResize := @GridResize;
end;

function TProblemsPanel.GetCount: integer;
begin
  Result := Length(FProblems);
end;

function TProblemsPanel.RowKey(RowIndex: integer): string;
begin
  Result := '';
  if (RowIndex >= 0) and (RowIndex <= High(FProblems)) then
    Result := FProblems[RowIndex].Key;
end;

procedure TProblemsPanel.SetProblems(const Problems: TListedProblemArray);
var
  Chosen: TListedProblem;
  HadChoice: boolean;
  Index: integer;
begin
  HadChoice := (FChosen >= 0) and (FChosen <= High(FProblems));
  if HadChoice then
    Chosen := FProblems[FChosen];
  FProblems := Copy(Problems);
  FChosen := -1;
  FHoverRow := -1;
  FUpdating := True;
  try
    FGrid.RowCount := Length(FProblems);
    for Index := 0 to High(FProblems) do
    begin
      FGrid.Cells[0, Index] := FProblems[Index].Text;
      if HadChoice and (FChosen < 0) and (FProblems[Index].Key = Chosen.Key) and (FProblems[Index].Text = Chosen.Text) then
        FChosen := Index;
    end;
    if FChosen >= 0 then
      FGrid.Row := FChosen;
  finally
    FUpdating := False;
  end;
  FEmpty.Visible := Length(FProblems) = 0;
  FGrid.Visible := Length(FProblems) > 0;
  FitRows;
  FGrid.Invalidate;
end;

// Each row as tall as its text wrapped to the column
procedure TProblemsPanel.FitRows;
var
  Index, Padding: integer;
  Area: TRect;
begin
  if not FGrid.HandleAllocated or (FGrid.RowCount = 0) then
    Exit;
  Padding := Scale96ToForm(CELL_PADDING96);
  FGrid.Canvas.Font := FGrid.Font;
  for Index := 0 to FGrid.RowCount - 1 do
  begin
    Area := Rect(0, 0, Max(1, FGrid.ColWidths[0] - 2 * Padding), 0);
    DrawText(FGrid.Canvas.Handle, PChar(FGrid.Cells[0, Index]), Length(FGrid.Cells[0, Index]), Area, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
    FGrid.RowHeights[Index] := Max(FGrid.DefaultRowHeight, Area.Bottom - Area.Top + 2 * Padding);
  end;
end;

procedure TProblemsPanel.Choose(RowIndex: integer);
begin
  if (RowIndex < 0) or (RowIndex > High(FProblems)) then
    Exit;
  FChosen := RowIndex;
  FGrid.Invalidate;
  if Assigned(FOnSelect) then
    FOnSelect(Self, FProblems[RowIndex].Key);
end;

procedure TProblemsPanel.SetHoverRow(RowIndex: integer);
begin
  if RowIndex = FHoverRow then
    Exit;
  FHoverRow := RowIndex;
  if Assigned(FOnHover) then
    FOnHover(Self, RowKey(RowIndex));
end;

procedure TProblemsPanel.GridSelection(Sender: TObject; ACol, ARow: integer);
begin
  if not FUpdating then
    Choose(ARow);
end;

// A click on the row already current changes no selection, so the click
// itself chooses it again, to show it once more after the view has moved
procedure TProblemsPanel.GridMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  FRowBeforePress := FGrid.Row;
end;

procedure TProblemsPanel.GridClick(Sender: TObject);
begin
  if (FGrid.Row = FRowBeforePress) and (FGrid.Row = FChosen) then
    Choose(FGrid.Row);
end;

procedure TProblemsPanel.GridDoubleClick(Sender: TObject);
begin
  if (FChosen >= 0) and Assigned(FOnZoom) then
    FOnZoom(Self, RowKey(FChosen));
end;

procedure TProblemsPanel.GridMouseMove(Sender: TObject; Shift: TShiftState; X, Y: integer);
var
  Cell: TPoint;
begin
  Cell := FGrid.MouseToCell(Point(X, Y));
  if (Cell.Y >= 0) and (Cell.Y < FGrid.RowCount) and (Y < FGrid.GridHeight) then
    SetHoverRow(Cell.Y)
  else
    SetHoverRow(-1);
end;

procedure TProblemsPanel.GridMouseLeave(Sender: TObject);
begin
  SetHoverRow(-1);
end;

// Wrapped text, blocking problems in red, and only a row the user chose
// drawn as chosen
procedure TProblemsPanel.GridPrepareCanvas(Sender: TObject; ACol, ARow: integer; AState: TGridDrawState);
var
  Style: TTextStyle;
begin
  Style := FGrid.Canvas.TextStyle;
  Style.SingleLine := False;
  Style.Wordbreak := True;
  Style.Layout := tlTop;
  FGrid.Canvas.TextStyle := Style;
  if (gdSelected in AState) and (ARow <> FChosen) then
  begin
    FGrid.Canvas.Brush.Color := FGrid.Color;
    FGrid.Canvas.Font.Color := FGrid.Font.Color;
  end;
  if (ARow <= High(FProblems)) and FProblems[ARow].Blocking and not ((gdSelected in AState) and (ARow = FChosen)) then
    FGrid.Canvas.Font.Color := BLOCKING_INK;
end;

procedure TProblemsPanel.GridResize(Sender: TObject);
begin
  FitRows;
end;

end.
