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

// The draft as an SVG, to look at or to check: edges as true lines and Bézier
// curves, points, and optionally their names. Coordinates are millimetres
// as in the model, since both have y down. Reads computed geometry only.
unit Sloper.Output.DraftSVG;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Evaluator, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern, Sloper.Core.Note;

type
  TDraftSVGOptions = record
    // Names every point, edge and piece, as the canvas's All labels
    Labels: boolean;
    // Names only these objects, as the canvas was showing them; Labels is
    // then ignored
    LabelChosen: boolean;
    LabelKeys: TStringArray;
    // Names only the objects with these names, compared as names are, in
    // every draft an animation shows; Labels is then ignored
    LabelNames: TStringArray;
    // Pieces are left unfilled, as with View -> Piece Fills off
    NoFills: boolean;
    // Show only this part of the draft, in model millimetres
    HasRegion: boolean;
    Region: TRect2;
    // Lines of these roles are left out, as the canvas hides them
    HiddenRoles: TEdgeRoles;
    // Notes are left out, as View -> Annotations off hides them
    HideAnnotations: boolean;
    // Pieces the canvas hides are left out, with what only they use, and
    // pieces drawn in the view's order; an isolated piece changes nothing
    FollowPieceView: boolean;
    // For {pattern.name} in notes; empty leaves it as typed
    PatternFileName: string;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
// The patterns' drafts in turn, each for a few seconds and fading into the
// next, looping, all drawn at the same scale in a view that holds them all.
// Where animation is off or not shown, the last is drawn.
function AnimatedDraftToSVG(const Patterns: array of TPattern; const Options: TDraftSVGOptions): string;
// A number as written in SVG
function SVGNumber(Value: double): string;
function EscapeXML(const Text: string): string;
// A note's font as SVG attributes: its family first, then the default
// families, and its weight and style when bold or italic
function NoteFontAttributes(const Style: TTextStyle): string;

implementation

uses
  Math, Sloper.Core.Bezier, Sloper.Core.Bounds, Sloper.Core.Drag, Sloper.Core.EvalTypes, Sloper.Core.Materials, Sloper.Core.Piece,
  Sloper.Core.TextFields,
  // Measures notes in a named font, here and wherever this unit is used
  Sloper.Output.Fonts;

const
  // The default font of notes, and what follows a named one
  NOTE_FONT_FAMILIES = 'Helvetica, Arial, sans-serif';
  COORDINATE_DECIMALS = 3;
  // Of the longer side, so a drawing reads the same at any size
  LINE_SHARE = 0.0015;
  CONSTRUCTION_SHARE = 0.0008;
  POINT_SHARE = 0.003;
  FONT_SHARE = 0.014;
  MARGIN_SHARE = 0.05;
  MINIMUM_EXTENT = 10;
  EMPTY_EXTENT = 100;
  INK_COLOR = '#202020';
  CONSTRUCTION_COLOR = '#808080';
  ERROR_COLOR = '#c02020';
  BLOCKED_COLOR = '#e08000';
  // Share of the view's size between hatching lines
  HATCH_SHARE = 0.012;
  // A callout's leader, in mm, as printed
  NOTE_LINE_WIDTH = 0.25;
  // How long an animation shows each draft, and how long the next takes to
  // fade in over it, in seconds
  FRAME_SECONDS = 2.5;
  FADE_SECONDS = 0.5;
  // Between two keyframes that change at once, in percent
  KEYFRAME_STEP = 0.01;

type
  TDraftView = record
    Left, Top, Width, Height, Extent: double;
  end;

function DefaultDraftSVGOptions: TDraftSVGOptions;
begin
  Result := Default(TDraftSVGOptions);
end;

function SVGNumber(Value: double): string;
begin
  Result := RoundedText(Value, COORDINATE_DECIMALS);
end;

function Num(Value: double): string;
begin
  Result := SVGNumber(Value);
end;

// Model and SVG both have y down
function Coord(const Point: TVec2): string;
begin
  Result := Num(Point.X) + ' ' + Num(Point.Y);
end;

function EscapeXML(const Text: string): string;
begin
  Result := StringReplace(Text, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

// CheckFontName keeps quotes out of the name
function NoteFontAttributes(const Style: TTextStyle): string;
begin
  Result := NOTE_FONT_FAMILIES;
  if Style.Font <> '' then
    Result := '''' + EscapeXML(Style.Font) + ''', ' + Result;
  Result := 'font-family="' + Result + '"';
  if Style.Bold then
    Result := Result + ' font-weight="bold"';
  if Style.Italic then
    Result := Result + ' font-style="italic"';
end;

function StateColor(State: TEvalState; const Normal: string): string;
begin
  case State of
    esError, esInvalid: Result := ERROR_COLOR;
    esBlocked: Result := BLOCKED_COLOR;
    else
      Result := Normal;
  end;
end;

function EdgePath(Edge: TEdgeObject): string;
var
  Segment: TEdgeSegment;
  First: boolean;
begin
  Result := '';
  First := True;
  for Segment in Edge.Segments do
    if Segment.Kind = skLine then
    begin
      if First then
        Result := 'M ' + Coord(Segment.Line.P1);
      Result := Result + ' L ' + Coord(Segment.Line.P2);
      First := False;
    end
    else
    begin
      if First then
        Result := 'M ' + Coord(Segment.Curve.P0);
      Result := Result + ' C ' + Coord(Segment.Curve.P1) + ' ' + Coord(Segment.Curve.P2) + ' ' + Coord(Segment.Curve.P3);
      First := False;
    end;
end;

// The part of the drawing shown, in millimetres. Extent is the
// longer side, which line widths and text sizes are shares of.
function DraftView(Pattern: TPattern; const Options: TDraftSVGOptions): TDraftView;
var
  Bounds: TRect2;
  Margin: double;
  Found: boolean;
begin
  Found := True;
  if Options.HasRegion then
    Bounds := Options.Region
  else
    Found := PatternBounds(Pattern, Bounds, not Options.HideAnnotations);
  if not Found then
  begin
    Bounds := Default(TRect2);
    Bounds.MaxX := EMPTY_EXTENT;
    Bounds.MaxY := EMPTY_EXTENT;
  end;
  Result.Extent := Max(Max(Bounds.MaxX - Bounds.MinX, Bounds.MaxY - Bounds.MinY), MINIMUM_EXTENT);
  Margin := 0;
  if not Options.HasRegion then
    Margin := Result.Extent * MARGIN_SHARE;
  Result.Left := Bounds.MinX - Margin;
  Result.Top := Bounds.MinY - Margin;
  Result.Width := Bounds.MaxX - Bounds.MinX + 2 * Margin;
  Result.Height := Bounds.MaxY - Bounds.MinY + 2 * Margin;
end;

function SVGStart(const View: TDraftView): string;
begin
  Result := Format('<svg xmlns="http://www.w3.org/2000/svg" width="%smm" height="%smm" viewBox="%s %s %s %s">',
    [Num(View.Width), Num(View.Height), Num(View.Left), Num(View.Top), Num(View.Width), Num(View.Height)]) + #10 +
    Format('<rect x="%s" y="%s" width="%s" height="%s" fill="#ffffff"/>', [Num(View.Left), Num(View.Top), Num(View.Width), Num(View.Height)]) + #10;
end;

function EdgeElement(Edge: TEdgeObject; Extent: double): string;
var
  Color, Dash: string;
  Stroke, Length: double;
begin
  Dash := '';
  case Edge.Role of
    erOutline:
    begin
      Color := INK_COLOR;
      Stroke := Extent * LINE_SHARE;
    end;
    erConstruction:
    begin
      Color := CONSTRUCTION_COLOR;
      Stroke := Extent * CONSTRUCTION_SHARE;
      Dash := Format(' stroke-dasharray="%s %s"', [Num(Stroke * 4), Num(Stroke * 3)]);
    end;
    else
    begin
      // A marking line in its role's colour, dashed as on paper but scaled
      // with the drawing, like the other lines
      Color := ROLE_COLORS[Edge.Role];
      Stroke := Extent * LINE_SHARE * 0.75;
      for Length in ROLE_DASHES[Edge.Role] do
        if Length > 0 then
          Dash := Dash + ' ' + Num(Length * Stroke * 2);
      if Dash <> '' then
        Dash := Format(' stroke-dasharray="%s"', [Trim(Dash)]);
    end;
  end;
  Result := Format('<path data-id="%s" data-name="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"%s/>',
    [Edge.Key, EscapeXML(Edge.DisplayName), EdgePath(Edge), StateColor(Edge.State, Color), Num(Stroke), Dash]) + #10;
end;

// The cutting line, filled, so the edges drawn over it show the seam line
function PieceElement(Pattern: TPattern; Piece: TPieceObject; Extent: double; NoFills: boolean): string;
var
  Index: integer;
  PathText, FillText, HatchText: string;
  Look: TPieceLook;
  Stroke: TLine2;
begin
  Look := Pattern.PieceLook(Piece);
  if NoFills then
    Look.Filled := False;
  FillText := 'none';
  if Look.Filled and (Look.Fill = ffTint) then
    FillText := LowerCase(MaterialColorText(MaterialTint(Look.Color)));
  PathText := '';
  for Index := 0 to High(Piece.CutLine) do
    if Index = 0 then
      PathText := 'M ' + Coord(Piece.CutLine[Index])
    else
      PathText := PathText + ' L ' + Coord(Piece.CutLine[Index]);
  Result := Format('<path data-id="%s" data-name="%s" d="%s Z" fill="%s" stroke="%s" stroke-width="%s"/>',
    [Piece.Key, EscapeXML(Piece.DisplayName), PathText, FillText, StateColor(Piece.State, INK_COLOR), Num(Extent * LINE_SHARE)]) + #10;
  if not Look.Filled or (Look.Fill <> ffHatch) then
    Exit;
  HatchText := '';
  for Stroke in HatchLines(Piece.CutLine, Extent * HATCH_SHARE, Look.HatchAngle) do
    HatchText := HatchText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
  if HatchText <> '' then
    Result := Result + Format('<path data-id="%s" data-hatch="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [Piece.Key, EscapeXML(Piece.DisplayName), Trim(HatchText), LowerCase(MaterialColorText(Look.Color)), Num(Extent * LINE_SHARE)]) + #10;
end;

// The grainline and notches, over the edges
function PieceMarksElement(Piece: TPieceObject; Extent: double): string;
var
  Stroke: TLine2;
  Mark: TNotchMark;
  PathText: string;
begin
  PathText := '';
  for Stroke in Concat(Piece.GrainArrow, Piece.FoldArrow, Piece.MarkingStrokes) do
    PathText := PathText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
  for Mark in Piece.NotchMarks do
    PathText := PathText + 'M ' + Coord(Mark.Cut) + ' L ' + Coord(Mark.Tip) + ' ';
  Result := '';
  if PathText <> '' then
    Result := Format('<path data-id="%s" data-marks="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [Piece.Key, EscapeXML(Piece.DisplayName), Trim(PathText), StateColor(Piece.State, INK_COLOR), Num(Extent * LINE_SHARE)]) + #10;
end;

function PieceLabelElement(Pattern: TPattern; Piece: TPieceObject; Extent: double): string;
var
  Middle: TVec2;
begin
  Middle := Piece.Middle;
  Result := Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
    [Num(Middle.X), Num(Middle.Y), Num(Extent * FONT_SHARE), StateColor(Piece.State, INK_COLOR), EscapeXML(Pattern.PieceCaption(Piece))]) + #10;
end;

function LabelElement(const At: TVec2; Extent: double; const Color, Text: string): string;
var
  Offset: double;
begin
  Offset := Extent * POINT_SHARE * 1.5;
  Result := Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%s" fill="%s">%s</text>',
    [Num(At.X + Offset), Num(At.Y - Offset), Num(Extent * FONT_SHARE), Color, EscapeXML(Text)]) + #10;
end;

// Halfway along the edge, where the canvas puts its name
function EdgeLabelElement(Edge: TEdgeObject; Extent: double): string;
begin
  Result := LabelElement(Edge.PointAtLength(Edge.Length / 2), Extent, StateColor(Edge.State, INK_COLOR), Edge.DisplayName);
end;

function PointElement(Point: TPointObject; Extent: double; Labels: boolean): string;
var
  Radius: double;
  Color: string;
begin
  Radius := Extent * POINT_SHARE;
  Color := StateColor(Point.State, INK_COLOR);
  Result := Format('<circle data-id="%s" data-name="%s" cx="%s" cy="%s" r="%s" fill="%s"/>',
    [Point.Key, EscapeXML(Point.DisplayName), Num(Point.Position.X), Num(Point.Position.Y), Num(Radius), Color]) + #10;
  if Labels then
    Result := Result + LabelElement(Point.Position, Extent, Color, Point.DisplayName);
end;

// A point's or repeat's marker, whether or not it is on a piece yet
function MarkerElement(DraftObject: TDraftObject; Extent: double): string;
var
  Centre: TVec2;
  Stroke: TLine2;
  PathText: string;
begin
  PathText := '';
  if DraftObject.MarkerSize > 0 then
    for Centre in MarkerPositions(DraftObject) do
      for Stroke in MarkerStrokes(DraftObject.Marker, Centre, DraftObject.MarkerSize) do
        PathText := PathText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
  Result := '';
  if PathText <> '' then
    Result := Format('<path data-id="%s" data-marker="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [DraftObject.Key, POINT_MARKER_NAMES[DraftObject.Marker], Trim(PathText), StateColor(DraftObject.State, INK_COLOR),
      Num(Extent * LINE_SHARE)]) + #10;
end;

// At its true printed size over everything else: a callout's leader, a white
// box when it has one, and a text element per line
function NoteElement(Note: TNoteObject; const Values: TFieldValues): string;
var
  Lines: TStringArray;
  Index: integer;
  Box, Frame: TRect2;
  Start: TVec2;
  Color, PathText: string;
  Stroke: TLine2;
begin
  Result := '';
  Color := StateColor(Note.State, INK_COLOR);
  Box := NoteBox(Note, Values);
  Frame := NoteFrame(Note, Values);
  if (Note.Leader <> nlNone) and LeaderStart(Frame, Note.AnchorPosition, Start) then
  begin
    PathText := '';
    for Stroke in LeaderStrokes(Start, Note.AnchorPosition, Note.Leader) do
      PathText := PathText + 'M ' + Coord(Stroke.P1) + ' L ' + Coord(Stroke.P2) + ' ';
    Result := Result + Format('<path data-id="%s" d="%s" fill="none" stroke="%s" stroke-width="%s"/>',
      [Note.Key, Trim(PathText), Color, Num(NOTE_LINE_WIDTH)]) + #10;
    if Note.Leader = nlDot then
      Result := Result + Format('<circle data-id="%s" cx="%s" cy="%s" r="%s" fill="%s"/>',
        [Note.Key, Num(Note.AnchorPosition.X), Num(Note.AnchorPosition.Y), Num(LEADER_DOT_RADIUS), Color]) + #10;
  end;
  if Note.Boxed then
    Result := Result + Format('<rect data-id="%s" x="%s" y="%s" width="%s" height="%s" fill="#ffffff"/>',
      [Note.Key, Num(Frame.MinX), Num(Frame.MinY), Num(Frame.MaxX - Frame.MinX), Num(Frame.MaxY - Frame.MinY)]) + #10;
  Lines := TextLines(ExpandFields(Note.ShownText, Values));
  for Index := 0 to High(Lines) do
    Result := Result + Format('<text data-id="%s" x="%s" y="%s" %s font-size="%s" fill="%s">%s</text>',
      [Note.Key, Num(AlignedLeft(Box.MinX, Box.MaxX - Box.MinX, TextWidth(Lines[Index], Note.Size, Note.Style), Note.Align)),
      Num(Note.Position.Y + (Index + 1) * LineHeight(Note.Size)), NoteFontAttributes(Note.Style), Num(Note.Size * POINTS_TO_MM), Color,
      EscapeXML(Lines[Index])]) + #10;
end;

function AllObjects(Pattern: TPattern): TDraftObjectArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Pattern.ObjectCount);
  for Index := 0 to Pattern.ObjectCount - 1 do
    Result[Index] := Pattern.Objects[Index];
end;

// Everything drawn, in the view given
function DraftElements(Pattern: TPattern; const Options: TDraftSVGOptions; const View: TDraftView): string;
var
  Index: integer;
  DraftObject: TDraftObject;
  Point: TPointObject;

  function Labelled(DraftObject: TDraftObject): boolean;
  var
    Key: string;
  begin
    if Length(Options.LabelNames) > 0 then
    begin
      for Key in Options.LabelNames do
        if SameText(Key, DraftObject.Name) then
          Exit(True);
      Exit(False);
    end;
    if not Options.LabelChosen then
      Exit(Options.Labels);
    for Key in Options.LabelKeys do
      if Key = DraftObject.Key then
        Exit(True);
    Result := False;
  end;

  function Shown(DraftObject: TDraftObject): boolean;
  begin
    Result := DraftObject.HasResult and (not Options.FollowPieceView or (Pattern.HiddenPieceCount = 0) or not Pattern.IsHidden(DraftObject));
  end;

var
  Pieces: TPieceObjectArray;
  Piece: TPieceObject;
begin
  Result := '';
  if Options.FollowPieceView then
    Pieces := Pattern.PiecesInDrawOrder
  else
    Pieces := Pattern.PieceList;
  // Pieces under edges, edges under points
  for Piece in Pieces do
    if Shown(Piece) then
      Result := Result + PieceElement(Pattern, Piece, View.Extent, Options.NoFills);
  for DraftObject in EdgesInDrawOrder(AllObjects(Pattern)) do
  begin
    if Shown(DraftObject) and (Length(TEdgeObject(DraftObject).Segments) > 0) and not (TEdgeObject(DraftObject).Role in Options.HiddenRoles) then
    begin
      Result := Result + EdgeElement(TEdgeObject(DraftObject), View.Extent);
      if Labelled(DraftObject) then
        Result := Result + EdgeLabelElement(TEdgeObject(DraftObject), View.Extent);
    end;
  end;
  for Piece in Pieces do
    if Shown(Piece) then
    begin
      Result := Result + PieceMarksElement(Piece, View.Extent);
      if Labelled(Piece) then
        Result := Result + PieceLabelElement(Pattern, Piece, View.Extent);
    end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    DraftObject := Pattern.Objects[Index];
    if (DraftObject.Marker <> pmPlain) and Shown(DraftObject) then
      Result := Result + MarkerElement(DraftObject, View.Extent);
  end;
  for Point in Pattern.AllPoints do
    if Shown(Point) then
      Result := Result + PointElement(Point, View.Extent, Labelled(Point));
  // Screen-only notes never leave the app
  if not Options.HideAnnotations then
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      DraftObject := Pattern.Objects[Index];
      if (DraftObject is TNoteObject) and Shown(DraftObject) and TNoteObject(DraftObject).Print then
        Result := Result + NoteElement(TNoteObject(DraftObject), NoteFieldValues(Pattern, TNoteObject(DraftObject),
          PatternFieldValues(Pattern, Options.PatternFileName)));
    end;
end;

function DraftToSVG(Pattern: TPattern; const Options: TDraftSVGOptions): string;
var
  View: TDraftView;
begin
  View := DraftView(Pattern, Options);
  Result := SVGStart(View) + DraftElements(Pattern, Options, View) + '</svg>' + #10;
end;

// When frame Frame of Count is seen, as CSS keyframes of its opacity: it fades
// in over the one before, which stays until it has, and the first is back
// under the last as that fades out to start again
function FrameKeyframes(Frame, Count: integer): string;
var
  Total: double;

  function At(Seconds: double): double;
  begin
    Result := 100 * Seconds / Total;
  end;

  function Key(Percent, Opacity: double): string;
  begin
    Result := Format('%s%%{opacity:%s}', [Num(Percent), Num(Opacity)]);
  end;

begin
  Total := Count * FRAME_SECONDS;
  Result := Format('@keyframes frame%d{', [Frame]);
  if Frame = 0 then
    Result := Result + Key(0, 1) + Key(At(FRAME_SECONDS + FADE_SECONDS), 1) +
      Key(At(FRAME_SECONDS + FADE_SECONDS) + KEYFRAME_STEP, 0) + Key(At(Total - FADE_SECONDS) - KEYFRAME_STEP, 0) +
      Key(At(Total - FADE_SECONDS), 1) + Key(100, 1)
  else
  begin
    Result := Result + Key(0, 0) + Key(At(Frame * FRAME_SECONDS), 0) + Key(At(Frame * FRAME_SECONDS + FADE_SECONDS), 1);
    if Frame < Count - 1 then
      Result := Result + Key(At((Frame + 1) * FRAME_SECONDS + FADE_SECONDS), 1) +
        Key(At((Frame + 1) * FRAME_SECONDS + FADE_SECONDS) + KEYFRAME_STEP, 0) + Key(100, 0)
    else
      Result := Result + Key(At(Total - FADE_SECONDS), 1) + Key(100, 0);
  end;
  Result := Result + '}' + #10;
end;

function AnimatedDraftToSVG(const Patterns: array of TPattern; const Options: TDraftSVGOptions): string;
var
  View, Frame: TDraftView;
  Index: integer;
  Right, Bottom: double;
begin
  if Length(Patterns) = 1 then
    Exit(DraftToSVG(Patterns[0], Options));
  View := DraftView(Patterns[0], Options);
  for Index := 1 to High(Patterns) do
  begin
    Frame := DraftView(Patterns[Index], Options);
    Right := Max(View.Left + View.Width, Frame.Left + Frame.Width);
    Bottom := Max(View.Top + View.Height, Frame.Top + Frame.Height);
    View.Left := Min(View.Left, Frame.Left);
    View.Top := Min(View.Top, Frame.Top);
    View.Width := Right - View.Left;
    View.Height := Bottom - View.Top;
    View.Extent := Max(View.Extent, Frame.Extent);
  end;
  Result := SVGStart(View) + '<style>' + #10 +
    Format('.frame{animation-duration:%ss;animation-iteration-count:infinite;animation-timing-function:linear}',
    [Num(Length(Patterns) * FRAME_SECONDS)]) + #10;
  for Index := 0 to High(Patterns) do
    Result := Result + FrameKeyframes(Index, Length(Patterns));
  // Each frame has its own background, so the last hides the rest
  Result := Result + '@media (prefers-reduced-motion: reduce){.frame{animation:none}}' + #10 + '</style>' + #10;
  for Index := 0 to High(Patterns) do
    Result := Result + Format('<g class="frame" style="animation-name:frame%d">', [Index]) + #10 +
      Format('<rect x="%s" y="%s" width="%s" height="%s" fill="#ffffff"/>', [Num(View.Left), Num(View.Top), Num(View.Width),
      Num(View.Height)]) + #10 + DraftElements(Patterns[Index], Options, View) + '</g>' + #10;
  Result := Result + '</svg>' + #10;
end;

end.
