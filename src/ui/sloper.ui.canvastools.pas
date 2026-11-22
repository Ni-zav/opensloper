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

// The canvas's drawing tools, one object each: what a click, a move or a key
// does, what the tool snaps to and labels, what it draws over the pattern and
// the state it keeps between clicks. The canvas keeps pan, zoom, the gesture
// rules and the select tool's drags and boxes, and hands the rest to the tool
// in use. The table of tools is Sloper.Editor.Tools.
unit Sloper.UI.CanvasTools;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Shortcuts,
  Sloper.Document.PatternDocument, Sloper.Editor.View, Sloper.Editor.Snap, Sloper.UI.CanvasInput, Sloper.UI.PatternPainter,
  Sloper.Core.IconSet, Sloper.Editor.Tools, Sloper.Editor.SelectionEdits;

type
  // What a tool needs of the canvas
  TCanvasToolHost = class
  public
    function Document: TPatternDocument; virtual; abstract;
    function View: TViewTransform; virtual; abstract;
    // The role of the edges drawn next
    function DrawRole: TEdgeRole; virtual; abstract;
    procedure Select(const Keys: TStringArray); virtual; abstract;
    // A hint or the reason something could not be done
    procedure ShowMessage(const AText: string); virtual; abstract;
    // The canvas needs painting again
    procedure Refresh; virtual; abstract;
    // A note was placed and selected, ready for its text
    procedure NoteAdded; virtual; abstract;
  end;

  // A tool does nothing unless it says otherwise. Positions are in screen
  // pixels, and the host has a document whenever a handler is called.
  TCanvasToolHandler = class
  private
    FHost: TCanvasToolHost;
  protected
    function ModelAt(X, Y: integer): TVec2;
    // Selects what the edit says and shows its message
    procedure ApplyEdit(const Edit: TSelectionEdit);
    property Host: TCanvasToolHost read FHost;
  public
    constructor Create(AHost: TCanvasToolHost);
    // What the status bar says while the tool is chosen
    function Hint: string; virtual; abstract;
    // Drops what the tool is part way through, as when another is chosen
    procedure Reset; virtual;
    // A press that starts no gesture of the canvas's own; Shift holds the
    // modifier keys
    procedure Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer); virtual;
    // The pointer moving with no button held
    procedure Move(X, Y: integer); virtual;
    // Escape: True when it dropped something the tool was part way through
    function Cancel: boolean; virtual;
    // Keys besides Escape that the tool takes, which the canvas then keeps from moving the focus
    function HandlesKey(Key: word): boolean; virtual;
    // Only between gestures
    procedure KeyDown(Key: word; Shift: TShiftState); virtual;
    // Undo or redo replaced the pattern's objects, so keys held may be gone
    procedure ObjectsReplaced; virtual;
    // The pointer left the canvas; True when the canvas needs painting again
    function Leave: boolean; virtual;
    // The objects the tool is working with, to label them
    function LabelKeys: TStringArray; virtual;
    procedure AddToPaintState(var State: TPaintState); virtual;
    // Over the pattern and its labels
    procedure Paint(Painter: TPatternPainter); virtual;
  end;

  TCanvasToolHandlers = array[TCanvasTool] of TCanvasToolHandler;

// One of each tool, all working with Host; the caller frees them
function CreateCanvasTools(Host: TCanvasToolHost): TCanvasToolHandlers;
procedure FreeCanvasTools(var Tools: TCanvasToolHandlers);

resourcestring
  rsToolAddNote = 'Add note';
  rsToolNewNoteText = 'Text';
  rsToolCalloutBox = 'Click where the callout''s text goes';
  rsToolAddCallout = 'Add callout';

implementation

uses
  LCLType, Sloper.Core.Evaluator, Sloper.Core.Pattern, Sloper.Core.Units, Sloper.Core.Note, Sloper.Core.Drag, Sloper.Editor.Scene,
  Sloper.Editor.ToolEdits;

type
  // Selecting and dragging are the canvas's own gestures
  TSelectTool = class(TCanvasToolHandler)
  public
    function Hint: string; override;
  end;

  // So is zooming, which uses the select tool's box
  TZoomTool = class(TCanvasToolHandler)
  public
    function Hint: string; override;
  end;

  // Clicks where the pointer snaps, once or twice; a second click goes from
  // the first, and right click or Escape drops the first
  TSnapTool = class(TCanvasToolHandler)
  protected
    FSnap: TSnap;
    FSnapShown: boolean;
    // Where the pointer was when the snap was found
    FSnapClick: TVec2;
    // The first click
    FStart: TSnap;
    FHasStart: boolean;
    // Shift was held for the click being handled
    FShiftClick: boolean;
    procedure UpdateSnap(X, Y: integer);
    // What the status bar says about the snap
    function SnapMessage: string; virtual;
    // What the second click would make
    function Preview: TSnapPreview; virtual;
    procedure Click; virtual; abstract;
  public
    procedure Reset; override;
    procedure Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer); override;
    procedure Move(X, Y: integer); override;
    function Cancel: boolean; override;
    procedure ObjectsReplaced; override;
    function Leave: boolean; override;
    function LabelKeys: TStringArray; override;
    procedure Paint(Painter: TPatternPainter); override;
  end;

  TPointTool = class(TSnapTool)
  protected
    procedure Click; override;
  public
    function Hint: string; override;
  end;

  // Lines and curves carry on from the end of the last, as a chain. A
  // Shift+click carries the last curve on through the point instead, as one
  // curve path.
  TEdgeTool = class(TSnapTool)
  private
    FCurve: boolean;
    // The curve or curve path the last click made, which ends at FStart
    FLastEdge: string;
    procedure AddEdge;
    procedure ExtendLastEdge;
    procedure CarryOnFrom(const EndKey, EdgeKey: string);
  protected
    procedure Click; override;
  public
    constructor Create(AHost: TCanvasToolHost; Curve: boolean);
    function Hint: string; override;
  end;

  // A circle from its centre, or a rectangle from a corner; the second click
  // gives only the size, and makes no point
  TShapeTool = class(TSnapTool)
  private
    FCircle: boolean;
    procedure AddShape;
  protected
    function SnapMessage: string; override;
    function Preview: TSnapPreview; override;
    procedure Click; override;
  public
    constructor Create(AHost: TCanvasToolHost; Circle: boolean);
    function Hint: string; override;
  end;

  TTextTool = class(TSnapTool)
  protected
    function SnapMessage: string; override;
    procedure Click; override;
  public
    function Hint: string; override;
  end;

  TCalloutTool = class(TSnapTool)
  private
    // Where the first click was
    FStartClick: TVec2;
    procedure StartCallout;
    procedure AddCallout;
  protected
    function SnapMessage: string; override;
    procedure Click; override;
  public
    function Hint: string; override;
  end;

  // One click makes one piece, with the default allowance to edit in the
  // properties; a region that already has a piece selects that piece
  TPieceTool = class(TCanvasToolHandler)
  public
    function Hint: string; override;
    procedure Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer); override;
  end;

  // A click on a notch removes it; one on a piece's edge adds one
  TNotchTool = class(TCanvasToolHandler)
  public
    function Hint: string; override;
    procedure Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer); override;
  end;

  // Clicks pick the edges of side A, Tab moves to side B, Enter makes the seam
  TSeamTool = class(TCanvasToolHandler)
  private
    FSideA, FSideB: TSeamSide;
    FOnB: boolean;
    function Picking: boolean;
    procedure ShowProgress;
    procedure MakeSeam;
  public
    function Hint: string; override;
    procedure Reset; override;
    procedure Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer); override;
    function Cancel: boolean; override;
    function HandlesKey(Key: word): boolean; override;
    procedure KeyDown(Key: word; Shift: TShiftState); override;
    procedure ObjectsReplaced; override;
    procedure AddToPaintState(var State: TPaintState); override;
  end;

function CreateCanvasTools(Host: TCanvasToolHost): TCanvasToolHandlers;
begin
  Result := Default(TCanvasToolHandlers);
  try
    Result[ctSelect] := TSelectTool.Create(Host);
    Result[ctZoom] := TZoomTool.Create(Host);
    Result[ctPoint] := TPointTool.Create(Host);
    Result[ctLine] := TEdgeTool.Create(Host, False);
    Result[ctCurve] := TEdgeTool.Create(Host, True);
    Result[ctCircle] := TShapeTool.Create(Host, True);
    Result[ctRectangle] := TShapeTool.Create(Host, False);
    Result[ctPiece] := TPieceTool.Create(Host);
    Result[ctNotch] := TNotchTool.Create(Host);
    Result[ctSeam] := TSeamTool.Create(Host);
    Result[ctText] := TTextTool.Create(Host);
    Result[ctCallout] := TCalloutTool.Create(Host);
  except
    FreeCanvasTools(Result);
    raise;
  end;
end;

procedure FreeCanvasTools(var Tools: TCanvasToolHandlers);
var
  Tool: TCanvasTool;
begin
  for Tool := Low(TCanvasTool) to High(TCanvasTool) do
    FreeAndNil(Tools[Tool]);
end;

{ TCanvasToolHandler }

constructor TCanvasToolHandler.Create(AHost: TCanvasToolHost);
begin
  inherited Create;
  FHost := AHost;
end;

function TCanvasToolHandler.ModelAt(X, Y: integer): TVec2;
begin
  Result := FHost.View.ToModel(Vec2(X, Y));
end;

procedure TCanvasToolHandler.ApplyEdit(const Edit: TSelectionEdit);
begin
  if Edit.Reselect then
    Host.Select(Edit.Selection);
  if Edit.Message <> '' then
    Host.ShowMessage(Edit.Message);
end;

procedure TCanvasToolHandler.Reset;
begin
end;

procedure TCanvasToolHandler.Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer);
begin
end;

procedure TCanvasToolHandler.Move(X, Y: integer);
begin
end;

function TCanvasToolHandler.Cancel: boolean;
begin
  Result := False;
end;

function TCanvasToolHandler.HandlesKey(Key: word): boolean;
begin
  Result := False;
end;

procedure TCanvasToolHandler.KeyDown(Key: word; Shift: TShiftState);
begin
end;

procedure TCanvasToolHandler.ObjectsReplaced;
begin
end;

function TCanvasToolHandler.Leave: boolean;
begin
  Result := False;
end;

function TCanvasToolHandler.LabelKeys: TStringArray;
begin
  Result := nil;
end;

procedure TCanvasToolHandler.AddToPaintState(var State: TPaintState);
begin
end;

procedure TCanvasToolHandler.Paint(Painter: TPatternPainter);
begin
end;

{ TSelectTool }

function TSelectTool.Hint: string;
begin
  Result := rsToolSelectHint;
end;

{ TZoomTool }

function TZoomTool.Hint: string;
begin
  Result := rsToolZoomHint;
end;

{ TSnapTool }

procedure TSnapTool.Reset;
begin
  FHasStart := False;
  FSnapShown := False;
end;

procedure TSnapTool.UpdateSnap(X, Y: integer);
var
  AnchorKey: string;
begin
  AnchorKey := '';
  // A line lines up with its start first, once that start is a point
  if FHasStart and (FStart.Kind = snPoint) then
    AnchorKey := FStart.PointKey;
  FSnap := FindSnap(Host.Document.Pattern, ModelAt(X, Y), Host.View.PixelsToMM(SNAP_RADIUS), AnchorKey);
  FSnapClick := ModelAt(X, Y);
  FSnapShown := True;
  Host.ShowMessage(SnapMessage);
  Host.Refresh;
end;

function TSnapTool.SnapMessage: string;
begin
  Result := SnapDescription(Host.Document.Pattern, FSnap);
end;

function TSnapTool.Preview: TSnapPreview;
begin
  if FHasStart then
    Result := spLine
  else
    Result := spNone;
end;

// Right click stops a line or curve
procedure TSnapTool.Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer);
begin
  if Button = cbRight then
    Cancel
  else if Button = cbLeft then
  begin
    UpdateSnap(X, Y);
    FShiftClick := ssShift in Shift;
    Click;
    Host.Refresh;
  end;
end;

procedure TSnapTool.Move(X, Y: integer);
begin
  UpdateSnap(X, Y);
end;

function TSnapTool.Cancel: boolean;
begin
  Result := FHasStart;
  FHasStart := False;
  Host.Refresh;
end;

// The first click may name objects that undo removed
procedure TSnapTool.ObjectsReplaced;
begin
  Reset;
end;

function TSnapTool.Leave: boolean;
begin
  Result := FSnapShown;
  FSnapShown := False;
end;

function TSnapTool.LabelKeys: TStringArray;
begin
  Result := nil;
  if FHasStart then
    Result := SnapObjectKeys(FStart);
  if FSnapShown then
    Result := Concat(Result, SnapObjectKeys(FSnap));
end;

procedure TSnapTool.Paint(Painter: TPatternPainter);
begin
  if FSnapShown then
    Painter.DrawSnap(FSnap, Preview, FStart.Position);
end;

{ TPointTool }

function TPointTool.Hint: string;
begin
  Result := rsToolPointHint;
end;

// A click on a point selects it
procedure TPointTool.Click;
begin
  ApplyEdit(AddPointFromSnap(Host.Document, FSnap));
end;

{ TEdgeTool }

constructor TEdgeTool.Create(AHost: TCanvasToolHost; Curve: boolean);
begin
  inherited Create(AHost);
  FCurve := Curve;
end;

function TEdgeTool.Hint: string;
begin
  if FCurve then
    Result := rsToolCurveHint
  else
    Result := rsToolLineHint;
end;

procedure TEdgeTool.Click;
begin
  if not FHasStart then
  begin
    FStart := FSnap;
    FHasStart := True;
    FLastEdge := '';
  end
  else if FCurve and FShiftClick and (FLastEdge <> '') then
    ExtendLastEdge
  else
    AddEdge;
end;

// The second click: both ends and the edge are one change
procedure TEdgeTool.AddEdge;
var
  Edit: TSelectionEdit;
  EndKey: string;
begin
  Edit := AddEdgeFromSnaps(Host.Document, FStart, FSnap, FCurve, Host.DrawRole, EndKey);
  ApplyEdit(Edit);
  if Edit.Done then
    CarryOnFrom(EndKey, Edit.Selection[0])
  else if Edit.Message <> '' then
    FHasStart := False;
end;

// The point, made if need be, and the longer path are one change; the edge
// keeps its key, so the next Shift+click carries it on again
procedure TEdgeTool.ExtendLastEdge;
var
  Edit: TSelectionEdit;
  EndKey: string;
begin
  Edit := ExtendCurveToSnap(Host.Document, FLastEdge, FStart, FSnap, Host.DrawRole, EndKey);
  ApplyEdit(Edit);
  if Edit.Done then
    CarryOnFrom(EndKey, Edit.Selection[0]);
end;

// The next edge starts where the last ended; a curve can be carried on
procedure TEdgeTool.CarryOnFrom(const EndKey, EdgeKey: string);
begin
  FStart := Default(TSnap);
  FStart.Kind := snPoint;
  FStart.PointKey := EndKey;
  FStart.Position := TPointObject(Host.Document.Pattern.FindNode(EndKey)).Position;
  FHasStart := True;
  FLastEdge := '';
  if FCurve then
    FLastEdge := EdgeKey;
end;

{ TShapeTool }

constructor TShapeTool.Create(AHost: TCanvasToolHost; Circle: boolean);
begin
  inherited Create(AHost);
  FCircle := Circle;
end;

function TShapeTool.Hint: string;
begin
  if FCircle then
    Result := rsToolCircleHint
  else
    Result := rsToolRectangleHint;
end;

function TShapeTool.SnapMessage: string;
begin
  if not FHasStart then
    Exit(inherited SnapMessage);
  Result := ShapeSizeText(Host.Document.Pattern, FStart.Position, FSnap.Position, FCircle);
end;

function TShapeTool.Preview: TSnapPreview;
begin
  if not FHasStart then
    Result := spNone
  else if FCircle then
    Result := spCircle
  else
    Result := spRectangle;
end;

procedure TShapeTool.Click;
begin
  if FHasStart then
    AddShape
  else
  begin
    FStart := FSnap;
    FHasStart := True;
    if FCircle then
      Host.ShowMessage(rsToolCircleRim)
    else
      Host.ShowMessage(rsToolRectangleCorner);
  end;
end;

// The first point, made if need be, and the shape are one change. The tool
// stays on for the next.
procedure TShapeTool.AddShape;
begin
  FHasStart := False;
  ApplyEdit(AddShapeFromSnap(Host.Document, FStart, FSnap.Position, FCircle, Host.DrawRole));
  Host.Refresh;
end;

{ TTextTool }

function TTextTool.Hint: string;
begin
  Result := rsToolTextHint;
end;

function TTextTool.SnapMessage: string;
begin
  Result := NoteSnapDescription(Host.Document.Pattern, FSnap, FSnapClick);
end;

// The note is selected, ready for its text to be typed in the properties
procedure TTextTool.Click;
var
  Document: TPatternDocument;
  Note: TNoteObject;
  Key, Reason: string;
begin
  Document := Host.Document;
  Document.BeginChange(rsToolAddNote);
  Note := NoteFromSnap(Document.Pattern, FSnap, FSnapClick, rsToolNewNoteText);
  Reason := Document.Pattern.LastError;
  Key := '';
  if Assigned(Note) then
    Key := Note.Key;
  if not Document.Commit(Assigned(Note)) then
  begin
    Host.ShowMessage(Reason);
    Exit;
  end;
  Host.Select([Key]);
  Host.NoteAdded;
end;

{ TCalloutTool }

function TCalloutTool.Hint: string;
begin
  Result := rsToolCalloutHint;
end;

function TCalloutTool.SnapMessage: string;
begin
  if FHasStart then
    Result := rsToolCalloutBox
  else
    Result := CalloutSnapDescription(Host.Document.Pattern, FSnap, FSnapClick);
end;

procedure TCalloutTool.Click;
begin
  if FHasStart then
    AddCallout
  else
    StartCallout;
end;

// The first click says what the tip points at, which cannot be nothing
procedure TCalloutTool.StartCallout;
var
  Anchor: TNoteAnchor;
  AnchorKey: string;
  Ratio: double;
begin
  NoteAnchorFromSnap(Host.Document.Pattern, FSnap, FSnapClick, Anchor, AnchorKey, Ratio);
  if Anchor = naFree then
  begin
    Host.ShowMessage(rsPatternCalloutFree);
    Exit;
  end;
  FStart := FSnap;
  FStartClick := FSnapClick;
  FHasStart := True;
  Host.ShowMessage(rsToolCalloutBox);
end;

// The second click: the text goes where it was, and the tip where the first snapped
procedure TCalloutTool.AddCallout;
var
  Document: TPatternDocument;
  Note: TNoteObject;
  Key, Reason: string;
begin
  Document := Host.Document;
  FHasStart := False;
  Document.BeginChange(rsToolAddCallout);
  Note := CalloutFromSnap(Document.Pattern, FStart, FStartClick, FSnapClick, rsToolNewNoteText, nlArrow);
  Reason := Document.Pattern.LastError;
  Key := '';
  if Assigned(Note) then
    Key := Note.Key;
  if not Document.Commit(Assigned(Note)) then
  begin
    Host.ShowMessage(Reason);
    Exit;
  end;
  Host.ShowMessage(rsToolCalloutHint);
  Host.Select([Key]);
  Host.NoteAdded;
end;

{ TPieceTool }

function TPieceTool.Hint: string;
begin
  Result := rsToolPieceHint;
end;

procedure TPieceTool.Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer);
begin
  if Button = cbLeft then
    ApplyEdit(AddPieceAt(Host.Document, ModelAt(X, Y)));
end;

{ TNotchTool }

function TNotchTool.Hint: string;
begin
  Result := rsToolNotchHint;
end;

// Every notch here goes, since a notch often sits on two pieces sewn together

// On every piece that uses the edge, so two sides of a seam get matching notches

procedure TNotchTool.Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer);
begin
  if Button = cbLeft then
    ApplyEdit(ToggleNotchAt(Host.Document, ModelAt(X, Y), Host.View.PixelsToMM(SNAP_RADIUS)));
end;

{ TSeamTool }

function TSeamTool.Hint: string;
begin
  Result := rsToolSeamHint;
end;

procedure TSeamTool.Reset;
begin
  FSideA := nil;
  FSideB := nil;
  FOnB := False;
end;

function TSeamTool.Picking: boolean;
begin
  Result := (Length(FSideA) > 0) or (Length(FSideB) > 0) or FOnB;
end;

procedure TSeamTool.ShowProgress;
begin
  Host.ShowMessage(SeamProgressText(Host.Document.Pattern, FSideA, FSideB, FOnB));
end;

// A click on a piece's edge adds it to the side being picked, or takes it off
procedure TSeamTool.Press(Button: TCanvasButton; Shift: TShiftState; X, Y: integer);
var
  Message: string;
begin
  if Button <> cbLeft then
    Exit;
  PickSeamEntry(Host.Document.Pattern, ModelAt(X, Y), Host.View.PixelsToMM(SNAP_RADIUS), FSideA, FSideB, FOnB, Message);
  Host.ShowMessage(Message);
  Host.Refresh;
end;

function TSeamTool.Cancel: boolean;
begin
  Result := Picking;
  if not Result then
    Exit;
  Reset;
  Host.ShowMessage(rsToolSeamHint);
  Host.Refresh;
end;

// Tab would otherwise move the focus to the next control
function TSeamTool.HandlesKey(Key: word): boolean;
begin
  Result := (Key = VK_TAB) or (Key = VK_RETURN);
end;

procedure TSeamTool.KeyDown(Key: word; Shift: TShiftState);
begin
  if Key = VK_TAB then
  begin
    FOnB := not (ssShift in Shift);
    ShowProgress;
  end
  else if Key = VK_RETURN then
    MakeSeam;
end;

procedure TSeamTool.MakeSeam;
var
  Edit: TSelectionEdit;
begin
  Edit := AddSeamFromSides(Host.Document, FSideA, FSideB);
  if Edit.Done then
  begin
    Reset;
    Edit.Message := rsToolSeamHint;
  end;
  ApplyEdit(Edit);
  Host.Refresh;
end;

procedure TSeamTool.ObjectsReplaced;
var
  Pattern: TPattern;
begin
  Pattern := Host.Document.Pattern;
  FSideA := ExistingSeamEntries(Pattern, FSideA);
  FSideB := ExistingSeamEntries(Pattern, FSideB);
end;

procedure TSeamTool.AddToPaintState(var State: TPaintState);
begin
  State.SeamA := FSideA;
  State.SeamB := FSideB;
end;

end.
