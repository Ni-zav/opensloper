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

// The publish preview without its drawing: how layout millimetres map to
// screen pixels, what is under the cursor, and dragging pieces and notes, for
// the desktop's preview and the web page's alike. Both y axes point down.
// Kept free of the LCL so it can be unit-tested.
unit Sloper.Output.Preview;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.TextFields, Sloper.Output.Layout, Sloper.Output.Tiling, Sloper.Output.LayoutDocument;

const
  PREVIEW_ZOOM_STEP = 1.25;
  // Placements land on this grid, in mm
  PLACEMENT_STEP = 0.5;

type
  TPreviewView = record
    // Pixels per millimetre
    Scale: double;
    // Screen position of the layout's top left
    OriginX, OriginY: double;
    function ToScreen(const LayoutPoint: TVec2): TVec2;
    function ToLayout(const ScreenPoint: TVec2): TVec2;
    // Zooms by Factor keeping the layout point under Anchor (screen) still
    procedure ZoomAt(Factor: double; const Anchor: TVec2);
    procedure Pan(DX, DY: double);
    // Shows Area centred in a Width x Height view, with Margin pixels around it
    procedure Fit(const Area: TRect2; Width, Height, Margin: double);
    // Fills a Width x Height view with the box between two screen corners
    procedure ZoomToBox(const Corner, OtherCorner: TVec2; Width, Height: double);
  end;

  // A press on the pages and the drag after it. Press holds the note or piece
  // under the point; MoveTo moves it there, held where it was grabbed, on
  // the placement grid. The first move opens one undo step, which Release
  // ends. The layout may be read again between moves, as undo does, so a
  // move that finds its piece gone cancels the step.
  TPreviewDrag = class
  private
    FDocument: TLayoutDocument;
    FPlacement, FNote: integer;
    FGrab: TVec2;
    FMoving: boolean;
  public
    constructor Create(ADocument: TLayoutDocument);
    // Notes lie over pieces, so one is found first; else the smallest piece
    // of Shapes. Placement and Note say what was found, -1 for neither.
    procedure Press(const Shapes: TPlacedPieceArray; const At: TVec2);
    // The piece or note pressed is still there
    function Holds: boolean;
    // False, with the step cancelled, when nothing is held
    function MoveTo(const At: TVec2): boolean;
    // Ends the step a move opened, and lets go
    procedure Release;
    // Puts back what the moves changed, and lets go
    procedure Cancel;
    // Places a copy from the tray with its middle at At, one undo step; its
    // placement index, or -1 when its piece cannot be placed
    function DropCopy(const Item: TUnplacedCopy; const At: TVec2): integer;
    property Placement: integer read FPlacement;
    property Note: integer read FNote;
    property Moving: boolean read FMoving;
  end;

resourcestring
  rsPreviewMove = 'Move piece';
  rsPreviewMoveNote = 'Move note';

function DefaultPreviewView: TPreviewView;
// The index in Shapes of the smallest piece containing At, or -1
function ShapeAt(const Shapes: TPlacedPieceArray; const At: TVec2): integer;
// The index of the note covering At, the last drawn first, or -1
function NoteAt(const Notes: TSheetNoteArray; const Values: TFieldValues; const At: TVec2): integer;
// The caption of the page At falls on, nearest its middle where two overlap;
// '' when there is none
function PageCaptionAt(const Pages: TTilePageArray; const At: TVec2): string;
// The area every page covers; False when there are none
function PagesBounds(const Pages: TTilePageArray; out Bounds: TRect2): boolean;
function RoundToStep(Value: double): double;

implementation

uses
  Math;

const
  MIN_PREVIEW_SCALE = 0.02;
  MAX_PREVIEW_SCALE = 20;

function DefaultPreviewView: TPreviewView;
begin
  Result.Scale := 1;
  Result.OriginX := 0;
  Result.OriginY := 0;
end;

function TPreviewView.ToScreen(const LayoutPoint: TVec2): TVec2;
begin
  Result := Vec2(LayoutPoint.X * Scale + OriginX, LayoutPoint.Y * Scale + OriginY);
end;

function TPreviewView.ToLayout(const ScreenPoint: TVec2): TVec2;
begin
  Result := Vec2((ScreenPoint.X - OriginX) / Scale, (ScreenPoint.Y - OriginY) / Scale);
end;

procedure TPreviewView.ZoomAt(Factor: double; const Anchor: TVec2);
var
  Held: TVec2;
begin
  Held := ToLayout(Anchor);
  Scale := EnsureRange(Scale * Factor, MIN_PREVIEW_SCALE, MAX_PREVIEW_SCALE);
  OriginX := Anchor.X - Held.X * Scale;
  OriginY := Anchor.Y - Held.Y * Scale;
end;

procedure TPreviewView.Pan(DX, DY: double);
begin
  OriginX := OriginX + DX;
  OriginY := OriginY + DY;
end;

procedure TPreviewView.Fit(const Area: TRect2; Width, Height, Margin: double);
var
  AreaWidth, AreaHeight: double;
begin
  AreaWidth := Max(Area.MaxX - Area.MinX, 1);
  AreaHeight := Max(Area.MaxY - Area.MinY, 1);
  Scale := EnsureRange(Min((Width - 2 * Margin) / AreaWidth, (Height - 2 * Margin) / AreaHeight), MIN_PREVIEW_SCALE, MAX_PREVIEW_SCALE);
  OriginX := (Width - AreaWidth * Scale) / 2 - Area.MinX * Scale;
  OriginY := (Height - AreaHeight * Scale) / 2 - Area.MinY * Scale;
end;

procedure TPreviewView.ZoomToBox(const Corner, OtherCorner: TVec2; Width, Height: double);
var
  First, Last: TVec2;
  Box: TRect2;
begin
  First := ToLayout(Corner);
  Last := ToLayout(OtherCorner);
  Box.MinX := Min(First.X, Last.X);
  Box.MaxX := Max(First.X, Last.X);
  Box.MinY := Min(First.Y, Last.Y);
  Box.MaxY := Max(First.Y, Last.Y);
  Fit(Box, Width, Height, 0);
end;

function ShapeAt(const Shapes: TPlacedPieceArray; const At: TVec2): integer;
var
  Index: integer;
  Size, Best: double;
begin
  Result := -1;
  Best := Infinity;
  for Index := 0 to High(Shapes) do
  begin
    Size := Abs(SignedArea(Shapes[Index].CutLine));
    if (Size < Best) and PointInPolygon(At, Shapes[Index].CutLine) then
    begin
      Best := Size;
      Result := Index;
    end;
  end;
end;

function NoteAt(const Notes: TSheetNoteArray; const Values: TFieldValues; const At: TVec2): integer;
var
  Spread: TRect2;
begin
  for Result := High(Notes) downto 0 do
  begin
    Spread := NoteBounds(Notes[Result], Values);
    if (At.X >= Spread.MinX) and (At.X <= Spread.MaxX) and (At.Y >= Spread.MinY) and (At.Y <= Spread.MaxY) then
      Exit;
  end;
  Result := -1;
end;

function PageCaptionAt(const Pages: TTilePageArray; const At: TVec2): string;
var
  Page: TTilePage;
  Middle: TVec2;
  Best: double;
begin
  Result := '';
  Best := Infinity;
  for Page in Pages do
    if (At.X >= Page.Area.MinX) and (At.X <= Page.Area.MaxX) and (At.Y >= Page.Area.MinY) and (At.Y <= Page.Area.MaxY) then
    begin
      Middle := Vec2((Page.Area.MinX + Page.Area.MaxX) / 2, (Page.Area.MinY + Page.Area.MaxY) / 2);
      if Distance(Middle, At) < Best then
      begin
        Best := Distance(Middle, At);
        Result := Page.Caption;
      end;
    end;
end;

function PagesBounds(const Pages: TTilePageArray; out Bounds: TRect2): boolean;
var
  Page: TTilePage;
begin
  Bounds := Default(TRect2);
  Result := Length(Pages) > 0;
  if not Result then
    Exit;
  Bounds := Pages[0].Area;
  for Page in Pages do
  begin
    Bounds.MinX := Min(Bounds.MinX, Page.Area.MinX);
    Bounds.MinY := Min(Bounds.MinY, Page.Area.MinY);
    Bounds.MaxX := Max(Bounds.MaxX, Page.Area.MaxX);
    Bounds.MaxY := Max(Bounds.MaxY, Page.Area.MaxY);
  end;
end;

function RoundToStep(Value: double): double;
begin
  Result := Round(Value / PLACEMENT_STEP) * PLACEMENT_STEP;
end;

constructor TPreviewDrag.Create(ADocument: TLayoutDocument);
begin
  inherited Create;
  FDocument := ADocument;
  FPlacement := -1;
  FNote := -1;
end;

procedure TPreviewDrag.Press(const Shapes: TPlacedPieceArray; const At: TVec2);
var
  Layout: TLayout;
  Hit: integer;
begin
  Release;
  Layout := FDocument.Layout;
  FPlacement := -1;
  FNote := NoteAt(Layout.Notes, Layout.FieldValues('', ''), At);
  if FNote >= 0 then
  begin
    FGrab := Vec2(Layout.Notes[FNote].X - At.X, Layout.Notes[FNote].Y - At.Y);
    Exit;
  end;
  Hit := ShapeAt(Shapes, At);
  if Hit < 0 then
    Exit;
  FPlacement := Shapes[Hit].Placement;
  FGrab := Vec2(Layout.Placements[FPlacement].X - At.X, Layout.Placements[FPlacement].Y - At.Y);
end;

function TPreviewDrag.Holds: boolean;
begin
  if FNote >= 0 then
    Result := FNote < Length(FDocument.Layout.Notes)
  else
    Result := (FPlacement >= 0) and (FPlacement < Length(FDocument.Layout.Placements));
end;

function TPreviewDrag.MoveTo(const At: TVec2): boolean;
begin
  Result := Holds;
  if not Result then
  begin
    if FMoving then
      FDocument.CancelChange;
    FMoving := False;
    FPlacement := -1;
    FNote := -1;
    Exit;
  end;
  if not FMoving then
  begin
    if FNote >= 0 then
      FDocument.BeginChange(rsPreviewMoveNote)
    else
      FDocument.BeginChange(rsPreviewMove);
    FMoving := True;
  end;
  if FNote >= 0 then
  begin
    FDocument.Layout.Notes[FNote].X := RoundToStep(At.X + FGrab.X);
    FDocument.Layout.Notes[FNote].Y := RoundToStep(At.Y + FGrab.Y);
  end
  else
  begin
    FDocument.Layout.Placements[FPlacement].X := RoundToStep(At.X + FGrab.X);
    FDocument.Layout.Placements[FPlacement].Y := RoundToStep(At.Y + FGrab.Y);
  end;
  FDocument.LiveUpdate;
end;

procedure TPreviewDrag.Release;
begin
  if FMoving then
    FDocument.EndChange;
  FMoving := False;
end;

procedure TPreviewDrag.Cancel;
begin
  if FMoving then
    FDocument.CancelChange;
  FMoving := False;
end;

function TPreviewDrag.DropCopy(const Item: TUnplacedCopy; const At: TVec2): integer;
begin
  Release;
  if not Item.CanPlace then
    Exit(-1);
  FDocument.BeginChange(rsLayoutPlaceOne);
  Result := FDocument.Layout.PlaceCopyAt(Item, At, PLACEMENT_STEP);
  FDocument.EndChange;
end;

end.
