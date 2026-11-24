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

// Draws the drafting canvas into a bitmap: the grid, the pattern with its
// notes and labels, and the overlays the canvas asks for (curve handles, the
// snap, the selection box). It draws what it is given and decides nothing
// about tools or input; the canvas says what to show.
unit Sloper.UI.PatternPainter;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Graphics, BGRABitmap, BGRABitmapTypes, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam,
  Sloper.Core.Pattern, Sloper.Core.Units, Sloper.Core.TextFields, Sloper.Core.Note, Sloper.Core.Drag, Sloper.Core.LabelPlacement, Sloper.Editor.View,
  Sloper.Core.Stamp, Sloper.Editor.SuggestionGrade, Sloper.Editor.Snap, Sloper.Editor.Scene;

type
  // What a drawing tool's second click would make, drawn from its first
  TSnapPreview = (spNone, spLine, spCircle, spRectangle);

  // What the canvas shows besides the pattern itself
  TPaintState = record
    View: TViewTransform;
    Selection: TStringArray;
    HoverKey: string;
    ShowPieceFills: boolean;
    // Points drawn smaller, when no labels are shown
    SmallPoints: boolean;
    // The two sides of the seam being picked
    SeamA, SeamB: TSeamSide;
    // A callout whose tip is being dragged, and where to; empty when none
    DraggedTipKey: string;
    DraggedTip: TVec2;
    // A selected callout shows a handle on its tip, for dragging it
    TipHandles: boolean;
    // Objects with problems, marked with a red halo; empty when the overlay is off
    ProblemKeys: TStringArray;
    // Arrows also go to what reads the hovered and selected objects
    ShowDependents: boolean;
    // The note whose text is being typed, drawn with PreviewNoteText, which
    // is shown text with its draft values worked out; empty when none is
    PreviewNoteKey, PreviewNoteText: string;
  end;

  TPatternPainter = class
  private
    FBitmap: TBGRABitmap;
    FPattern: TPattern;
    FState: TPaintState;
    FEdgeSlots: TEdgeSlotArray;
    FCopyLinks: TCopyLinkArray;
    // Where the notes were drawn this frame, in pixels, for labels to keep off
    FNoteFrames: TRect2Array;
    function NearScreen(const At: TVec2): boolean;
    function IsSelected(const Key: string): boolean;
    // Normal, greyed when the object is locked, then in its state's colour
    function InkFor(Node: TDraftObject; const Normal: TBGRAPixel): TBGRAPixel;
    procedure DrawPieceFill(Piece: TPieceObject; const Points: TVec2Array; const Screen: array of TPointF);
    procedure DrawPiece(Piece: TPieceObject);
    procedure DrawChevron(const Position: TVec2; Angle: double; const AColor: TBGRAPixel);
    procedure DrawChevrons(Piece: TPieceObject);
    procedure DrawSeamSide(const Side: TSeamSide; const AColor: TBGRAPixel; Width: single);
    function HasProblem(const Key: string): boolean;
    procedure DrawProblemHalos;
    procedure DrawSeams;
    procedure DrawPieceMarks(Piece: TPieceObject);
    function EdgeShift(const Key: string): TVec2;
    procedure DrawEdge(Edge: TEdgeObject);
    procedure DrawPoint(Point: TPointObject);
    procedure DrawSourceHalos;
    procedure DrawCopyLinks;
    procedure DrawDependencyLinks;
    procedure DrawMarker(DraftObject: TDraftObject);
    procedure DrawLayer(Dimmed: boolean);
  public
    constructor Create;
    destructor Destroy; override;
    // Starts a frame of Width by Height pixels on blank paper. Pattern may be
    // nil, for the grid alone; the Draw calls below except DrawGrid and
    // DrawBox need one.
    procedure BeginFrame(Pattern: TPattern; Width, Height: integer; const State: TPaintState);
    procedure EndFrame(Target: TCanvas);
    // Step in GridUnit, as in Preferences
    procedure DrawGrid(Step: double; GridUnit: TMeasureUnit);
    // Pieces under edges, edges under points, with seams and markers
    procedure DrawPattern;
    procedure DrawNotes(const PatternValues: TFieldValues);
    // Over the rest, so no edge or point crosses out a label
    procedure DrawLabels(const Keys: TStringArray);
    // Each selected curve's handles; the one at HoverField of curve HoverEdge is larger
    procedure DrawHandles(const HoverField, HoverEdge: string);
    // The snap marker, a guide to the point it lines up with, and what the
    // second click would make from StartAt
    procedure DrawSnap(const Snap: TSnap; Preview: TSnapPreview; const StartAt: TVec2);
    // The selection box between two screen corners
    procedure DrawBox(const Corner, OtherCorner: TPoint);
    // The path a drag locked to one field keeps the point on (formula suggestions)
    procedure DrawFieldGuide(const Guide: TFieldGuide);
    // Where a suggested formula would put the point
    procedure DrawGhost(const Position: TVec2);
    // What a suggested formula would make of its object at another size
    procedure DrawGradeGhost(const Ghost: TGradeGhost);
  end;

// Draws text from here on in a note's font, or in DefaultFont when it names none
procedure UseNoteFont(Bitmap: TBGRABitmap; const Style: TTextStyle; const DefaultFont: string);
// A stamp's drawing in its own colours, faded to Alpha, its top left at
// TopLeft in pixels and PixelsPerMm pixels to each of its mm
procedure DrawStampOn(Bitmap: TBGRABitmap; const Drawing: TStampDrawing; const TopLeft: TVec2; PixelsPerMm: double; Alpha: byte);

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Transform,
  Sloper.Core.Materials, Sloper.Editor.RulerTicks;

const
  // How much of the paper covers what an isolated piece does not use
  DIM_WASH_ALPHA = 200;
  // How closely a stamp's curves are followed, and its thinnest stroke, in pixels
  STAMP_FLATTEN_PIXELS = 0.25;
  MIN_STAMP_STROKE = 0.5;
  OPAQUE = 255;
  // How strongly a dimmed note's ink shows
  DIM_NOTE_ALPHA = 60;
  // How strongly a material's colour shows under the lines
  MATERIAL_TINT_ALPHA = 60;
  MATERIAL_HATCH_ALPHA = 130;
  MATERIAL_HATCH_PIXELS = 8;
  // Screen pixels
  MARKING_LINE_WIDTH = 1.5;
  POINT_RADIUS = 3.5;
  SMALL_POINT_RADIUS = 2.5;
  HANDLE_RADIUS = 4;
  // How far apart lines in the same place are drawn, in pixels
  COINCIDENT_GAP = 3;
  FLATTEN_PIXELS = 0.25;
  LABEL_FONT_HEIGHT = 13;
  // How far a label is from its point or line, and how many lines further
  // out it may move to keep clear of others, in pixels
  LABEL_GAP_PIXELS = 4;
  LABEL_RINGS = 2;
  // Labels this far off the canvas are left out, in pixels
  OFFSCREEN_LABEL_PIXELS = 200;
  SNAP_MARKER_SIZE = 6;
  CHEVRON_SIZE = 7;
  CHEVRON_SPREAD = 150;
  SEAM_LINE_WIDTH = 4;
  // A copied point's diamond reaches this many dot radii from its centre, a
  // little larger than a dot so that its corners show past the lines through it
  DIAMOND_SCALE = 1.6;
  // The line from a copy to its source, and the halo lighting the source, in pixels
  COPY_LINK_WIDTH = 1.5;
  SOURCE_HALO_WIDTH = 8;
  SOURCE_HALO_GROW = 5;
  // Wider than a hover's or a copy source's, so a problem reads over both
  PROBLEM_HALO_WIDTH = 10;
  PROBLEM_HALO_GROW = 6;
  // A dependency arrow: its width, how far it stops short of each end, and
  // the length of its head, in pixels
  LINK_ARROW_WIDTH = 1.2;
  LINK_ARROW_GAP = 6;
  LINK_ARROW_HEAD = 7;
  // Text smaller than this many pixels is drawn as a faint bar
  MIN_NOTE_PIXELS = 3;
  DASH_PIXELS_PER_MILLIMETRE = 2.5;
  // A drag's guide, and the ghost of a suggestion's point, in pixels
  FIELD_GUIDE_WIDTH = 1;
  GHOST_RADIUS = 6;
  GHOST_WIDTH = 1.5;

function Paper: TBGRAPixel;
begin
  Result := BGRA(252, 251, 248);
end;

function GridMinor: TBGRAPixel;
begin
  Result := BGRA(236, 234, 228);
end;

function GridMajor: TBGRAPixel;
begin
  Result := BGRA(218, 215, 207);
end;

function Ink: TBGRAPixel;
begin
  Result := BGRA(34, 36, 40);
end;

function ConstructionInk: TBGRAPixel;
begin
  Result := BGRA(128, 134, 145);
end;

function SelectedInk: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214);
end;

function SeamInkA: TBGRAPixel;
begin
  Result := BGRA(214, 96, 37);
end;

function SeamInkB: TBGRAPixel;
begin
  Result := BGRA(20, 140, 120);
end;

function SnapInk: TBGRAPixel;
begin
  Result := BGRA(196, 48, 140);
end;

function BoxFill: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 20);
end;

// Laid over what an isolated piece does not use
function DimWash: TBGRAPixel;
begin
  Result := Paper;
  Result.alpha := DIM_WASH_ALPHA;
end;

function PieceHoverTint: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 30);
end;

function HoverHalo: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 60);
end;

// Round an object with a problem, in the error colour, faint enough to read
// the object through
function ProblemHalo: TBGRAPixel;
begin
  Result := BGRA(209, 52, 56, 80);
end;

// A suggestion's object at the smallest and largest sizes
function GradeGhostInk: TBGRAPixel;
begin
  Result := BGRA(196, 48, 140, 160);
end;

// The faint line a drag locked to one field follows
function GuideInk: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 90);
end;

// From a transform copy to its source
function CopyLinkInk: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 170);
end;

// From an object to what it reads, and to what reads it
function InputLinkInk: TBGRAPixel;
begin
  Result := BGRA(37, 116, 214, 130);
end;

function DependentLinkInk: TBGRAPixel;
begin
  Result := BGRA(140, 80, 200, 130);
end;

function StateInk(State: TEvalState; const Normal: TBGRAPixel): TBGRAPixel;
begin
  case State of
    esError, esInvalid: Result := BGRA(209, 52, 56);
    esBlocked: Result := BGRA(226, 140, 40);
    else
      Result := Normal;
  end;
end;

// A locked object is drawn greyed: its ink without colour, half way to the paper
function Greyed(const Color: TBGRAPixel): TBGRAPixel;
var
  Grey: integer;
begin
  Grey := (Color.red * 30 + Color.green * 59 + Color.blue * 11) div 100;
  Grey := (Grey + Paper.red) div 2;
  Result := BGRA(Grey, Grey, Grey, Color.alpha);
end;

// Failing objects are drawn faded at their last good result
function Faded(const Color: TBGRAPixel; State: TEvalState): TBGRAPixel;
begin
  Result := Color;
  if State <> esValid then
    Result.alpha := 150;
end;

function ScreenPoint(const Point: TVec2): TPointF;
begin
  Result := PointF(Point.X, Point.Y);
end;

procedure UseNoteFont(Bitmap: TBGRABitmap; const Style: TTextStyle; const DefaultFont: string);
var
  Styles: TFontStyles;
begin
  if Style.Font <> '' then
    Bitmap.FontName := Style.Font
  else
    Bitmap.FontName := DefaultFont;
  Styles := [];
  if Style.Bold then
    Include(Styles, fsBold);
  if Style.Italic then
    Include(Styles, fsItalic);
  Bitmap.FontStyle := Styles;
end;

procedure DrawStampOn(Bitmap: TBGRABitmap; const Drawing: TStampDrawing; const TopLeft: TVec2; PixelsPerMm: double; Alpha: byte);
var
  Path: TStampPath;
  Contour: TStampContour;
  Shape, Outline: array of TPointF;
  Point: TVec2;
  SavedMode: TFillMode;

  function Colour(Value: integer): TBGRAPixel;
  begin
    Result := BGRA((Value shr 16) and $FF, (Value shr 8) and $FF, Value and $FF, Alpha);
  end;

begin
  SavedMode := Bitmap.FillMode;
  try
    for Path in Drawing.Paths do
    begin
      // Every contour in one polygon, so holes stay holes
      Shape := nil;
      for Contour in Path.Contours do
      begin
        if Length(Shape) > 0 then
          Insert(EmptyPointF, Shape, Length(Shape));
        for Point in FlattenStampContour(Contour, TopLeft, PixelsPerMm, STAMP_FLATTEN_PIXELS) do
          Insert(ScreenPoint(Point), Shape, Length(Shape));
      end;
      if Path.Fill <> STAMP_NO_COLOUR then
      begin
        if Path.EvenOdd then
          Bitmap.FillMode := fmAlternate
        else
          Bitmap.FillMode := fmWinding;
        Bitmap.FillPolyAntialias(Shape, Colour(Path.Fill));
      end;
      if Path.Stroke = STAMP_NO_COLOUR then
        Continue;
      for Contour in Path.Contours do
      begin
        Outline := nil;
        for Point in FlattenStampContour(Contour, TopLeft, PixelsPerMm, STAMP_FLATTEN_PIXELS) do
          Insert(ScreenPoint(Point), Outline, Length(Outline));
        if Contour.Closed then
          Bitmap.DrawPolygonAntialias(Outline, Colour(Path.Stroke), Max(MIN_STAMP_STROKE, Path.StrokeWidth * PixelsPerMm))
        else
          Bitmap.DrawPolyLineAntialias(Outline, Colour(Path.Stroke), Max(MIN_STAMP_STROKE, Path.StrokeWidth * PixelsPerMm));
      end;
    end;
  finally
    Bitmap.FillMode := SavedMode;
  end;
end;

{ TPatternPainter }

function TPatternPainter.InkFor(Node: TDraftObject; const Normal: TBGRAPixel): TBGRAPixel;
begin
  Result := Normal;
  if FPattern.IsLocked(Node) then
    Result := Greyed(Result);
  Result := Faded(StateInk(Node.State, Result), Node.State);
end;

constructor TPatternPainter.Create;
begin
  inherited Create;
  FBitmap := TBGRABitmap.Create(1, 1);
end;

destructor TPatternPainter.Destroy;
begin
  FreeAndNil(FBitmap);
  inherited Destroy;
end;

procedure TPatternPainter.BeginFrame(Pattern: TPattern; Width, Height: integer; const State: TPaintState);
begin
  FPattern := Pattern;
  FState := State;
  // The bitmap is never empty, so a collapsed canvas keeps a 1 by 1 one
  Width := Max(Width, 1);
  Height := Max(Height, 1);
  if (FBitmap.Width <> Width) or (FBitmap.Height <> Height) then
    FBitmap.SetSize(Width, Height);
  FBitmap.Fill(Paper);
  FNoteFrames := nil;
  FBitmap.FontHeight := LABEL_FONT_HEIGHT;
  FBitmap.FontQuality := fqFineAntialiasing;
end;

procedure TPatternPainter.EndFrame(Target: TCanvas);
begin
  FBitmap.Draw(Target, 0, 0, True);
end;

function TPatternPainter.IsSelected(const Key: string): boolean;
var
  Selected: string;
begin
  for Selected in FState.Selection do
    if Selected = Key then
      Exit(True);
  Result := False;
end;

// Counted in whole steps from the origin, so major lines stay put and long
// grids gather no rounding
procedure TPatternPainter.DrawGrid(Step: double; GridUnit: TMeasureUnit);
var
  Spacing: TRulerSpacing;
  StepMm, Screen: double;
  PerMajor, First, Last, Index: int64;
  TopLeft, BottomRight: TVec2;
  LineColor: TBGRAPixel;
begin
  Spacing := GridSpacing(FState.View.Scale * MILLIMETRES_PER_UNIT[GridUnit], Step, GridUnit);
  StepMm := Spacing.Minor * MILLIMETRES_PER_UNIT[GridUnit];
  PerMajor := Max(1, Round(Spacing.Labelled / Spacing.Minor));
  TopLeft := FState.View.ToModel(Vec2(0, 0));
  BottomRight := FState.View.ToModel(Vec2(FBitmap.Width, FBitmap.Height));

  First := Floor64(TopLeft.X / StepMm);
  Last := Ceil64(BottomRight.X / StepMm);
  for Index := First to Last do
  begin
    if Index mod PerMajor = 0 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    Screen := FState.View.ToScreen(Vec2(Index * StepMm, 0)).X;
    FBitmap.DrawVertLine(Round(Screen), 0, FBitmap.Height, LineColor);
  end;
  First := Floor64(TopLeft.Y / StepMm);
  Last := Ceil64(BottomRight.Y / StepMm);
  for Index := First to Last do
  begin
    if Index mod PerMajor = 0 then
      LineColor := GridMajor
    else
      LineColor := GridMinor;
    Screen := FState.View.ToScreen(Vec2(0, Index * StepMm)).Y;
    FBitmap.DrawHorizLine(0, Round(Screen), FBitmap.Width, LineColor);
  end;
end;

// Under every line, so seams and labels stay readable. Hatching keeps its
// spacing on screen at any zoom.
procedure TPatternPainter.DrawPieceFill(Piece: TPieceObject; const Points: TVec2Array; const Screen: array of TPointF);
var
  Look: TPieceLook;
  Stroke: TLine2;
  Color: TBGRAPixel;
begin
  Look := FPattern.PieceLook(Piece);
  if not FState.ShowPieceFills or not Look.Filled then
    Exit;
  Color := BGRA(Look.Color.Red, Look.Color.Green, Look.Color.Blue);
  if Piece.Locked then
    Color := Greyed(Color);
  if Look.Fill = ffTint then
    FBitmap.FillPolyAntialias(Screen, BGRA(Color.red, Color.green, Color.blue, MATERIAL_TINT_ALPHA))
  else
    for Stroke in HatchLines(Points, MATERIAL_HATCH_PIXELS, Look.HatchAngle) do
      FBitmap.DrawLineAntialias(Stroke.P1.X, Stroke.P1.Y, Stroke.P2.X, Stroke.P2.Y, BGRA(Color.red, Color.green,
        Color.blue, MATERIAL_HATCH_ALPHA), 1);
end;

// The cutting line, filled with its material; the seam line is the edges drawn over it
procedure TPatternPainter.DrawPiece(Piece: TPieceObject);
var
  Screen: array of TPointF;
  Points: TVec2Array;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  if Length(Piece.CutLine) = 0 then
    Exit;
  Screen := nil;
  Points := nil;
  SetLength(Screen, Length(Piece.CutLine));
  SetLength(Points, Length(Piece.CutLine));
  for Index := 0 to High(Screen) do
  begin
    Points[Index] := FState.View.ToScreen(Piece.CutLine[Index]);
    Screen[Index] := ScreenPoint(Points[Index]);
  end;
  DrawPieceFill(Piece, Points, Screen);
  if Piece.Key = FState.HoverKey then
    FBitmap.FillPolyAntialias(Screen, PieceHoverTint);
  LineColor := InkFor(Piece, ConstructionInk);
  LineWidth := 1;
  if IsSelected(Piece.Key) then
  begin
    LineColor := SelectedInk;
    LineWidth := 2;
  end;
  FBitmap.DrawPolygonAntialias(Screen, LineColor, LineWidth);
end;

procedure TPatternPainter.DrawChevron(const Position: TVec2; Angle: double; const AColor: TBGRAPixel);
var
  Tip, WingA, WingB: TVec2;
  Size: double;
begin
  Size := FState.View.PixelsToMM(CHEVRON_SIZE);
  Tip := FState.View.ToScreen(Position);
  WingA := FState.View.ToScreen(PolarPoint(Position, Size, Angle + CHEVRON_SPREAD));
  WingB := FState.View.ToScreen(PolarPoint(Position, Size, Angle - CHEVRON_SPREAD));
  FBitmap.DrawPolyLineAntialias([PointF(WingA.X, WingA.Y), PointF(Tip.X, Tip.Y), PointF(WingB.X, WingB.Y)], AColor, 2);
end;

// Shown over the edges while a piece is hovered or selected
procedure TPatternPainter.DrawChevrons(Piece: TPieceObject);
var
  Item: TPieceChevron;
begin
  for Item in PieceChevrons(FPattern, Piece) do
    DrawChevron(Item.Position, Item.Angle, SelectedInk);
end;

procedure TPatternPainter.DrawSeamSide(const Side: TSeamSide; const AColor: TBGRAPixel; Width: single);
var
  Entry: TSeamEntry;
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
begin
  for Entry in Side do
  begin
    Model := EdgePolyline(TEdgeObject(FPattern.FindNode(Entry.EdgeKey)), FState.View.PixelsToMM(FLATTEN_PIXELS));
    Screen := nil;
    SetLength(Screen, Length(Model));
    for Index := 0 to High(Model) do
      Screen[Index] := ScreenPoint(FState.View.ToScreen(Model[Index]));
    FBitmap.DrawPolyLineAntialias(Screen, AColor, Width);
  end;
end;

// The selected seams, with the way they run, and the one being picked
procedure TPatternPainter.DrawSeams;
var
  Key: string;
  Node: TEvalNode;
  Item: TPieceChevron;
begin
  for Key in FState.Selection do
  begin
    Node := FPattern.FindNode(Key);
    if not (Node is TSeamObject) then
      Continue;
    DrawSeamSide(TSeamObject(Node).SideA, SeamInkA, SEAM_LINE_WIDTH);
    DrawSeamSide(TSeamObject(Node).SideB, SeamInkB, SEAM_LINE_WIDTH);
    for Item in SeamChevrons(FPattern, TSeamObject(Node), False) do
      DrawChevron(Item.Position, Item.Angle, SeamInkA);
    for Item in SeamChevrons(FPattern, TSeamObject(Node), True) do
      DrawChevron(Item.Position, Item.Angle, SeamInkB);
  end;
  DrawSeamSide(FState.SeamA, SeamInkA, SEAM_LINE_WIDTH);
  DrawSeamSide(FState.SeamB, SeamInkB, SEAM_LINE_WIDTH);
end;

// The grainline and notches, over the edges
procedure TPatternPainter.DrawPieceMarks(Piece: TPieceObject);
var
  Stroke: TLine2;
  Mark: TNotchMark;
  LineColor: TBGRAPixel;
  First, Last: TVec2;
begin
  LineColor := InkFor(Piece, ConstructionInk);
  if IsSelected(Piece.Key) then
    LineColor := SelectedInk;
  for Stroke in Concat(Piece.GrainArrow, Piece.FoldArrow, Piece.MarkingStrokes) do
  begin
    First := FState.View.ToScreen(Stroke.P1);
    Last := FState.View.ToScreen(Stroke.P2);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 1.5);
  end;
  for Mark in Piece.NotchMarks do
  begin
    First := FState.View.ToScreen(Mark.Cut);
    Last := FState.View.ToScreen(Mark.Tip);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 2);
  end;
end;

function ScreenDashes(const Dashes: TDashPattern; LineWidth: single): TBGRAPenStyle; forward;

// Screen pixels to move an edge aside by, so lines in the same place show
// that there is more than one; geometry and output never move
function TPatternPainter.EdgeShift(const Key: string): TVec2;
var
  Slot: TEdgeSlot;
begin
  Result := Vec2(0, 0);
  for Slot in FEdgeSlots do
    if Slot.Key = Key then
      Exit(Slot.Normal * (Slot.Slot * COINCIDENT_GAP));
end;

procedure TPatternPainter.DrawEdge(Edge: TEdgeObject);
var
  Shift: TVec2;
  Model: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
  LineColor: TBGRAPixel;
  LineWidth: single;
begin
  Model := EdgePolyline(Edge, FState.View.PixelsToMM(FLATTEN_PIXELS));
  if Length(Model) < 2 then
    Exit;
  Shift := EdgeShift(Edge.Key);
  Screen := nil;
  SetLength(Screen, Length(Model));
  for Index := 0 to High(Model) do
    Screen[Index] := ScreenPoint(FState.View.ToScreen(Model[Index]) + Shift);

  case Edge.Role of
    erOutline:
    begin
      LineColor := Ink;
      LineWidth := 2;
    end;
    erConstruction:
    begin
      LineColor := ConstructionInk;
      LineWidth := 1;
    end;
    else
    begin
      LineColor := StrToBGRA(ROLE_COLORS[Edge.Role]);
      LineWidth := MARKING_LINE_WIDTH;
    end;
  end;
  LineColor := InkFor(Edge, LineColor);
  if Edge.Key = FState.HoverKey then
    FBitmap.DrawPolyLineAntialias(Screen, HoverHalo, LineWidth + 6);
  // Selecting a transform shows its copies
  if IsSelected(Edge.Key) or IsSelected(CopyTransformKey(Edge)) then
  begin
    LineColor := SelectedInk;
    LineWidth := LineWidth + 1;
  end;
  if Edge.Role = erConstruction then
    FBitmap.PenStyle := psDash
  else if ROLE_DASHES[Edge.Role][0] > 0 then
    FBitmap.CustomPenStyle := ScreenDashes(ROLE_DASHES[Edge.Role], LineWidth);
  FBitmap.DrawPolyLineAntialias(Screen, LineColor, LineWidth);
  FBitmap.PenStyle := psSolid;
end;

// The paper dashes at a fixed size on screen, whatever the zoom, in the pen
// widths BGRABitmap counts in
function ScreenDashes(const Dashes: TDashPattern; LineWidth: single): TBGRAPenStyle;
var
  Index, Count: integer;
begin
  Result := nil;
  Count := 0;
  for Index := 0 to High(Dashes) do
    if Dashes[Index] > 0 then
      Inc(Count);
  SetLength(Result, Count);
  for Index := 0 to Count - 1 do
    Result[Index] := Dashes[Index] * DASH_PIXELS_PER_MILLIMETRE / LineWidth;
end;

procedure TPatternPainter.DrawPoint(Point: TPointObject);
var
  Screen: TVec2;
  InkColor: TBGRAPixel;
  Radius: single;
begin
  Screen := FState.View.ToScreen(Point.Position);
  InkColor := InkFor(Point, Ink);
  if FState.SmallPoints then
    Radius := SMALL_POINT_RADIUS
  else
    Radius := POINT_RADIUS;
  if Point.Key = FState.HoverKey then
    FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius + 5, Radius + 5, HoverHalo);
  if IsSelected(Point.Key) or IsSelected(CopyTransformKey(Point)) then
  begin
    InkColor := SelectedInk;
    Radius := Radius + 1.5;
  end;
  // A transform copy is a diamond, so it reads as following something else
  // without looking locked or failing
  if Point is TPointCopy then
  begin
    Radius := Radius * DIAMOND_SCALE;
    FBitmap.FillPolyAntialias([PointF(Screen.X, Screen.Y - Radius), PointF(Screen.X + Radius, Screen.Y),
      PointF(Screen.X, Screen.Y + Radius), PointF(Screen.X - Radius, Screen.Y)], InkColor);
  end
  else
    FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, Radius, Radius, InkColor);
end;

// The sources of the linked copies, lit as if hovered, under their own lines
procedure TPatternPainter.DrawSourceHalos;
var
  Link: TCopyLink;
  Node: TEvalNode;
  Model: TVec2Array;
  Screen: array of TPointF;
  Shift, Spot: TVec2;
  Index: integer;
begin
  for Link in FCopyLinks do
  begin
    Node := FPattern.FindNode(Link.SourceKey);
    if Node is TPointObject then
    begin
      Spot := FState.View.ToScreen(TPointObject(Node).Position);
      FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, POINT_RADIUS + SOURCE_HALO_GROW, POINT_RADIUS + SOURCE_HALO_GROW, HoverHalo);
    end
    else if (Node is TEdgeObject) and not FPattern.IsHidden(TEdgeObject(Node)) then
    begin
      Model := EdgePolyline(TEdgeObject(Node), FState.View.PixelsToMM(FLATTEN_PIXELS));
      Shift := EdgeShift(Node.Key);
      Screen := nil;
      SetLength(Screen, Length(Model));
      for Index := 0 to High(Model) do
        Screen[Index] := ScreenPoint(FState.View.ToScreen(Model[Index]) + Shift);
      FBitmap.DrawPolyLineAntialias(Screen, HoverHalo, SOURCE_HALO_WIDTH);
    end;
  end;
end;

function TPatternPainter.HasProblem(const Key: string): boolean;
var
  Problem: string;
begin
  for Problem in FState.ProblemKeys do
    if Problem = Key then
      Exit(True);
  Result := False;
end;

// Under the lines, so each object stays readable over its halo. Hidden and
// dimmed objects are left out, as they cannot be clicked; notes mark theirs
// in DrawNotes.
procedure TPatternPainter.DrawProblemHalos;
var
  Key: string;
  Node: TEvalNode;
  Model: TVec2Array;
  Screen: array of TPointF;
  Shift, Spot, Centre: TVec2;
  Index: integer;
  Piece: TPieceObject;
begin
  for Key in FState.ProblemKeys do
  begin
    Node := FPattern.FindNode(Key);
    if not (Node is TDraftObject) or not Node.HasResult or FPattern.IsHidden(TDraftObject(Node)) or FPattern.IsDimmed(TDraftObject(Node)) then
      Continue;
    Screen := nil;
    if Node is TPieceObject then
    begin
      Piece := TPieceObject(Node);
      SetLength(Screen, Length(Piece.CutLine));
      for Index := 0 to High(Screen) do
        Screen[Index] := ScreenPoint(FState.View.ToScreen(Piece.CutLine[Index]));
      if Length(Screen) > 2 then
        FBitmap.DrawPolygonAntialias(Screen, ProblemHalo, PROBLEM_HALO_WIDTH);
    end
    else if Node is TEdgeObject then
    begin
      Model := EdgePolyline(TEdgeObject(Node), FState.View.PixelsToMM(FLATTEN_PIXELS));
      Shift := EdgeShift(Node.Key);
      SetLength(Screen, Length(Model));
      for Index := 0 to High(Model) do
        Screen[Index] := ScreenPoint(FState.View.ToScreen(Model[Index]) + Shift);
      FBitmap.DrawPolyLineAntialias(Screen, ProblemHalo, PROBLEM_HALO_WIDTH);
    end
    else if Node is TSeamObject then
    begin
      DrawSeamSide(TSeamObject(Node).SideA, ProblemHalo, PROBLEM_HALO_WIDTH);
      DrawSeamSide(TSeamObject(Node).SideB, ProblemHalo, PROBLEM_HALO_WIDTH);
    end
    else if Node is TPointObject then
    begin
      Spot := FState.View.ToScreen(TPointObject(Node).Position);
      FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, POINT_RADIUS + PROBLEM_HALO_GROW, POINT_RADIUS + PROBLEM_HALO_GROW, ProblemHalo);
    end
    else
      // A repeat's marked points
      for Centre in MarkerPositions(TDraftObject(Node)) do
      begin
        Spot := FState.View.ToScreen(Centre);
        FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, POINT_RADIUS + PROBLEM_HALO_GROW, POINT_RADIUS + PROBLEM_HALO_GROW, ProblemHalo);
      end;
  end;
end;

// A faint dashed line from each linked copy to its source
procedure TPatternPainter.DrawCopyLinks;
var
  Link: TCopyLink;
  First, Last: TVec2;
begin
  FBitmap.PenStyle := psDash;
  for Link in FCopyLinks do
  begin
    First := FState.View.ToScreen(Link.CopyAt);
    Last := FState.View.ToScreen(Link.SourceAt);
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, CopyLinkInk, COPY_LINK_WIDTH);
  end;
  FBitmap.PenStyle := psSolid;
end;

// Faint arrows from the hovered and selected objects to what they read, and
// to what reads them when asked, stopping short of both ends so the points
// stay clear, with the head at the far end
procedure TPatternPainter.DrawDependencyLinks;
var
  Link: TDependencyLink;
  First, Last, Along, Across: TVec2;
  LinkInk: TBGRAPixel;
  Span: double;
begin
  for Link in DependencyLinks(FPattern, FState.Selection, FState.HoverKey, FState.ShowDependents) do
  begin
    First := FState.View.ToScreen(Link.FromAt);
    Last := FState.View.ToScreen(Link.ToAt);
    Span := Distance(First, Last);
    if Span < 3 * LINK_ARROW_GAP then
      Continue;
    Along := (Last - First) * (1 / Span);
    Across := Vec2(-Along.Y, Along.X);
    First := First + Along * LINK_ARROW_GAP;
    Last := Last - Along * LINK_ARROW_GAP;
    if Link.Dependent then
      LinkInk := DependentLinkInk
    else
      LinkInk := InputLinkInk;
    FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LinkInk, LINK_ARROW_WIDTH);
    FBitmap.FillPolyAntialias([PointF(Last.X, Last.Y),
      ScreenPoint(Last - Along * LINK_ARROW_HEAD + Across * (LINK_ARROW_HEAD / 2)),
      ScreenPoint(Last - Along * LINK_ARROW_HEAD - Across * (LINK_ARROW_HEAD / 2))], LinkInk);
  end;
end;

// Pieces under edges, edges under points, with seams and markers. While a
// piece is isolated, what it does not use is drawn first and washed over with
// paper, so it shows faintly under the piece.
procedure TPatternPainter.DrawPattern;
begin
  FEdgeSlots := CoincidentEdges(FPattern);
  if not Assigned(FPattern.IsolatedPiece) then
  begin
    DrawLayer(False);
    Exit;
  end;
  DrawLayer(True);
  FBitmap.FillRect(0, 0, FBitmap.Width, FBitmap.Height, DimWash, dmDrawWithTransparency);
  DrawLayer(False);
end;

procedure TPatternPainter.DrawLayer(Dimmed: boolean);
var
  Point: TPointObject;
  Shown: TDraftObjectArray;
  DraftObject: TDraftObject;
  Piece: TPieceObject;
  Key: string;
  Node: TEvalNode;
begin
  Shown := nil;
  for DraftObject in ShownObjects(FPattern) do
    if FPattern.IsDimmed(DraftObject) = Dimmed then
      Insert(DraftObject, Shown, Length(Shown));
  if not Dimmed then
    FCopyLinks := CopyLinks(FPattern, FState.Selection, FState.HoverKey)
  else
    FCopyLinks := nil;
  // In the view's drawing order
  for Piece in FPattern.PiecesInDrawOrder do
    if Piece.HasResult and not FPattern.IsHidden(Piece) and (FPattern.IsDimmed(Piece) = Dimmed) then
      DrawPiece(Piece);
  if not Dimmed then
  begin
    DrawSourceHalos;
    DrawProblemHalos;
  end;
  for DraftObject in EdgesInDrawOrder(Shown) do
    if DraftObject.HasResult then
      DrawEdge(TEdgeObject(DraftObject));
  // A hidden line shows while it is selected, as from the Objects panel
  if not Dimmed then
    for Key in FState.Selection do
    begin
      Node := FPattern.FindNode(Key);
      if (Node is TEdgeObject) and FPattern.IsHidden(TEdgeObject(Node)) and Node.HasResult then
        DrawEdge(TEdgeObject(Node));
    end;
  for Piece in FPattern.PiecesInDrawOrder do
  begin
    if not Piece.HasResult or FPattern.IsHidden(Piece) or (FPattern.IsDimmed(Piece) <> Dimmed) then
      Continue;
    DrawPieceMarks(Piece);
    if not Dimmed and (IsSelected(Piece.Key) or (Piece.Key = FState.HoverKey)) then
      DrawChevrons(Piece);
  end;
  if not Dimmed then
    DrawSeams;
  // A marker shows at its point whether or not it is on a piece yet
  for DraftObject in Shown do
    if (DraftObject.Marker <> pmPlain) and DraftObject.HasResult then
      DrawMarker(DraftObject);
  if not Dimmed then
  begin
    DrawCopyLinks;
    DrawDependencyLinks;
  end;
  for Point in ShownPoints(FPattern) do
    if Point.HasResult and (FPattern.IsDimmed(Point) = Dimmed) then
      DrawPoint(Point);
end;

// Over the pattern, at their true size for the zoom. A selected note shows a
// faint line to what it hangs from, and a hovered one a halo.
procedure TPatternPainter.DrawNotes(const PatternValues: TFieldValues);
var
  Values: TFieldValues;
  Shown: string;
  Index, LineIndex: integer;
  Note: TNoteObject;
  Lines: TStringArray;
  Box, Frame: TRect2;
  TopLeft, BottomRight, Anchor, Spot, Tip, Start, First, Last: TVec2;
  InkColor: TBGRAPixel;
  EmPixels, LinePixels, BoxPixels: double;
  Stroke: TLine2;
  Selected: boolean;
  DefaultFont: string;
  StampAlpha: byte;
begin
  if FPattern.View.HideAnnotations then
    Exit;
  DefaultFont := FBitmap.FontName;
  for Index := 0 to FPattern.ObjectCount - 1 do
  begin
    if not (FPattern.Objects[Index] is TNoteObject) or not FPattern.Objects[Index].HasResult or FPattern.IsHidden(FPattern.Objects[Index]) then
      Continue;
    Note := TNoteObject(FPattern.Objects[Index]);
    Selected := IsSelected(Note.Key);
    Shown := Note.ShownText;
    if (FState.PreviewNoteKey <> '') and (Note.Key = FState.PreviewNoteKey) then
      Shown := FState.PreviewNoteText;
    Values := NoteFieldValues(FPattern, Note, PatternValues, Shown);
    Box := NoteBox(Note, Values, Shown);
    Frame := NoteFrame(Note, Values, Shown);
    TopLeft := FState.View.ToScreen(Vec2(Box.MinX, Box.MinY));
    BottomRight := FState.View.ToScreen(Vec2(Box.MaxX, Box.MaxY));
    First := FState.View.ToScreen(Vec2(Frame.MinX, Frame.MinY));
    Last := FState.View.ToScreen(Vec2(Frame.MaxX, Frame.MaxY));
    // One far off the screen would only spread out the labels' grid
    if (Last.X > -OFFSCREEN_LABEL_PIXELS) and (First.X < FBitmap.Width + OFFSCREEN_LABEL_PIXELS) and (Last.Y > -OFFSCREEN_LABEL_PIXELS) and
      (First.Y < FBitmap.Height + OFFSCREEN_LABEL_PIXELS) then
      Insert(Rect2(First.X, First.Y, Last.X, Last.Y), FNoteFrames, Length(FNoteFrames));
    if Selected then
      InkColor := SelectedInk
    else
      InkColor := InkFor(Note, Ink);
    // A screen-only note is drawn lighter, as it never prints
    if not Note.Print then
      InkColor.alpha := InkColor.alpha div 2;
    // Notes are drawn over the wash, so a dimmed one is faded here
    if FPattern.IsDimmed(Note) then
      InkColor.alpha := DIM_NOTE_ALPHA;
    // A callout's leader, to where its tip is being dragged while it is
    Tip := Note.AnchorPosition;
    if (FState.DraggedTipKey <> '') and (Note.Key = FState.DraggedTipKey) then
      Tip := FState.DraggedTip;
    if (Note.Leader <> nlNone) and LeaderStart(Frame, Tip, Start) then
    begin
      for Stroke in LeaderStrokes(Start, Tip, Note.Leader) do
      begin
        First := FState.View.ToScreen(Stroke.P1);
        Last := FState.View.ToScreen(Stroke.P2);
        FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, InkColor, 1);
      end;
      if Note.Leader = nlDot then
      begin
        Spot := FState.View.ToScreen(Tip);
        FBitmap.FillEllipseAntialias(Spot.X, Spot.Y, Max(1.5, LEADER_DOT_RADIUS * FState.View.Scale), Max(1.5, LEADER_DOT_RADIUS * FState.View.Scale), InkColor);
      end;
    end
    else if Selected and (Note.Anchor <> naFree) then
    begin
      // A plain note shows faintly what it hangs from
      Anchor := FState.View.ToScreen(Note.AnchorPosition);
      FBitmap.PenStyle := psDot;
      FBitmap.DrawLineAntialias(Anchor.X, Anchor.Y, TopLeft.X, TopLeft.Y, HoverHalo, 1);
      FBitmap.PenStyle := psSolid;
    end;
    // A selected callout's tip can be dragged to something else
    if Selected and (Note.Leader <> nlNone) and FState.TipHandles then
    begin
      Spot := FState.View.ToScreen(Tip);
      FBitmap.EllipseAntialias(Spot.X, Spot.Y, HANDLE_RADIUS, HANDLE_RADIUS, SelectedInk, 1.5, Paper);
    end;
    if HasProblem(Note.Key) and not FPattern.IsDimmed(Note) then
    begin
      First := FState.View.ToScreen(Vec2(Frame.MinX, Frame.MinY));
      Last := FState.View.ToScreen(Vec2(Frame.MaxX, Frame.MaxY));
      FBitmap.FillRectAntialias(First.X - PROBLEM_HALO_GROW, First.Y - PROBLEM_HALO_GROW, Last.X + PROBLEM_HALO_GROW,
        Last.Y + PROBLEM_HALO_GROW, ProblemHalo);
    end;
    if Note.Boxed then
    begin
      First := FState.View.ToScreen(Vec2(Frame.MinX, Frame.MinY));
      Last := FState.View.ToScreen(Vec2(Frame.MaxX, Frame.MaxY));
      FBitmap.FillRectAntialias(First.X, First.Y, Last.X, Last.Y, BGRA(255, 255, 255));
    end;
    if (Note.Key = FState.HoverKey) or Selected then
      FBitmap.FillRectAntialias(TopLeft.X - 2, TopLeft.Y - 1, BottomRight.X + 2, BottomRight.Y + 1, PieceHoverTint);
    // A stamp keeps its colours, faded as the ink would be
    if Note.IsStamp then
    begin
      StampAlpha := OPAQUE;
      if not Note.Print then
        StampAlpha := OPAQUE div 2;
      if FPattern.IsDimmed(Note) then
        StampAlpha := DIM_NOTE_ALPHA;
      DrawStampOn(FBitmap, Note.Drawing, TopLeft, Note.Scale * FState.View.Scale, StampAlpha);
      Continue;
    end;
    EmPixels := Note.Size * POINTS_TO_MM * FState.View.Scale;
    LinePixels := LineHeight(Note.Size) * FState.View.Scale;
    if EmPixels < MIN_NOTE_PIXELS then
    begin
      FBitmap.FillRectAntialias(TopLeft.X, TopLeft.Y, BottomRight.X, BottomRight.Y, BGRA(InkColor.red, InkColor.green, InkColor.blue, 40));
      Continue;
    end;
    FBitmap.FontHeight := Round(EmPixels);
    UseNoteFont(FBitmap, Note.Style, DefaultFont);
    BoxPixels := BottomRight.X - TopLeft.X;
    Lines := TextLines(ExpandFields(Shown, Values));
    for LineIndex := 0 to High(Lines) do
    begin
      Spot := Vec2(AlignedLeft(TopLeft.X, BoxPixels, FBitmap.TextSize(Lines[LineIndex]).cx, Note.Align), TopLeft.Y + LineIndex * LinePixels);
      FBitmap.TextOut(Spot.X, Spot.Y, Lines[LineIndex], InkColor);
    end;
  end;
  UseNoteFont(FBitmap, Default(TTextStyle), DefaultFont);
  FBitmap.FontHeight := LABEL_FONT_HEIGHT;
end;

procedure TPatternPainter.DrawMarker(DraftObject: TDraftObject);
var
  Centre: TVec2;
  Stroke: TLine2;
  First, Last: TVec2;
  LineColor: TBGRAPixel;
begin
  if DraftObject.MarkerSize <= 0 then
    Exit;
  LineColor := InkFor(DraftObject, Ink);
  if IsSelected(DraftObject.Key) then
    LineColor := SelectedInk;
  for Centre in MarkerPositions(DraftObject) do
    for Stroke in DraftObject.MarkerStrokesAt(Centre) do
    begin
      First := FState.View.ToScreen(Stroke.P1);
      Last := FState.View.ToScreen(Stroke.P2);
      FBitmap.DrawLineAntialias(First.X, First.Y, Last.X, Last.Y, LineColor, 1);
    end;
end;

// Each selected curve's tangent lines. A handle set by a formula is hollow,
// since it cannot be dragged.
procedure TPatternPainter.DrawHandles(const HoverField, HoverEdge: string);
var
  Item: TCurveHandle;
  Anchor, Tip: TVec2;
  Radius: single;
  Reason: string;
begin
  for Item in SelectionHandles(FPattern, FState.Selection) do
  begin
    Anchor := FState.View.ToScreen(Item.Anchor);
    Tip := FState.View.ToScreen(Item.Position);
    FBitmap.DrawLineAntialias(Anchor.X, Anchor.Y, Tip.X, Tip.Y, SelectedInk, 1);
    Radius := HANDLE_RADIUS;
    if (Item.LengthField = HoverField) and (Item.EdgeKey = HoverEdge) then
      Radius := Radius + 1.5;
    if CanDragHandle(TEdgeObject(FPattern.FindNode(Item.EdgeKey)), Item, Reason) then
      FBitmap.FillEllipseAntialias(Tip.X, Tip.Y, Radius, Radius, SelectedInk)
    else
      FBitmap.EllipseAntialias(Tip.X, Tip.Y, Radius, Radius, SelectedInk, 1.5, Paper);
  end;
end;

// Whether a label put near At can show, so that one far off the screen is
// neither placed nor drawn
function TPatternPainter.NearScreen(const At: TVec2): boolean;
begin
  Result := (At.X > -OFFSCREEN_LABEL_PIXELS) and (At.Y > -OFFSCREEN_LABEL_PIXELS) and (At.X < FBitmap.Width + OFFSCREEN_LABEL_PIXELS) and
    (At.Y < FBitmap.Height + OFFSCREEN_LABEL_PIXELS);
end;

// Over the drawing, so that no edge or point crosses out a label, and each
// moved where it covers no note, no point and no other label: pieces' first,
// then points', then lines', which can move along their lines
procedure TPatternPainter.DrawLabels(const Keys: TStringArray);
var
  Requests: TLabelRequestArray;
  Texts: TStringArray;
  Colors: array of TBGRAPixel;
  Obstacles: TRect2Array;
  Places: TVec2Array;
  Key: string;
  Node: TEvalNode;
  Point: TPointObject;
  Model, Line: TVec2Array;
  Screen: TVec2;
  Index, Pass: integer;
  Size: TSize;
  Radius: double;

  procedure Request(DraftObject: TDraftObject; const Text: string; const APlaces: TVec2Array);
  var
    Item: TLabelRequest;
    InkColor: TBGRAPixel;
  begin
    if IsSelected(DraftObject.Key) then
      InkColor := SelectedInk
    else
      InkColor := InkFor(DraftObject, Ink);
    Item.Width := Size.cx;
    Item.Height := Size.cy;
    Item.Places := APlaces;
    Insert(Item, Requests, Length(Requests));
    Insert(Text, Texts, Length(Texts));
    Insert(InkColor, Colors, Length(Colors));
  end;

begin
  Requests := nil;
  Texts := nil;
  Colors := nil;
  Obstacles := Copy(FNoteFrames);
  Radius := POINT_RADIUS;
  if FState.SmallPoints then
    Radius := SMALL_POINT_RADIUS;
  for Point in ShownPoints(FPattern) do
    if Point.HasResult then
    begin
      Screen := FState.View.ToScreen(Point.Position);
      if NearScreen(Screen) then
        Insert(RectAround(Screen, Radius), Obstacles, Length(Obstacles));
    end;
  for Pass := 0 to 2 do
    for Key in Keys do
    begin
      Node := FPattern.FindNode(Key);
      if (Pass = 0) and (Node is TPieceObject) then
      begin
        Screen := FState.View.ToScreen(PieceMiddle(TPieceObject(Node)));
        Size := FBitmap.TextSize(FPattern.PieceCaption(TPieceObject(Node)));
        if NearScreen(Screen) then
          Request(TDraftObject(Node), FPattern.PieceCaption(TPieceObject(Node)), PlacesStacked(Screen, Size.cx, Size.cy, LABEL_RINGS));
      end
      else if (Pass = 1) and (Node is TPointObject) then
      begin
        Screen := FState.View.ToScreen(TPointObject(Node).Position);
        Size := FBitmap.TextSize(Node.DisplayName);
        if NearScreen(Screen) then
          Request(TDraftObject(Node), Node.DisplayName, PlacesAround(Screen, Size.cx, Size.cy, LABEL_GAP_PIXELS, LABEL_RINGS));
      end
      else if (Pass = 2) and (Node is TEdgeObject) then
      begin
        Model := EdgePolyline(TEdgeObject(Node), FState.View.PixelsToMM(FLATTEN_PIXELS));
        if Length(Model) = 0 then
          Continue;
        Line := nil;
        SetLength(Line, Length(Model));
        for Index := 0 to High(Model) do
          Line[Index] := FState.View.ToScreen(Model[Index]);
        Size := FBitmap.TextSize(Node.DisplayName);
        if NearScreen(PolylineMiddle(Line)) then
          Request(TDraftObject(Node), Node.DisplayName, PlacesAlong(PolylinePlaces(Line), Size.cx, Size.cy, LABEL_GAP_PIXELS));
      end;
    end;
  Places := PlaceLabels(Requests, Obstacles, False, Default(TRect2));
  for Index := 0 to High(Requests) do
    FBitmap.TextOut(Places[Index].X, Places[Index].Y, Texts[Index], Colors[Index]);
end;

procedure TPatternPainter.DrawSnap(const Snap: TSnap; Preview: TSnapPreview; const StartAt: TVec2);
var
  Screen, Base, Start: TVec2;
  Node: TEvalNode;
  Size: single;
begin
  Screen := FState.View.ToScreen(Snap.Position);
  Size := SNAP_MARKER_SIZE;
  if Preview <> spNone then
  begin
    Start := FState.View.ToScreen(StartAt);
    FBitmap.PenStyle := psDash;
    case Preview of
      spCircle:
        FBitmap.EllipseAntialias(Start.X, Start.Y, Distance(Start, Screen), Distance(Start, Screen), SelectedInk, 1.5);
      spRectangle:
        FBitmap.RectangleAntialias(Min(Start.X, Screen.X), Min(Start.Y, Screen.Y), Max(Start.X, Screen.X), Max(Start.Y, Screen.Y),
          SelectedInk, 1.5);
      else
        FBitmap.DrawLineAntialias(Start.X, Start.Y, Screen.X, Screen.Y, SelectedInk, 1.5);
    end;
    FBitmap.PenStyle := psSolid;
  end;
  if Snap.Kind in [snHorizontal, snVertical] then
  begin
    Node := FPattern.FindNode(Snap.PointKey);
    if Node is TPointObject then
    begin
      Base := FState.View.ToScreen(TPointObject(Node).Position);
      FBitmap.PenStyle := psDot;
      FBitmap.DrawLineAntialias(Base.X, Base.Y, Screen.X, Screen.Y, SnapInk, 1);
      FBitmap.PenStyle := psSolid;
    end;
  end;
  case Snap.Kind of
    snPoint:
      FBitmap.EllipseAntialias(Screen.X, Screen.Y, Size, Size, SnapInk, 2);
    snCrossing:
    begin
      FBitmap.DrawLineAntialias(Screen.X - Size, Screen.Y - Size, Screen.X + Size, Screen.Y + Size, SnapInk, 2);
      FBitmap.DrawLineAntialias(Screen.X - Size, Screen.Y + Size, Screen.X + Size, Screen.Y - Size, SnapInk, 2);
    end;
    snEdge:
      FBitmap.DrawPolygonAntialias([PointF(Screen.X, Screen.Y - Size), PointF(Screen.X + Size, Screen.Y),
        PointF(Screen.X, Screen.Y + Size), PointF(Screen.X - Size, Screen.Y)], SnapInk, 2);
    snHorizontal, snVertical:
      FBitmap.RectangleAntialias(Screen.X - Size + 1, Screen.Y - Size + 1, Screen.X + Size - 1, Screen.Y + Size - 1, SnapInk, 2);
    else
    begin
      FBitmap.DrawLineAntialias(Screen.X - Size, Screen.Y, Screen.X + Size, Screen.Y, SnapInk, 1.5);
      FBitmap.DrawLineAntialias(Screen.X, Screen.Y - Size, Screen.X, Screen.Y + Size, SnapInk, 1.5);
    end;
  end;
end;

procedure TPatternPainter.DrawBox(const Corner, OtherCorner: TPoint);
var
  X1, Y1, X2, Y2: single;
begin
  X1 := Min(Corner.X, OtherCorner.X) + 0.5;
  X2 := Max(Corner.X, OtherCorner.X) + 0.5;
  Y1 := Min(Corner.Y, OtherCorner.Y) + 0.5;
  Y2 := Max(Corner.Y, OtherCorner.Y) + 0.5;
  FBitmap.FillRectAntialias(X1, Y1, X2, Y2, BoxFill);
  FBitmap.PenStyle := psDot;
  FBitmap.RectangleAntialias(X1, Y1, X2, Y2, SelectedInk, 1);
  FBitmap.PenStyle := psSolid;
end;

procedure TPatternPainter.DrawFieldGuide(const Guide: TFieldGuide);
var
  Start, Finish, Direction, Centre: TVec2;
  Reach: double;
begin
  FBitmap.PenStyle := psDash;
  case Guide.Kind of
    fgLine:
    begin
      Start := FState.View.ToScreen(Guide.Start);
      Finish := FState.View.ToScreen(Guide.Finish);
      if Distance(Start, Finish) > 0 then
      begin
        // Past both edges of the canvas from anywhere on it
        Reach := 2 * (FBitmap.Width + FBitmap.Height) + Distance(Start, Vec2(FBitmap.Width / 2, FBitmap.Height / 2));
        Direction := (Finish - Start).Normalized * Reach;
        FBitmap.DrawLineAntialias(Start.X - Direction.X, Start.Y - Direction.Y, Start.X + Direction.X, Start.Y + Direction.Y,
          GuideInk, FIELD_GUIDE_WIDTH);
      end;
    end;
    fgCircle:
    begin
      Centre := FState.View.ToScreen(Guide.Centre);
      Reach := Guide.Radius * FState.View.Scale;
      FBitmap.EllipseAntialias(Centre.X, Centre.Y, Reach, Reach, GuideInk, FIELD_GUIDE_WIDTH);
    end;
  end;
  FBitmap.PenStyle := psSolid;
end;

procedure TPatternPainter.DrawGhost(const Position: TVec2);
var
  Screen: TVec2;
begin
  Screen := FState.View.ToScreen(Position);
  FBitmap.PenStyle := psDash;
  FBitmap.EllipseAntialias(Screen.X, Screen.Y, GHOST_RADIUS, GHOST_RADIUS, SelectedInk, GHOST_WIDTH);
  FBitmap.PenStyle := psSolid;
  FBitmap.FillEllipseAntialias(Screen.X, Screen.Y, POINT_RADIUS, POINT_RADIUS, HoverHalo);
end;

procedure TPatternPainter.DrawGradeGhost(const Ghost: TGradeGhost);
var
  Line: TVec2Array;
  Screen: array of TPointF;
  Index: integer;
  Spot: TVec2;
begin
  FBitmap.PenStyle := psDash;
  for Line in Ghost.Lines do
  begin
    Screen := nil;
    SetLength(Screen, Length(Line));
    for Index := 0 to High(Line) do
      Screen[Index] := ScreenPoint(FState.View.ToScreen(Line[Index]));
    FBitmap.DrawPolyLineAntialias(Screen, GradeGhostInk, GHOST_WIDTH);
  end;
  if Ghost.HasPoint then
  begin
    Spot := FState.View.ToScreen(Ghost.Point);
    FBitmap.EllipseAntialias(Spot.X, Spot.Y, GHOST_RADIUS, GHOST_RADIUS, GradeGhostInk, GHOST_WIDTH);
  end;
  FBitmap.PenStyle := psSolid;
end;

end.
