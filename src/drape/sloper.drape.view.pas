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

// The drape app's 3D view: the body and the placed pieces as
// Sloper.Core.DrapeScene gives them, filled back to front, with lines across
// each seam between placed pieces. Dragging the background turns the view
// round the body, the middle button pans and the wheel zooms. Dragging a piece
// moves it across the view (with Shift, towards or away), with the modifier
// round the body, and with the right button turns it about its anchor (with
// Shift, in 15 degree steps); each drag is one undo step.
unit Sloper.Drape.View;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.DrapePlacement,
  Sloper.Core.DrapeScene, Sloper.Document.DrapeDocument;

type
  TDrapeDrag = (ddNone, ddOrbit, ddPan, ddMove, ddTurn, ddRoundBody);

  TDrapeCanvas = class(TCustomControl)
  private
    FDocument: TDrapeDocument;
    FCamera: TDrapeCamera;
    // The drape item selected, or -1
    FSelected: integer;
    FDrag: TDrapeDrag;
    FDragStart, FLastPoint: TPoint;
    // The selected piece's placement when its drag began
    FDragFrom: TDrapePlacement;
    FOnSelectionChange: TNotifyEvent;
    FOnCameraChange: TNotifyEvent;
    // Set by FitAll; the fit is made when the view next paints, at its size
    // then, as a window not yet shown has no size to fit to
    FFitPending: boolean;
    procedure FitNow;
    procedure SetSelected(AValue: integer);
    procedure SetCamera(const AValue: TDrapeCamera);
    function ScreenPoint(X, Y: integer): TVec2;
    // The dragged piece turned by the drag so far: across the screen about
    // the vertical, up and down about the view's right
    function TurnedFrom(X, Y: integer; Snap: boolean): TDrapePlacement;
    procedure CameraChanged;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean; override;
    procedure KeyDown(var Key: word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    // Turns to a view, keeping the zoom
    procedure ShowView(View: TDrapeView);
    procedure ZoomBy(Factor: double);
    // Shows the whole body and every placed piece
    procedure FitAll;
    // Ends a drag, putting the piece back
    procedure CancelDrag;
    property Document: TDrapeDocument read FDocument write FDocument;
    property Camera: TDrapeCamera read FCamera write SetCamera;
    property Selected: integer read FSelected write SetSelected;
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnCameraChange: TNotifyEvent read FOnCameraChange write FOnCameraChange;
  end;

resourcestring
  rsDrapeMovePiece = 'Move Piece';
  rsDrapeTurnPiece = 'Turn Piece';

implementation

uses
  Math, LCLType, Sloper.Core.Materials, Sloper.Core.BodyForm;

const
  // Degrees the view turns per pixel dragged
  ORBIT_DEGREES_PER_PIXEL = 0.4;
  MIN_PITCH = -89;
  MAX_PITCH = 90;
  // The zoom one wheel notch makes, and the notch's size in WheelDelta
  WHEEL_ZOOM = 1.15;
  WHEEL_NOTCH = 120;
  // Share of the view the whole scene fills when fitted
  FIT_SHARE = 0.9;
  MIN_SCALE = 0.02;
  MAX_SCALE = 20;
  BACKGROUND_COLOR: TColor = $00F4F1EE;
  PIECE_EDGE_COLOR: TColor = $00505050;
  SELECTED_EDGE_COLOR: TColor = $00D67425;
  // Pixels
  SELECTED_EDGE_WIDTH = 3;
  // Below this many pixels a press is a click, not a drag
  DRAG_THRESHOLD = 3;
  // Degrees a piece turns, or goes round the body, per pixel dragged
  TURN_DEGREES_PER_PIXEL = 0.5;
  // Turns snap to this with Shift
  TURN_SNAP = 15;
  SEAM_LINE_COLOR: TColor = $002F6BE0;

constructor TDrapeCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCamera := DefaultDrapeCamera;
  FSelected := -1;
  DoubleBuffered := True;
  TabStop := True;
  Color := BACKGROUND_COLOR;
end;

function TDrapeCanvas.ScreenPoint(X, Y: integer): TVec2;
begin
  Result := Vec2(X - ClientWidth / 2, Y - ClientHeight / 2);
end;

function TDrapeCanvas.TurnedFrom(X, Y: integer; Snap: boolean): TDrapePlacement;
var
  Across, Tip: double;
begin
  Across := (X - FDragStart.X) * TURN_DEGREES_PER_PIXEL;
  Tip := (Y - FDragStart.Y) * TURN_DEGREES_PER_PIXEL;
  if Snap then
  begin
    Across := SnappedAngle(Across, TURN_SNAP);
    Tip := SnappedAngle(Tip, TURN_SNAP);
  end;
  Result := TurnedPlacement(TurnedPlacement(FDragFrom, Vec3(0, 0, 1), Across), FCamera.Right, Tip);
end;

procedure TDrapeCanvas.CameraChanged;
begin
  Invalidate;
  if Assigned(FOnCameraChange) then
    FOnCameraChange(Self);
end;

procedure TDrapeCanvas.SetCamera(const AValue: TDrapeCamera);
begin
  FCamera := AValue;
  CameraChanged;
end;

procedure TDrapeCanvas.SetSelected(AValue: integer);
begin
  if Assigned(FDocument) and ((AValue < 0) or (AValue > High(FDocument.Drape.Items))) then
    AValue := -1;
  if FSelected = AValue then
    Exit;
  FSelected := AValue;
  Invalidate;
  if Assigned(FOnSelectionChange) then
    FOnSelectionChange(Self);
end;

procedure TDrapeCanvas.Paint;
var
  Faces: TDrapeFaceArray;
  Face: TDrapeFace;
  Points: array of TPoint;
  Index: integer;
  Middle: TVec2;
  Line: TDrapeLine;
begin
  Canvas.Brush.Color := Color;
  Canvas.FillRect(ClientRect);
  if not Assigned(FDocument) then
    Exit;
  if FFitPending then
    FitNow;
  Faces := BuildDrapeScene(FDocument.Drape, FCamera);
  Middle := Vec2(ClientWidth / 2, ClientHeight / 2);
  Points := nil;
  for Face in Faces do
  begin
    SetLength(Points, Length(Face.Points));
    for Index := 0 to High(Face.Points) do
      Points[Index] := Point(Round(Face.Points[Index].X + Middle.X), Round(Face.Points[Index].Y + Middle.Y));
    Canvas.Brush.Color := RGBToColor(Face.Color.Red, Face.Color.Green, Face.Color.Blue);
    Canvas.Pen.Width := 1;
    // The body's triangles are edged in their own colour, so no seams show
    if Face.Item < 0 then
      Canvas.Pen.Color := Canvas.Brush.Color
    else if Face.Item = FSelected then
    begin
      Canvas.Pen.Color := SELECTED_EDGE_COLOR;
      Canvas.Pen.Width := Scale96ToForm(SELECTED_EDGE_WIDTH);
    end
    else
      Canvas.Pen.Color := PIECE_EDGE_COLOR;
    Canvas.Polygon(Points);
  end;
  Canvas.Pen.Color := SEAM_LINE_COLOR;
  Canvas.Pen.Width := 1;
  for Line in DrapeSceneLines(FDocument.Drape, FCamera) do
    Canvas.Line(Round(Line.From.X + Middle.X), Round(Line.From.Y + Middle.Y), Round(Line.Onto.X + Middle.X), Round(Line.Onto.Y + Middle.Y));
end;

procedure TDrapeCanvas.ShowView(View: TDrapeView);
begin
  Camera := CameraForView(FCamera, View);
end;

procedure TDrapeCanvas.ZoomBy(Factor: double);
begin
  FCamera.Scale := EnsureRange(FCamera.Scale * Factor, MIN_SCALE, MAX_SCALE);
  CameraChanged;
end;

procedure TDrapeCanvas.FitAll;
begin
  FFitPending := True;
  Invalidate;
end;

procedure TDrapeCanvas.FitNow;
var
  Low, High, Point: TVec3;
  Measures: TBodyMeasures;
  Mesh: TBodyMesh;
  Index: integer;
  Points: TVec3Array;
  Started: boolean;
  Span: double;

  procedure Grow(const Each: TVec3);
  begin
    if not Started then
    begin
      Low := Each;
      High := Each;
      Started := True;
    end;
    Low := Vec3(Min(Low.X, Each.X), Min(Low.Y, Each.Y), Min(Low.Z, Each.Z));
    High := Vec3(Max(High.X, Each.X), Max(High.Y, Each.Y), Max(High.Z, Each.Z));
  end;

begin
  FFitPending := False;
  if not Assigned(FDocument) then
    Exit;
  Started := False;
  Low := Vec3(0, 0, 0);
  High := Low;
  if FDocument.Drape.BodyMeasures(Measures) then
  begin
    Mesh := BuildBodyForm(Measures);
    for Point in Mesh.Vertices do
      Grow(Point);
  end;
  for Index := 0 to System.High(FDocument.Drape.Items) do
    if FDocument.Drape.PlacedOutline(FDocument.Drape.Items[Index].Piece, Points) then
      for Point in Points do
        Grow(Point);
  if not Started then
    Exit;
  // The diagonal fits from every side, so turning the view keeps it in
  Span := Max(Distance3(Low, High), 1);
  FCamera.Target := (Low + High) * 0.5;
  FCamera.Scale := EnsureRange(FIT_SHARE * Min(ClientWidth, ClientHeight) / Span, MIN_SCALE, MAX_SCALE);
  if Assigned(FOnCameraChange) then
    FOnCameraChange(Self);
end;

procedure TDrapeCanvas.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Picked: integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  SetFocus;
  if not Assigned(FDocument) or (FDrag <> ddNone) then
    Exit;
  FDragStart := Point(X, Y);
  FLastPoint := FDragStart;
  if Button = mbMiddle then
    FDrag := ddPan
  else if Button in [mbLeft, mbRight] then
  begin
    Picked := DrapePieceAt(BuildDrapeScene(FDocument.Drape, FCamera), ScreenPoint(X, Y));
    if Picked >= 0 then
    begin
      Selected := Picked;
      FDragFrom := FDocument.Drape.Items[Picked].Placement;
      if Button = mbRight then
      begin
        FDocument.BeginChange(rsDrapeTurnPiece);
        FDrag := ddTurn;
      end
      else
      begin
        FDocument.BeginChange(rsDrapeMovePiece);
        if ssModifier in Shift then
          FDrag := ddRoundBody
        else
          FDrag := ddMove;
      end;
    end
    else if Button = mbLeft then
      FDrag := ddOrbit;
  end;
end;

procedure TDrapeCanvas.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Delta: TVec2;
  Moved: TDrapePlacement;
begin
  inherited MouseMove(Shift, X, Y);
  case FDrag of
    ddOrbit:
    begin
      FCamera.Yaw := NormalizeAngle(FCamera.Yaw - (X - FLastPoint.X) * ORBIT_DEGREES_PER_PIXEL);
      FCamera.Pitch := EnsureRange(FCamera.Pitch + (Y - FLastPoint.Y) * ORBIT_DEGREES_PER_PIXEL, MIN_PITCH, MAX_PITCH);
      CameraChanged;
    end;
    ddPan:
    begin
      FCamera.Target := FCamera.Target - FCamera.ScreenToWorld(Vec2(X - FLastPoint.X, Y - FLastPoint.Y));
      CameraChanged;
    end;
    ddMove:
    begin
      Delta := Vec2(X - FDragStart.X, Y - FDragStart.Y);
      Moved := FDragFrom;
      // Up the screen is away from the viewer
      if ssShift in Shift then
        Moved.Position := Moved.Position - FCamera.Forward * (Delta.Y / FCamera.Scale)
      else
        Moved.Position := Moved.Position + FCamera.ScreenToWorld(Delta);
      FDocument.Drape.Items[FSelected].Placement := Moved;
      FDocument.LiveUpdate;
    end;
    ddTurn:
    begin
      FDocument.Drape.Items[FSelected].Placement := TurnedFrom(X, Y, ssShift in Shift);
      FDocument.LiveUpdate;
    end;
    ddRoundBody:
    begin
      FDocument.Drape.Items[FSelected].Placement := RoundBodyPlacement(FDragFrom, (X - FDragStart.X) * TURN_DEGREES_PER_PIXEL);
      FDocument.LiveUpdate;
    end;
  end;
  FLastPoint := Point(X, Y);
end;

procedure TDrapeCanvas.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  case FDrag of
    ddMove, ddTurn, ddRoundBody:
    begin
      // A click without a drag only selects; an unchanged file adds no step
      if Max(Abs(X - FDragStart.X), Abs(Y - FDragStart.Y)) < DRAG_THRESHOLD then
        FDocument.Drape.Items[FSelected].Placement := FDragFrom;
      FDocument.EndChange;
    end;
    ddOrbit:
      if Max(Abs(X - FDragStart.X), Abs(Y - FDragStart.Y)) < DRAG_THRESHOLD then
        Selected := -1;
  end;
  FDrag := ddNone;
end;

// Putting the placement back leaves the file as it was, so ending the change
// adds no step, and the patterns are not read again as CancelChange would
procedure TDrapeCanvas.CancelDrag;
begin
  if FDrag in [ddMove, ddTurn, ddRoundBody] then
  begin
    FDocument.Drape.Items[FSelected].Placement := FDragFrom;
    FDocument.EndChange;
    FDocument.LiveUpdate;
  end;
  FDrag := ddNone;
end;

function TDrapeCanvas.DoMouseWheel(Shift: TShiftState; WheelDelta: integer; MousePos: TPoint): boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then
    Exit;
  ZoomBy(Power(WHEEL_ZOOM, WheelDelta / WHEEL_NOTCH));
  Result := True;
end;

procedure TDrapeCanvas.KeyDown(var Key: word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if FDrag <> ddNone then
      CancelDrag
    else
      Selected := -1;
    Key := 0;
  end;
  inherited KeyDown(Key, Shift);
end;

end.
