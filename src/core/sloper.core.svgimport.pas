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

// Reads an SVG drawing from another app (a logo, a fold diagram) into a
// stamp's drawing (Sloper.Core.Stamp), at true size from the SVG's own units.
// Paths and the basic shapes are read, through groups and transforms, with
// their fill and stroke colours. Text is refused, asking for it to be
// converted to paths, which keeps fonts out of patterns; so are bitmaps and
// clones. Sizes in pixels are taken at 96 to the inch, with a warning, as are
// gradients, style sheets, clipping and transparency, which are left out.
// No LCL dependency.
unit Sloper.Core.SvgImport;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Stamp;

const
  // The largest SVG file read, in bytes
  MAX_SVG_BYTES = 8 * 1024 * 1024;

// The drawing in SvgText, with its top left at (0, 0). False with the reason
// when it cannot be a stamp; Warnings say what was drawn differently.
function ImportSvgStamp(const SvgText: string; out Drawing: TStampDrawing; out Warnings: TStringArray;
  out ErrorMessage: string): boolean;
function ImportSvgStampFile(const FileName: string; out Drawing: TStampDrawing; out Warnings: TStringArray;
  out ErrorMessage: string): boolean;

resourcestring
  rsSvgNotXml = 'The file is not an SVG drawing: %s';
  rsSvgDoctypeSubset = 'The drawing has a document type with an internal subset. Save it again without the document type';
  rsSvgDoctypeUnread = 'The drawing''s document type could not be read. Save it again without the document type';
  rsSvgNotSvg = 'The file is not an SVG drawing';
  rsSvgTooLarge = 'The file is too large for a stamp: at most %d MB';
  rsSvgText = 'The drawing has text, which a stamp cannot hold; convert the text to paths first (in Inkscape, Path ' +
    '> Object to Path)';
  rsSvgImage = 'The drawing holds a bitmap image; a stamp can only hold paths';
  rsSvgUse = 'The drawing has clones; unlink them first (in Inkscape, Edit > Clone > Unlink Clone)';
  rsSvgEmpty = 'The drawing has nothing to draw';
  rsSvgTooDeep = 'The drawing''s groups are nested too deep';
  rsSvgPixels = 'Its size is in pixels, taken at 96 to the inch';
  rsSvgGradient = 'Gradients and patterns are drawn in black';
  rsSvgStyleSheet = 'Its style sheet is not read, only the style on each shape';
  rsSvgClip = 'Clipping and masks are left out';
  rsSvgOpacity = 'Transparency is left out';
  rsSvgColour = 'Colours it does not know are drawn in black';
  rsSvgBadPath = 'A path is drawn only up to where its data could not be read';

implementation

uses
  Classes, Math, StrUtils, DOM, XMLRead, XMLUtils, Sloper.Core.Geometry, Sloper.Core.JSON;

const
  SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
  // CSS pixels to the inch, and mm to the inch
  PIXELS_PER_INCH = 96;
  MM_PER_INCH = 25.4;
  POINTS_PER_INCH = 72;
  PICAS_PER_INCH = 6;
  // An em, in pixels, as browsers take it by default
  EM_PIXELS = 16;
  MAX_DEPTH = 256;
  BYTES_PER_MB = 1024 * 1024;
  BLACK = 0;
  COLOUR_CHANNEL = 255;
  PERCENT = 100;
  // An arc is drawn as cubics of at most a quarter turn
  ARC_PIECE = Pi / 2;
  // How closely a curve is followed to find the drawing's edges, in mm
  BOUNDS_TOLERANCE = 0.01;
  // Elements read through for what is inside them
  CONTAINER_NAMES: array[0..3] of string = ('g', 'a', 'switch', 'svg');
  // Elements whose contents are not drawn where they stand
  SKIPPED_NAMES: array[0..11] of string = ('defs', 'symbol', 'clipPath', 'mask', 'pattern', 'marker', 'linearGradient', 'radialGradient',
    'metadata', 'title', 'desc', 'filter');
  TEXT_NAMES: array[0..4] of string = ('text', 'tspan', 'textPath', 'flowRoot', 'flowPara');
  IMAGE_NAMES: array[0..1] of string = ('image', 'foreignObject');
  // The presentation attributes read: the colour first, which currentColor
  // in the others takes
  STYLE_PROPERTY_NAMES: array[0..10] of string = ('color', 'fill', 'stroke', 'stroke-width', 'fill-rule', 'visibility', 'opacity',
    'fill-opacity', 'stroke-opacity', 'clip-path', 'mask');
  // The colours of CSS's basic list, and a few more drawings commonly use
  COLOUR_NAMES: array[0..25] of string = ('black', 'white', 'red', 'green', 'blue', 'yellow', 'cyan', 'magenta', 'gray', 'grey', 'silver',
    'maroon', 'olive', 'lime', 'aqua', 'teal', 'navy', 'fuchsia', 'purple', 'orange', 'brown', 'pink', 'darkgray', 'darkgrey', 'lightgray',
    'lightgrey');
  COLOUR_VALUES: array[0..25] of integer = ($000000, $FFFFFF, $FF0000, $008000, $0000FF, $FFFF00, $00FFFF, $FF00FF, $808080, $808080,
    $C0C0C0, $800000, $808000, $00FF00, $00FFFF, $008080, $000080, $FF00FF, $800080, $FFA500, $A52A2A, $FFC0CB, $A9A9A9, $A9A9A9,
    $D3D3D3, $D3D3D3);

type
  // x' = A x + C y + E, y' = B x + D y + F, as SVG writes a matrix
  TAffine = record
    A, B, C, D, E, F: double;
  end;

  TWarning = (wnPixels, wnGradient, wnStyleSheet, wnClip, wnOpacity, wnColour, wnBadPath);

  // What a shape takes from its groups unless it says otherwise
  TSvgStyle = record
    Fill, Stroke, Color: integer;
    // In the shape's own units
    StrokeWidth: double;
    EvenOdd, Hidden: boolean;
  end;

  TSvgReader = class
  private
    FPaths: TStampPathArray;
    FWarned: set of TWarning;
    FError: string;
    FSegments: integer;
    procedure Warn(Warning: TWarning);
    function Refuse(const Reason: string): boolean;
    function ReadColour(const Text: string; const Style: TSvgStyle; out Colour: integer): boolean;
    procedure ApplyProperty(const Name, Value: string; var Style: TSvgStyle);
    procedure ReadStyle(Element: TDOMElement; var Style: TSvgStyle);
    function ShapeContours(Element: TDOMElement; const Name: string; out Contours: TStampContourArray): boolean;
    procedure AddShape(Contours: TStampContourArray; const Matrix: TAffine; const Style: TSvgStyle);
    function ReadChildren(Element: TDOMElement; const Matrix: TAffine; const Style: TSvgStyle; Depth: integer): boolean;
    function ReadElement(Element: TDOMElement; const Matrix: TAffine; const Style: TSvgStyle; Depth: integer): boolean;
  public
    function Read(Root: TDOMElement; out Drawing: TStampDrawing; out Warnings: TStringArray; out ErrorMessage: string): boolean;
  end;

function Identity: TAffine;
begin
  Result.A := 1;
  Result.B := 0;
  Result.C := 0;
  Result.D := 1;
  Result.E := 0;
  Result.F := 0;
end;

function Affine(AA, AB, AC, AD, AE, AF: double): TAffine;
begin
  Result.A := AA;
  Result.B := AB;
  Result.C := AC;
  Result.D := AD;
  Result.E := AE;
  Result.F := AF;
end;

// First after Second: Second is applied to a point before First
function Combined(const First, Second: TAffine): TAffine;
begin
  Result.A := First.A * Second.A + First.C * Second.B;
  Result.B := First.B * Second.A + First.D * Second.B;
  Result.C := First.A * Second.C + First.C * Second.D;
  Result.D := First.B * Second.C + First.D * Second.D;
  Result.E := First.A * Second.E + First.C * Second.F + First.E;
  Result.F := First.B * Second.E + First.D * Second.F + First.F;
end;

function Applied(const Matrix: TAffine; const Point: TVec2): TVec2;
begin
  Result := Vec2(Matrix.A * Point.X + Matrix.C * Point.Y + Matrix.E, Matrix.B * Point.X + Matrix.D * Point.Y + Matrix.F);
end;

procedure MoveContour(var Contour: TStampContour; const Matrix: TAffine);
var
  Index: integer;
begin
  Contour.Start := Applied(Matrix, Contour.Start);
  for Index := 0 to High(Contour.Segments) do
  begin
    Contour.Segments[Index].Control1 := Applied(Matrix, Contour.Segments[Index].Control1);
    Contour.Segments[Index].Control2 := Applied(Matrix, Contour.Segments[Index].Control2);
    Contour.Segments[Index].Finish := Applied(Matrix, Contour.Segments[Index].Finish);
  end;
end;

function IsIn(const Name: string; const Names: array of string): boolean;
var
  Index: integer;
begin
  for Index := 0 to High(Names) do
    if Names[Index] = Name then
      Exit(True);
  Result := False;
end;

{ Numbers and lengths }

type
  // Reads numbers one at a time from path data, a points list, a viewBox or
  // a transform's arguments, separated by spaces, commas or nothing at all
  TNumberScanner = record
    Text: string;
    Position: integer;
  end;

function Scanner(const AText: string): TNumberScanner;
begin
  Result.Text := AText;
  Result.Position := 1;
end;

procedure SkipSeparators(var Scan: TNumberScanner);
begin
  while (Scan.Position <= Length(Scan.Text)) and (Scan.Text[Scan.Position] in [' ', #9, #10, #13, ',']) do
    Inc(Scan.Position);
end;

function AtEnd(var Scan: TNumberScanner): boolean;
begin
  SkipSeparators(Scan);
  Result := Scan.Position > Length(Scan.Text);
end;

function NextNumber(var Scan: TNumberScanner; out Value: double): boolean;
var
  Start: integer;
  SeenPoint: boolean;

  function Digits: boolean;
  begin
    Result := False;
    while (Scan.Position <= Length(Scan.Text)) and (Scan.Text[Scan.Position] in ['0'..'9']) do
    begin
      Inc(Scan.Position);
      Result := True;
    end;
  end;

begin
  Value := 0;
  SkipSeparators(Scan);
  Start := Scan.Position;
  if (Scan.Position <= Length(Scan.Text)) and (Scan.Text[Scan.Position] in ['+', '-']) then
    Inc(Scan.Position);
  Result := Digits;
  SeenPoint := (Scan.Position <= Length(Scan.Text)) and (Scan.Text[Scan.Position] = '.');
  if SeenPoint then
  begin
    Inc(Scan.Position);
    Result := Digits or Result;
  end;
  if not Result then
  begin
    Scan.Position := Start;
    Exit;
  end;
  if (Scan.Position < Length(Scan.Text)) and (Scan.Text[Scan.Position] in ['e', 'E']) and
    ((Scan.Text[Scan.Position + 1] in ['0'..'9']) or ((Scan.Position + 1 < Length(Scan.Text)) and
    (Scan.Text[Scan.Position + 1] in ['+', '-']) and (Scan.Text[Scan.Position + 2] in ['0'..'9']))) then
  begin
    Inc(Scan.Position, 2);
    Digits;
  end;
  Result := TextToFiniteFloat(Copy(Scan.Text, Start, Scan.Position - Start), Value);
  if not Result then
    Scan.Position := Start;
end;

// An arc's flag is one digit, which may run straight into the next number
function NextFlag(var Scan: TNumberScanner; out Flag: boolean): boolean;
begin
  SkipSeparators(Scan);
  Result := (Scan.Position <= Length(Scan.Text)) and (Scan.Text[Scan.Position] in ['0', '1']);
  Flag := Result and (Scan.Text[Scan.Position] = '1');
  if Result then
    Inc(Scan.Position);
end;

// A length as a number of pixels (user units), from its unit; False for a
// percentage or what is not a length. Absolute is set for a real unit (mm,
// cm, in, pt, pc), not pixels or none.
function UserLength(const Text: string; out Pixels: double; out Absolute: boolean): boolean;
var
  Scan: TNumberScanner;
  UnitText: string;
begin
  Pixels := 0;
  Absolute := False;
  Scan := Scanner(Trim(Text));
  if not NextNumber(Scan, Pixels) then
    Exit(False);
  UnitText := LowerCase(Trim(Copy(Scan.Text, Scan.Position, MaxInt)));
  Result := True;
  Absolute := True;
  if UnitText = 'mm' then
    Pixels := Pixels * PIXELS_PER_INCH / MM_PER_INCH
  else if UnitText = 'cm' then
    Pixels := Pixels * PIXELS_PER_INCH * 10 / MM_PER_INCH
  else if UnitText = 'in' then
    Pixels := Pixels * PIXELS_PER_INCH
  else if UnitText = 'pt' then
    Pixels := Pixels * PIXELS_PER_INCH / POINTS_PER_INCH
  else if UnitText = 'pc' then
    Pixels := Pixels * PIXELS_PER_INCH / PICAS_PER_INCH
  else
  begin
    Absolute := False;
    if (UnitText = 'em') or (UnitText = 'ex') then
      Pixels := Pixels * EM_PIXELS
    else if UnitText = '%' then
      Result := False
    else if (UnitText <> '') and (UnitText <> 'px') then
      Result := False;
  end;
end;

function LengthAttribute(Element: TDOMElement; const Name: string; Default: double = 0): double;
var
  Absolute: boolean;
begin
  if not Element.HasAttribute(Name) or not UserLength(Element.GetAttribute(Name), Result, Absolute) then
    Result := Default;
end;

{ Transforms }

// The transform list, as in transform="translate(10 5) rotate(30)"; an
// unreadable one is taken as no transform
function ParseTransform(const Text: string): TAffine;
var
  Position, Open, Close, Count: integer;
  Name: string;
  Values: array[0..5] of double;
  Scan: TNumberScanner;
  Step: TAffine;
  Turn: double;
begin
  Result := Identity;
  Position := 1;
  while Position <= Length(Text) do
  begin
    Open := Pos('(', Text, Position);
    Close := Pos(')', Text, Position);
    if (Open = 0) or (Close < Open) then
      Break;
    Name := LowerCase(Trim(StringReplace(Copy(Text, Position, Open - Position), ',', '', [rfReplaceAll])));
    Scan := Scanner(Copy(Text, Open + 1, Close - Open - 1));
    Count := 0;
    while (Count <= High(Values)) and NextNumber(Scan, Values[Count]) do
      Inc(Count);
    Step := Identity;
    if (Name = 'matrix') and (Count = 6) then
      Step := Affine(Values[0], Values[1], Values[2], Values[3], Values[4], Values[5])
    else if (Name = 'translate') and (Count >= 1) then
    begin
      if Count = 1 then
        Values[1] := 0;
      Step := Affine(1, 0, 0, 1, Values[0], Values[1]);
    end
    else if (Name = 'scale') and (Count >= 1) then
    begin
      if Count = 1 then
        Values[1] := Values[0];
      Step := Affine(Values[0], 0, 0, Values[1], 0, 0);
    end
    else if (Name = 'rotate') and (Count >= 1) then
    begin
      Turn := DegToRad(Values[0]);
      Step := Affine(Cos(Turn), Sin(Turn), -Sin(Turn), Cos(Turn), 0, 0);
      if Count >= 3 then
        Step := Combined(Affine(1, 0, 0, 1, Values[1], Values[2]), Combined(Step, Affine(1, 0, 0, 1, -Values[1], -Values[2])));
    end
    else if (Name = 'skewx') and (Count = 1) then
      Step := Affine(1, 0, Tan(DegToRad(Values[0])), 1, 0, 0)
    else if (Name = 'skewy') and (Count = 1) then
      Step := Affine(1, Tan(DegToRad(Values[0])), 0, 1, 0, 0);
    Result := Combined(Result, Step);
    Position := Close + 1;
  end;
end;

{ Contours }

procedure AddLine(var Contour: TStampContour; const Finish: TVec2);
var
  Segment: TStampSegment;
begin
  Segment := Default(TStampSegment);
  Segment.Finish := Finish;
  Insert(Segment, Contour.Segments, Length(Contour.Segments));
end;

procedure AddCubic(var Contour: TStampContour; const Control1, Control2, Finish: TVec2);
var
  Segment: TStampSegment;
begin
  Segment.Curve := True;
  Segment.Control1 := Control1;
  Segment.Control2 := Control2;
  Segment.Finish := Finish;
  Insert(Segment, Contour.Segments, Length(Contour.Segments));
end;

function NewContour(const Start: TVec2): TStampContour;
begin
  Result := Default(TStampContour);
  Result.Start := Start;
end;

// The angle of (UX, UY) to (VX, VY), signed
function VectorAngle(UX, UY, VX, VY: double): double;
begin
  Result := ArcTan2(UX * VY - UY * VX, UX * VX + UY * VY);
end;

// An elliptical arc from From to Target as SVG gives it, as cubics
procedure AddArc(var Contour: TStampContour; const From, Target: TVec2; RadiusX, RadiusY, Rotation: double; LargeArc, Sweep: boolean);
var
  CosTurn, SinTurn, HalfX, HalfY, PrimeX, PrimeY, Lambda, Factor, CentreX, CentreY, StartAngle, Delta, PieceAngle, Handle: double;
  Pieces, Piece: integer;
  Centre: TVec2;

  function OnEllipse(Angle: double): TVec2;
  begin
    Result := Centre + Vec2(RadiusX * Cos(Angle) * CosTurn - RadiusY * Sin(Angle) * SinTurn,
      RadiusX * Cos(Angle) * SinTurn + RadiusY * Sin(Angle) * CosTurn);
  end;

  function Tangent(Angle: double): TVec2;
  begin
    Result := Vec2(-RadiusX * Sin(Angle) * CosTurn - RadiusY * Cos(Angle) * SinTurn, -RadiusX * Sin(Angle) * SinTurn + RadiusY * Cos(Angle) * CosTurn);
  end;

var
  Angle, NextAngle: double;
begin
  RadiusX := Abs(RadiusX);
  RadiusY := Abs(RadiusY);
  if (RadiusX = 0) or (RadiusY = 0) or (Distance(From, Target) = 0) then
  begin
    if Distance(From, Target) > 0 then
      AddLine(Contour, Target);
    Exit;
  end;
  CosTurn := Cos(DegToRad(Rotation));
  SinTurn := Sin(DegToRad(Rotation));
  HalfX := (From.X - Target.X) / 2;
  HalfY := (From.Y - Target.Y) / 2;
  PrimeX := CosTurn * HalfX + SinTurn * HalfY;
  PrimeY := -SinTurn * HalfX + CosTurn * HalfY;
  // Radii too small to reach are scaled up until they just do
  Lambda := Sqr(PrimeX) / Sqr(RadiusX) + Sqr(PrimeY) / Sqr(RadiusY);
  if Lambda > 1 then
  begin
    RadiusX := RadiusX * Sqrt(Lambda);
    RadiusY := RadiusY * Sqrt(Lambda);
  end;
  Factor := Sqrt(Max(0, (Sqr(RadiusX) * Sqr(RadiusY) - Sqr(RadiusX) * Sqr(PrimeY) - Sqr(RadiusY) * Sqr(PrimeX)) /
    (Sqr(RadiusX) * Sqr(PrimeY) + Sqr(RadiusY) * Sqr(PrimeX))));
  if LargeArc = Sweep then
    Factor := -Factor;
  CentreX := Factor * RadiusX * PrimeY / RadiusY;
  CentreY := -Factor * RadiusY * PrimeX / RadiusX;
  Centre := Vec2(CosTurn * CentreX - SinTurn * CentreY + (From.X + Target.X) / 2,
    SinTurn * CentreX + CosTurn * CentreY + (From.Y + Target.Y) / 2);
  StartAngle := VectorAngle(1, 0, (PrimeX - CentreX) / RadiusX, (PrimeY - CentreY) / RadiusY);
  Delta := VectorAngle((PrimeX - CentreX) / RadiusX, (PrimeY - CentreY) / RadiusY, (-PrimeX - CentreX) / RadiusX,
    (-PrimeY - CentreY) / RadiusY);
  if not Sweep and (Delta > 0) then
    Delta := Delta - 2 * Pi
  else if Sweep and (Delta < 0) then
    Delta := Delta + 2 * Pi;
  Pieces := Max(1, Ceil(Abs(Delta) / ARC_PIECE - 1e-9));
  PieceAngle := Delta / Pieces;
  Handle := 4 / 3 * Tan(PieceAngle / 4);
  Angle := StartAngle;
  for Piece := 1 to Pieces do
  begin
    NextAngle := Angle + PieceAngle;
    if Piece = Pieces then
      AddCubic(Contour, OnEllipse(Angle) + Tangent(Angle) * Handle, Target - Tangent(NextAngle) * Handle, Target)
    else
      AddCubic(Contour, OnEllipse(Angle) + Tangent(Angle) * Handle, OnEllipse(NextAngle) - Tangent(NextAngle) * Handle,
        OnEllipse(NextAngle));
    Angle := NextAngle;
  end;
end;

// SVG path data, with every command, absolute and relative. False when it
// stops at something it cannot read; the contours up to there are kept.
function ParsePathData(const Text: string; out Contours: TStampContourArray): boolean;
var
  Scan: TNumberScanner;
  Command: char;
  Relative, Started, LargeArc, Sweep: boolean;
  Current, SubpathStart, LastControl, Control1, Control2, Target, Base: TVec2;
  Values: array[0..6] of double;
  LastCommand: char;

  procedure Flush;
  begin
    // A lone moveto draws nothing
    if Started and (Length(Contours[High(Contours)].Segments) = 0) then
      SetLength(Contours, Length(Contours) - 1);
    Started := False;
  end;

  procedure StartAt(const Point: TVec2);
  begin
    Flush;
    Insert(NewContour(Point), Contours, Length(Contours));
    Started := True;
    SubpathStart := Point;
  end;

  // After Z, drawing goes on from the subpath's start, in a new contour
  procedure EnsureStarted;
  begin
    if not Started then
      StartAt(Current);
  end;

  function ReadNumbers(Count: integer): boolean;
  var
    Index: integer;
  begin
    for Index := 0 to Count - 1 do
      if not NextNumber(Scan, Values[Index]) then
        Exit(False);
    Result := True;
  end;

  function ReadArc: boolean;
  begin
    Result := NextNumber(Scan, Values[0]) and NextNumber(Scan, Values[1]) and NextNumber(Scan, Values[2]) and NextFlag(Scan, LargeArc) and
      NextFlag(Scan, Sweep) and NextNumber(Scan, Values[3]) and NextNumber(Scan, Values[4]);
  end;

  function Point(Index: integer): TVec2;
  begin
    Result := Base + Vec2(Values[Index], Values[Index + 1]);
  end;

  // One set of a command's numbers; False when they are not there
  function DrawOnce: boolean;
  begin
    if Relative then
      Base := Current
    else
      Base := Vec2(0, 0);
    Result := True;
    case UpCase(Command) of
      'M':
      begin
        if not ReadNumbers(2) then
          Exit(False);
        Current := Point(0);
        StartAt(Current);
        // Pairs after a moveto are linetos
        if Relative then
          Command := 'l'
        else
          Command := 'L';
      end;
      'L':
      begin
        if not ReadNumbers(2) then
          Exit(False);
        EnsureStarted;
        Current := Point(0);
        AddLine(Contours[High(Contours)], Current);
      end;
      'H':
      begin
        if not ReadNumbers(1) then
          Exit(False);
        EnsureStarted;
        Current := Vec2(Base.X + Values[0], Current.Y);
        AddLine(Contours[High(Contours)], Current);
      end;
      'V':
      begin
        if not ReadNumbers(1) then
          Exit(False);
        EnsureStarted;
        Current := Vec2(Current.X, Base.Y + Values[0]);
        AddLine(Contours[High(Contours)], Current);
      end;
      'C', 'S':
      begin
        if UpCase(Command) = 'C' then
        begin
          if not ReadNumbers(6) then
            Exit(False);
          Control1 := Point(0);
          Control2 := Point(2);
          Target := Point(4);
        end
        else
        begin
          if not ReadNumbers(4) then
            Exit(False);
          if UpCase(LastCommand) in ['C', 'S'] then
            Control1 := Current * 2 - LastControl
          else
            Control1 := Current;
          Control2 := Point(0);
          Target := Point(2);
        end;
        EnsureStarted;
        AddCubic(Contours[High(Contours)], Control1, Control2, Target);
        LastControl := Control2;
        Current := Target;
      end;
      'Q', 'T':
      begin
        if UpCase(Command) = 'Q' then
        begin
          if not ReadNumbers(4) then
            Exit(False);
          Control1 := Point(0);
          Target := Point(2);
        end
        else
        begin
          if not ReadNumbers(2) then
            Exit(False);
          if UpCase(LastCommand) in ['Q', 'T'] then
            Control1 := Current * 2 - LastControl
          else
            Control1 := Current;
          Target := Point(0);
        end;
        EnsureStarted;
        // A quadratic is the cubic with its controls two thirds of the way
        AddCubic(Contours[High(Contours)], Lerp(Current, Control1, 2 / 3), Lerp(Target, Control1, 2 / 3), Target);
        LastControl := Control1;
        Current := Target;
      end;
      'A':
      begin
        if not ReadArc then
          Exit(False);
        EnsureStarted;
        Target := Point(3);
        AddArc(Contours[High(Contours)], Current, Target, Values[0], Values[1], Values[2], LargeArc, Sweep);
        Current := Target;
      end;
    end;
    LastCommand := Command;
  end;

begin
  Contours := nil;
  Scan := Scanner(Text);
  Started := False;
  Current := Vec2(0, 0);
  SubpathStart := Current;
  LastControl := Current;
  LastCommand := ' ';
  Result := True;
  while not AtEnd(Scan) do
  begin
    Command := Scan.Text[Scan.Position];
    if not (UpCase(Command) in ['M', 'L', 'H', 'V', 'C', 'S', 'Q', 'T', 'A', 'Z']) then
    begin
      Result := False;
      Break;
    end;
    Inc(Scan.Position);
    if (Length(Contours) = 0) and (UpCase(Command) <> 'M') then
    begin
      Result := False;
      Break;
    end;
    Relative := Command in ['a'..'z'];
    if UpCase(Command) = 'Z' then
    begin
      if Started then
        Contours[High(Contours)].Closed := True;
      Flush;
      Current := SubpathStart;
      LastCommand := Command;
      Continue;
    end;
    // A command's numbers may repeat, drawing it again each time
    if not DrawOnce then
    begin
      Result := False;
      Break;
    end;
    while not AtEnd(Scan) and (Scan.Text[Scan.Position] in ['0'..'9', '-', '+', '.']) do
      if not DrawOnce then
      begin
        Result := False;
        Break;
      end;
    if not Result then
      Break;
  end;
  Flush;
end;

function RectContours(X, Y, Width, Height, RadiusX, RadiusY: double): TStampContourArray;
const
  // How far a quarter circle's handles reach, of the radius
  KAPPA = 0.5522847498;
var
  Contour: TStampContour;
  HandleX, HandleY: double;
begin
  Result := nil;
  if (Width <= 0) or (Height <= 0) then
    Exit;
  RadiusX := Min(RadiusX, Width / 2);
  RadiusY := Min(RadiusY, Height / 2);
  HandleX := RadiusX * (1 - KAPPA);
  HandleY := RadiusY * (1 - KAPPA);
  Contour := NewContour(Vec2(X + RadiusX, Y));
  AddLine(Contour, Vec2(X + Width - RadiusX, Y));
  if RadiusX > 0 then
    AddCubic(Contour, Vec2(X + Width - HandleX, Y), Vec2(X + Width, Y + HandleY), Vec2(X + Width, Y + RadiusY));
  AddLine(Contour, Vec2(X + Width, Y + Height - RadiusY));
  if RadiusX > 0 then
    AddCubic(Contour, Vec2(X + Width, Y + Height - HandleY), Vec2(X + Width - HandleX, Y + Height), Vec2(X + Width - RadiusX, Y + Height));
  AddLine(Contour, Vec2(X + RadiusX, Y + Height));
  if RadiusX > 0 then
    AddCubic(Contour, Vec2(X + HandleX, Y + Height), Vec2(X, Y + Height - HandleY), Vec2(X, Y + Height - RadiusY));
  AddLine(Contour, Vec2(X, Y + RadiusY));
  if RadiusX > 0 then
    AddCubic(Contour, Vec2(X, Y + HandleY), Vec2(X + HandleX, Y), Vec2(X + RadiusX, Y));
  Contour.Closed := True;
  Result := [Contour];
end;

function EllipseContours(CentreX, CentreY, RadiusX, RadiusY: double): TStampContourArray;
var
  Contour: TStampContour;
  Centre: TVec2;
begin
  Result := nil;
  if (RadiusX <= 0) or (RadiusY <= 0) then
    Exit;
  Centre := Vec2(CentreX, CentreY);
  Contour := NewContour(Centre + Vec2(RadiusX, 0));
  AddArc(Contour, Centre + Vec2(RadiusX, 0), Centre + Vec2(-RadiusX, 0), RadiusX, RadiusY, 0, False, True);
  AddArc(Contour, Centre + Vec2(-RadiusX, 0), Centre + Vec2(RadiusX, 0), RadiusX, RadiusY, 0, False, True);
  Contour.Closed := True;
  Result := [Contour];
end;

function PointsContours(const Text: string; Closed: boolean): TStampContourArray;
var
  Scan: TNumberScanner;
  First, Second: double;
  Contour: TStampContour;
  Started: boolean;
begin
  Result := nil;
  Scan := Scanner(Text);
  Started := False;
  Contour := Default(TStampContour);
  while NextNumber(Scan, First) and NextNumber(Scan, Second) do
    if Started then
      AddLine(Contour, Vec2(First, Second))
    else
    begin
      Contour := NewContour(Vec2(First, Second));
      Started := True;
    end;
  if Started and (Length(Contour.Segments) > 0) then
  begin
    Contour.Closed := Closed;
    Result := [Contour];
  end;
end;

{ TSvgReader }

procedure TSvgReader.Warn(Warning: TWarning);
begin
  Include(FWarned, Warning);
end;

function TSvgReader.Refuse(const Reason: string): boolean;
begin
  if FError = '' then
    FError := Reason;
  Result := False;
end;

function TSvgReader.ReadColour(const Text: string; const Style: TSvgStyle; out Colour: integer): boolean;
var
  Kept, Inside: string;
  Scan: TNumberScanner;
  Parts: array[0..2] of double;
  Index: integer;
  InPercent: boolean;
begin
  Kept := LowerCase(Trim(Text));
  Colour := BLACK;
  Result := True;
  if (Kept = 'none') or (Kept = 'transparent') then
    Colour := STAMP_NO_COLOUR
  else if Kept = 'currentcolor' then
    Colour := Style.Color
  else if Kept.StartsWith('url(') then
    Warn(wnGradient)
  else if Kept.StartsWith('#') and (Length(Kept) = 7) and ParseStampColour(Kept, Colour) then
  else if Kept.StartsWith('#') and (Length(Kept) = 4) and ParseStampColour('#' + Kept[2] + Kept[2] + Kept[3] + Kept[3] + Kept[4] + Kept[4],
    Colour) then
  else if Kept.StartsWith('rgb(') and Kept.EndsWith(')') then
  begin
    Inside := Copy(Kept, 5, Length(Kept) - 5);
    InPercent := Pos('%', Inside) > 0;
    Scan := Scanner(StringReplace(Inside, '%', ' ', [rfReplaceAll]));
    for Index := 0 to High(Parts) do
      if not NextNumber(Scan, Parts[Index]) then
      begin
        Warn(wnColour);
        Exit;
      end;
    for Index := 0 to High(Parts) do
    begin
      if InPercent then
        Parts[Index] := Parts[Index] * COLOUR_CHANNEL / PERCENT;
      Parts[Index] := EnsureRange(Round(Parts[Index]), 0, COLOUR_CHANNEL);
    end;
    Colour := (Round(Parts[0]) shl 16) or (Round(Parts[1]) shl 8) or Round(Parts[2]);
  end
  else if IsIn(Kept, COLOUR_NAMES) then
  begin
    for Index := 0 to High(COLOUR_NAMES) do
      if COLOUR_NAMES[Index] = Kept then
        Colour := COLOUR_VALUES[Index];
  end
  else if Kept = 'inherit' then
    Result := False
  else
    Warn(wnColour);
end;

procedure TSvgReader.ApplyProperty(const Name, Value: string; var Style: TSvgStyle);
var
  Colour: integer;
  Width: double;
  Absolute: boolean;
  Kept: string;
begin
  Kept := Trim(Value);
  if Kept = '' then
    Exit;
  if (Name = 'fill') and ReadColour(Kept, Style, Colour) then
    Style.Fill := Colour
  else if (Name = 'stroke') and ReadColour(Kept, Style, Colour) then
    Style.Stroke := Colour
  else if (Name = 'color') and ReadColour(Kept, Style, Colour) and (Colour <> STAMP_NO_COLOUR) then
    Style.Color := Colour
  else if (Name = 'stroke-width') and UserLength(Kept, Width, Absolute) then
    Style.StrokeWidth := Max(0, Width)
  else if Name = 'fill-rule' then
    Style.EvenOdd := Kept = 'evenodd'
  else if Name = 'visibility' then
    Style.Hidden := (Kept = 'hidden') or (Kept = 'collapse')
  else if (Name = 'opacity') or (Name = 'fill-opacity') or (Name = 'stroke-opacity') then
  begin
    if TextToFiniteFloat(Kept, Width) and (Width < 1) then
      Warn(wnOpacity);
  end
  else if ((Name = 'clip-path') or (Name = 'mask')) and (Kept <> 'none') then
    Warn(wnClip);
end;

// Presentation attributes first, then the style attribute, which wins
procedure TSvgReader.ReadStyle(Element: TDOMElement; var Style: TSvgStyle);
var
  Name, Declaration: string;
  Colon: integer;
begin
  for Name in STYLE_PROPERTY_NAMES do
    if Element.HasAttribute(Name) then
      ApplyProperty(Name, Element.GetAttribute(Name), Style);
  for Declaration in string(Element.GetAttribute('style')).Split([';']) do
  begin
    Colon := Pos(':', Declaration);
    if Colon > 0 then
      ApplyProperty(LowerCase(Trim(Copy(Declaration, 1, Colon - 1))), StringReplace(Copy(Declaration, Colon + 1, MaxInt), '!important', '',
        [rfReplaceAll, rfIgnoreCase]), Style);
  end;
end;

function IsHiddenElement(Element: TDOMElement): boolean;
begin
  Result := (Trim(Element.GetAttribute('display')) = 'none') or (Pos('display:none', StringReplace(Element.GetAttribute('style'), ' ', '',
    [rfReplaceAll])) > 0);
end;

function TSvgReader.ShapeContours(Element: TDOMElement; const Name: string; out Contours: TStampContourArray): boolean;
var
  RadiusX, RadiusY: double;
begin
  Contours := nil;
  Result := True;
  if Name = 'path' then
  begin
    if not ParsePathData(Element.GetAttribute('d'), Contours) then
      Warn(wnBadPath);
  end
  else if Name = 'rect' then
  begin
    RadiusX := LengthAttribute(Element, 'rx', -1);
    RadiusY := LengthAttribute(Element, 'ry', -1);
    // Either radius stands for both when only one is given
    if RadiusX < 0 then
      RadiusX := Max(0, RadiusY);
    if RadiusY < 0 then
      RadiusY := RadiusX;
    Contours := RectContours(LengthAttribute(Element, 'x'), LengthAttribute(Element, 'y'), LengthAttribute(Element, 'width'),
      LengthAttribute(Element, 'height'), RadiusX, RadiusY);
  end
  else if Name = 'circle' then
    Contours := EllipseContours(LengthAttribute(Element, 'cx'), LengthAttribute(Element, 'cy'), LengthAttribute(Element, 'r'),
      LengthAttribute(Element, 'r'))
  else if Name = 'ellipse' then
    Contours := EllipseContours(LengthAttribute(Element, 'cx'), LengthAttribute(Element, 'cy'), LengthAttribute(Element, 'rx'),
      LengthAttribute(Element, 'ry'))
  else if Name = 'line' then
    Contours := PointsContours(Format('%s,%s %s,%s', [Element.GetAttribute('x1'), Element.GetAttribute('y1'), Element.GetAttribute('x2'),
      Element.GetAttribute('y2')]), False)
  else if Name = 'polyline' then
    Contours := PointsContours(Element.GetAttribute('points'), False)
  else if Name = 'polygon' then
    Contours := PointsContours(Element.GetAttribute('points'), True)
  else
    Result := False;
end;

procedure TSvgReader.AddShape(Contours: TStampContourArray; const Matrix: TAffine; const Style: TSvgStyle);
var
  Path: TStampPath;
  ContourIndex: integer;
begin
  if Style.Hidden or (Length(Contours) = 0) or ((Style.Fill = STAMP_NO_COLOUR) and ((Style.Stroke = STAMP_NO_COLOUR) or
    (Style.StrokeWidth <= 0))) then
    Exit;
  for ContourIndex := 0 to High(Contours) do
  begin
    Inc(FSegments, Length(Contours[ContourIndex].Segments) + 1);
    MoveContour(Contours[ContourIndex], Matrix);
  end;
  Path := Default(TStampPath);
  Path.Fill := Style.Fill;
  Path.Stroke := STAMP_NO_COLOUR;
  if Style.StrokeWidth > 0 then
    Path.Stroke := Style.Stroke;
  // A stroke grows as the shape does, by the transform's average scale
  Path.StrokeWidth := Style.StrokeWidth * Sqrt(Abs(Matrix.A * Matrix.D - Matrix.B * Matrix.C));
  Path.EvenOdd := Style.EvenOdd;
  Path.Contours := Contours;
  Insert(Path, FPaths, Length(FPaths));
end;

function TSvgReader.ReadChildren(Element: TDOMElement; const Matrix: TAffine; const Style: TSvgStyle; Depth: integer): boolean;
var
  Child: TDOMNode;
begin
  Child := Element.FirstChild;
  while Assigned(Child) do
  begin
    if (Child is TDOMElement) and not ReadElement(TDOMElement(Child), Matrix, Style, Depth + 1) then
      Exit(False);
    Child := Child.NextSibling;
  end;
  Result := True;
end;

function TSvgReader.ReadElement(Element: TDOMElement; const Matrix: TAffine; const Style: TSvgStyle; Depth: integer): boolean;
var
  Name: string;
  Own: TSvgStyle;
  Placed: TAffine;
  Contours: TStampContourArray;
begin
  Result := True;
  // Inkscape's and other apps' own elements carry nothing drawn
  if (Element.NamespaceURI <> '') and (Element.NamespaceURI <> SVG_NAMESPACE) then
    Exit;
  if Depth > MAX_DEPTH then
    Exit(Refuse(rsSvgTooDeep));
  Name := Element.LocalName;
  if IsIn(Name, TEXT_NAMES) then
    Exit(Refuse(rsSvgText));
  if IsIn(Name, IMAGE_NAMES) then
    Exit(Refuse(rsSvgImage));
  if Name = 'use' then
    Exit(Refuse(rsSvgUse));
  if Name = 'style' then
    Warn(wnStyleSheet);
  if IsIn(Name, SKIPPED_NAMES) or (Name = 'style') or IsHiddenElement(Element) then
    Exit;
  Own := Style;
  ReadStyle(Element, Own);
  Placed := Combined(Matrix, ParseTransform(Element.GetAttribute('transform')));
  if IsIn(Name, CONTAINER_NAMES) then
  begin
    // A drawing inside the drawing sits at its x and y
    if Name = 'svg' then
      Placed := Combined(Placed, Affine(1, 0, 0, 1, LengthAttribute(Element, 'x'), LengthAttribute(Element, 'y')));
    Exit(ReadChildren(Element, Placed, Own, Depth));
  end;
  // A line has no inside to fill
  if Name = 'line' then
    Own.Fill := STAMP_NO_COLOUR;
  if ShapeContours(Element, Name, Contours) then
    AddShape(Contours, Placed, Own);
end;

// The root's size and viewBox say how big a user unit is
function RootMatrix(Root: TDOMElement; out InPixels: boolean): TAffine;
var
  Scan: TNumberScanner;
  Box: array[0..3] of double;
  Width, Height, ScaleX, ScaleY, Scale: double;
  HasWidth, HasHeight, WidthAbsolute, HeightAbsolute, HasBox: boolean;
  Index: integer;
begin
  HasWidth := Root.HasAttribute('width') and UserLength(Root.GetAttribute('width'), Width, WidthAbsolute) and (Width > 0);
  HasHeight := Root.HasAttribute('height') and UserLength(Root.GetAttribute('height'), Height, HeightAbsolute) and (Height > 0);
  Scan := Scanner(Root.GetAttribute('viewBox'));
  HasBox := True;
  for Index := 0 to High(Box) do
    HasBox := HasBox and NextNumber(Scan, Box[Index]);
  HasBox := HasBox and (Box[2] > 0) and (Box[3] > 0);
  Scale := MM_PER_INCH / PIXELS_PER_INCH;
  InPixels := True;
  if not HasBox then
    Exit(Affine(Scale, 0, 0, Scale, 0, 0));
  ScaleX := 0;
  ScaleY := 0;
  if HasWidth then
    ScaleX := Width * MM_PER_INCH / PIXELS_PER_INCH / Box[2];
  if HasHeight then
    ScaleY := Height * MM_PER_INCH / PIXELS_PER_INCH / Box[3];
  // The viewBox is fitted in whole, keeping its shape
  if HasWidth and HasHeight then
    Scale := Min(ScaleX, ScaleY)
  else if HasWidth then
    Scale := ScaleX
  else if HasHeight then
    Scale := ScaleY
  else
    Scale := MM_PER_INCH / PIXELS_PER_INCH;
  InPixels := not ((HasWidth and WidthAbsolute) or (HasHeight and HeightAbsolute));
  Result := Affine(Scale, 0, 0, Scale, -Box[0] * Scale, -Box[1] * Scale);
end;

procedure IncludePoint(var Bounds: TRect2; const Point: TVec2; Grow: double);
begin
  Bounds.MinX := Min(Bounds.MinX, Point.X - Grow);
  Bounds.MinY := Min(Bounds.MinY, Point.Y - Grow);
  Bounds.MaxX := Max(Bounds.MaxX, Point.X + Grow);
  Bounds.MaxY := Max(Bounds.MaxY, Point.Y + Grow);
end;

// What the paths cover, strokes included, then moved so it starts at (0, 0)
procedure PlaceAtOrigin(var Drawing: TStampDrawing);
var
  Bounds: TRect2;
  PathIndex, ContourIndex: integer;
  Grow: double;
  Point, Shift: TVec2;
begin
  Bounds.MinX := Infinity;
  Bounds.MinY := Infinity;
  Bounds.MaxX := NegInfinity;
  Bounds.MaxY := NegInfinity;
  for PathIndex := 0 to High(Drawing.Paths) do
  begin
    Grow := 0;
    if Drawing.Paths[PathIndex].Stroke <> STAMP_NO_COLOUR then
      Grow := Drawing.Paths[PathIndex].StrokeWidth / 2;
    for ContourIndex := 0 to High(Drawing.Paths[PathIndex].Contours) do
      for Point in FlattenStampContour(Drawing.Paths[PathIndex].Contours[ContourIndex], Vec2(0, 0), 1, BOUNDS_TOLERANCE) do
        IncludePoint(Bounds, Point, Grow);
  end;
  for PathIndex := 0 to High(Drawing.Paths) do
    for ContourIndex := 0 to High(Drawing.Paths[PathIndex].Contours) do
      MoveContour(Drawing.Paths[PathIndex].Contours[ContourIndex], Affine(1, 0, 0, 1, -Bounds.MinX, -Bounds.MinY));
  Drawing.Width := Bounds.MaxX - Bounds.MinX;
  Drawing.Height := Bounds.MaxY - Bounds.MinY;
end;

function TSvgReader.Read(Root: TDOMElement; out Drawing: TStampDrawing; out Warnings: TStringArray; out ErrorMessage: string): boolean;
var
  Style: TSvgStyle;
  InPixels: boolean;
  Warning: TWarning;
  Text: string;
begin
  Drawing := Default(TStampDrawing);
  Warnings := nil;
  ErrorMessage := '';
  if not Assigned(Root) or (Root.LocalName <> 'svg') then
  begin
    ErrorMessage := rsSvgNotSvg;
    Exit(False);
  end;
  // As SVG starts: filled black, no stroke, a stroke 1 wide when there is one
  Style := Default(TSvgStyle);
  Style.Fill := BLACK;
  Style.Stroke := STAMP_NO_COLOUR;
  Style.Color := BLACK;
  Style.StrokeWidth := 1;
  ReadStyle(Root, Style);
  if not ReadChildren(Root, RootMatrix(Root, InPixels), Style, 0) then
  begin
    ErrorMessage := FError;
    Exit(False);
  end;
  if InPixels then
    Warn(wnPixels);
  if Length(FPaths) = 0 then
  begin
    ErrorMessage := rsSvgEmpty;
    Exit(False);
  end;
  if FSegments > MAX_STAMP_SEGMENTS then
  begin
    ErrorMessage := Format(rsStampTooDetailed, [MAX_STAMP_SEGMENTS]);
    Exit(False);
  end;
  Drawing.Paths := FPaths;
  PlaceAtOrigin(Drawing);
  for Warning in FWarned do
  begin
    case Warning of
      wnPixels: Text := rsSvgPixels;
      wnGradient: Text := rsSvgGradient;
      wnStyleSheet: Text := rsSvgStyleSheet;
      wnClip: Text := rsSvgClip;
      wnOpacity: Text := rsSvgOpacity;
      wnColour: Text := rsSvgColour;
      else
        Text := rsSvgBadPath;
    end;
    Insert(Text, Warnings, Length(Warnings));
  end;
  Result := True;
end;

// Ignore a plain SVG document type without handing its external ID to XMLRead.
// Only inspect the prolog. A declaration with an internal subset, or one that
// cannot be read, is refused with a message saying how to fix the file;
// anything else is left for the parser, which still has DOCTYPE processing
// disabled.
function StripSvgDoctype(const SvgText: string; out Text, ErrorMessage: string): boolean;
const
  XML_SPACE = [#9, #10, #13, ' '];
  UTF8_BOM = #$EF#$BB#$BF;
  DOCTYPE_START = '<!DOCTYPE';
var
  Cursor, Start, NameStart, EndMarker: SizeInt;

  function Take(const Token: string): boolean;
  begin
    Result := Copy(SvgText, Cursor, Length(Token)) = Token;
    if Result then
      Inc(Cursor, Length(Token));
  end;

  function SkipSpace: boolean;
  var
    Before: SizeInt;
  begin
    Before := Cursor;
    while (Cursor <= Length(SvgText)) and (SvgText[Cursor] in XML_SPACE) do
      Inc(Cursor);
    Result := Cursor > Before;
  end;

  function TakeLiteral: boolean;
  var
    Quote: char;
  begin
    Result := False;
    if (Cursor > Length(SvgText)) or not (SvgText[Cursor] in ['"', '''']) then
      Exit;
    Quote := SvgText[Cursor];
    Inc(Cursor);
    EndMarker := PosEx(Quote, SvgText, Cursor);
    if EndMarker = 0 then
      Exit;
    Cursor := EndMarker + 1;
    Result := True;
  end;

  function Unreadable: boolean;
  begin
    ErrorMessage := rsSvgDoctypeUnread;
    Result := False;
  end;

begin
  Result := True;
  Text := SvgText;
  ErrorMessage := '';
  Cursor := 1;
  Take(UTF8_BOM);
  repeat
    SkipSpace;
    if Take('<!--') then
    begin
      EndMarker := PosEx('-->', SvgText, Cursor);
      if EndMarker = 0 then
        Exit;
      Cursor := EndMarker + 3;
    end
    else if Take('<?') then
    begin
      EndMarker := PosEx('?>', SvgText, Cursor);
      if EndMarker = 0 then
        Exit;
      Cursor := EndMarker + 2;
    end
    else
      Break;
  until False;
  Start := Cursor;
  // In any case, as HTML writes it; XML only allows capitals
  if not SameText(Copy(SvgText, Cursor, Length(DOCTYPE_START)), DOCTYPE_START) then
    Exit;
  if not Take(DOCTYPE_START) or not SkipSpace then
    Exit(Unreadable);
  NameStart := Cursor;
  while (Cursor <= Length(SvgText)) and not (SvgText[Cursor] in XML_SPACE + ['[', '>']) do
    Inc(Cursor);
  if not IsXmlName(UTF8Decode(Copy(SvgText, NameStart, Cursor - NameStart))) then
    Exit(Unreadable);
  if SkipSpace then
  begin
    if Take('SYSTEM') then
    begin
      if not SkipSpace or not TakeLiteral then
        Exit(Unreadable);
    end
    else if Take('PUBLIC') then
    begin
      if not SkipSpace or not TakeLiteral or not SkipSpace or not TakeLiteral then
        Exit(Unreadable);
    end;
    SkipSpace;
  end;
  if Take('[') then
  begin
    ErrorMessage := rsSvgDoctypeSubset;
    Exit(False);
  end;
  if not Take('>') then
    Exit(Unreadable);
  Delete(Text, Start, Cursor - Start);
end;

function ImportSvgStamp(const SvgText: string; out Drawing: TStampDrawing; out Warnings: TStringArray; out ErrorMessage: string): boolean;
var
  Parser: TDOMParser;
  Source: TXMLInputSource;
  Stream: TStringStream;
  Document: TXMLDocument;
  Reader: TSvgReader;
  SavedMask: TFPUExceptionMask;
  Text: string;
begin
  Result := False;
  Drawing := Default(TStampDrawing);
  Warnings := nil;
  ErrorMessage := '';
  if Length(SvgText) > MAX_SVG_BYTES then
  begin
    ErrorMessage := Format(rsSvgTooLarge, [MAX_SVG_BYTES div BYTES_PER_MB]);
    Exit;
  end;
  if not StripSvgDoctype(SvgText, Text, ErrorMessage) then
    Exit;
  Parser := nil;
  Source := nil;
  Stream := nil;
  Document := nil;
  Reader := nil;
  SavedMask := GetExceptionMask;
  SetExceptionMask(SavedMask + [exInvalidOp, exDenormalized, exZeroDivide, exOverflow, exUnderflow, exPrecision]);
  try
    try
      Parser := TDOMParser.Create;
      Parser.Options.Namespaces := True;
      // A stamp needs shapes only. Keep DTD processing out of the importer.
      Parser.Options.DisallowDoctype := True;
      Stream := TStringStream.Create(Text);
      Source := TXMLInputSource.Create(Stream);
      Parser.Parse(Source, Document);
      Reader := TSvgReader.Create;
      Result := Reader.Read(Document.DocumentElement, Drawing, Warnings, ErrorMessage);
    except
      on Failure: EXMLReadError do
        ErrorMessage := Format(rsSvgNotXml, [Failure.Message]);
      on Failure: EDOMError do
        ErrorMessage := Format(rsSvgNotXml, [Failure.Message]);
      on Failure: Exception do
        ErrorMessage := Format(rsSvgNotXml, [Failure.Message]);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(SavedMask);
    FreeAndNil(Reader);
    FreeAndNil(Document);
    FreeAndNil(Source);
    FreeAndNil(Stream);
    FreeAndNil(Parser);
  end;
  if not Result then
    Drawing := Default(TStampDrawing);
end;

function ImportSvgStampFile(const FileName: string; out Drawing: TStampDrawing; out Warnings: TStringArray;
  out ErrorMessage: string): boolean;
var
  Text: string;
begin
  Drawing := Default(TStampDrawing);
  Warnings := nil;
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Result := ImportSvgStamp(Text, Drawing, Warnings, ErrorMessage);
end;

end.
