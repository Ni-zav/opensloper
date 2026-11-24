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

// A stamp's drawing: paths from an SVG drawing (Sloper.Core.SvgImport), kept
// in the pattern so it does not depend on the file it came from. Every place
// is in mm at true size, from the drawing's top left, so (0, 0) to (Width,
// Height) holds it all, strokes included. Each path is its contours, made of
// lines and cubic curves, with a fill and a stroke colour. Saved as path data
// with only M, L, C and Z, absolute. A drawing is a value: nothing changes it
// once made. See Annotations in the design document. No LCL dependency.
unit Sloper.Core.Stamp;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.Core.Geometry;

const
  // A fill or stroke that is not drawn
  STAMP_NO_COLOUR = -1;
  // The most segments a drawing may have, so a pattern file stays a size
  // that loads and draws quickly
  MAX_STAMP_SEGMENTS = 50000;
  // How far a stamp can be scaled either way
  MIN_STAMP_SCALE = 0.01;
  MAX_STAMP_SCALE = 100;

type
  // A line to Finish, or a cubic curve through Control1 and Control2
  TStampSegment = record
    Curve: boolean;
    Control1, Control2, Finish: TVec2;
  end;

  TStampContour = record
    Start: TVec2;
    Segments: array of TStampSegment;
    Closed: boolean;
  end;

  TStampContourArray = array of TStampContour;

  TStampPath = record
    // $RRGGBB, or STAMP_NO_COLOUR
    Fill, Stroke: integer;
    // In mm
    StrokeWidth: double;
    // Filled by the even-odd rule, not the nonzero one
    EvenOdd: boolean;
    Contours: TStampContourArray;
  end;

  TStampPathArray = array of TStampPath;

  TStampDrawing = record
    // In mm at true size
    Width, Height: double;
    Paths: TStampPathArray;
  end;

// A drawing with paths in it; a note without one is text
function HasDrawing(const Drawing: TStampDrawing): boolean;
function StampSegmentCount(const Drawing: TStampDrawing): integer;
// The path's contours as path data, each place At + place * Scale, in mm
// with at most three decimals
function StampPathData(const Path: TStampPath; const At: TVec2; Scale: double): string;
// Reads path data as StampPathData writes it: M, L, C and Z, absolute
function ParseStampPathData(const Text: string; out Contours: TStampContourArray; out ErrorMessage: string): boolean;
// #rrggbb, or 'none'
function StampColourText(Colour: integer): string;
function ParseStampColour(const Text: string; out Colour: integer): boolean;
// The contour as a polygon or polyline, each curve cut into straight pieces
// no more than Tolerance off it, each place At + place * Scale
function FlattenStampContour(const Contour: TStampContour; const At: TVec2; Scale, Tolerance: double): TVec2Array;
// The red, green and blue of a colour from 0 to 1, for PDF
procedure StampColourParts(Colour: integer; out Red, Green, Blue: double);

// As kept in a pattern file
function StampToJSON(const Drawing: TStampDrawing): TJSONObject;
function StampFromJSON(Data: TJSONData; out Drawing: TStampDrawing; out ErrorMessage: string): boolean;

resourcestring
  rsStampBadData = 'A stamp''s path data cannot be read at "%s"';
  rsStampBadDrawing = 'A stamp''s drawing is not as written by OpenSloper: %s';
  rsStampTooDetailed = 'The drawing is too detailed: a stamp can have at most %d segments';

implementation

uses
  Math, Sloper.Core.JSON;

const
  // Places in path data are kept to a thousandth of a mm
  PATH_DECIMALS = 1000;
  // A curve is never cut into more pieces than this
  MAX_FLATTEN_PIECES = 64;
  COLOUR_CHANNEL = 255;
  HEX_DIGITS = 6;
  NONE_TEXT = 'none';

function HasDrawing(const Drawing: TStampDrawing): boolean;
begin
  Result := Length(Drawing.Paths) > 0;
end;

function StampSegmentCount(const Drawing: TStampDrawing): integer;
var
  Path: TStampPath;
  Contour: TStampContour;
begin
  Result := 0;
  for Path in Drawing.Paths do
    for Contour in Path.Contours do
      Inc(Result, Length(Contour.Segments) + 1);
end;

function PlaceText(Value: double): string;
var
  Rounded: double;
begin
  Rounded := Round(Value * PATH_DECIMALS) / PATH_DECIMALS;
  if Rounded = 0 then
    Rounded := 0;
  Result := FormatJSONFloat(Rounded);
end;

function PointText(const Point, At: TVec2; Scale: double): string;
begin
  Result := PlaceText(At.X + Point.X * Scale) + ' ' + PlaceText(At.Y + Point.Y * Scale);
end;

function StampPathData(const Path: TStampPath; const At: TVec2; Scale: double): string;
var
  Contour: TStampContour;
  Segment: TStampSegment;
  Parts: TStringArray;
begin
  Parts := nil;
  for Contour in Path.Contours do
  begin
    Insert('M ' + PointText(Contour.Start, At, Scale), Parts, Length(Parts));
    for Segment in Contour.Segments do
      if Segment.Curve then
        Insert('C ' + PointText(Segment.Control1, At, Scale) + ' ' + PointText(Segment.Control2, At, Scale) + ' ' +
          PointText(Segment.Finish, At, Scale), Parts, Length(Parts))
      else
        Insert('L ' + PointText(Segment.Finish, At, Scale), Parts, Length(Parts));
    if Contour.Closed then
      Insert('Z', Parts, Length(Parts));
  end;
  Result := string.Join(' ', Parts);
end;

function ParseStampPathData(const Text: string; out Contours: TStampContourArray; out ErrorMessage: string): boolean;
var
  Words: TStringArray;
  Index: integer;
  Command: string;
  Current: ^TStampContour;
  Segment: TStampSegment;

  function Fail: boolean;
  begin
    ErrorMessage := Format(rsStampBadData, [Command]);
    Contours := nil;
    Result := False;
  end;

  function ReadPoint(out Point: TVec2): boolean;
  var
    First, Second: double;
  begin
    Result := (Index + 1 <= High(Words)) and TextToFiniteFloat(Words[Index], First) and TextToFiniteFloat(Words[Index + 1], Second);
    if Result then
    begin
      Point := Vec2(First, Second);
      Inc(Index, 2);
    end;
  end;

begin
  Contours := nil;
  ErrorMessage := '';
  Current := nil;
  Words := Text.Split([' ', #9, #10, #13], TStringSplitOptions.ExcludeEmpty);
  Index := 0;
  while Index <= High(Words) do
  begin
    Command := Words[Index];
    Inc(Index);
    Segment := Default(TStampSegment);
    if Command = 'M' then
    begin
      SetLength(Contours, Length(Contours) + 1);
      Current := @Contours[High(Contours)];
      if not ReadPoint(Current^.Start) then
        Exit(Fail);
    end
    else if not Assigned(Current) or Current^.Closed then
      Exit(Fail)
    else if Command = 'L' then
    begin
      if not ReadPoint(Segment.Finish) then
        Exit(Fail);
      Insert(Segment, Current^.Segments, Length(Current^.Segments));
    end
    else if Command = 'C' then
    begin
      Segment.Curve := True;
      if not ReadPoint(Segment.Control1) or not ReadPoint(Segment.Control2) or not ReadPoint(Segment.Finish) then
        Exit(Fail);
      Insert(Segment, Current^.Segments, Length(Current^.Segments));
    end
    else if Command = 'Z' then
      Current^.Closed := True
    else
      Exit(Fail);
  end;
  Result := True;
end;

function StampColourText(Colour: integer): string;
begin
  if Colour = STAMP_NO_COLOUR then
    Result := NONE_TEXT
  else
    Result := '#' + LowerCase(IntToHex(Colour, HEX_DIGITS));
end;

function ParseStampColour(const Text: string; out Colour: integer): boolean;
var
  Letter: char;
begin
  Colour := STAMP_NO_COLOUR;
  if Text = NONE_TEXT then
    Exit(True);
  if (Length(Text) <> HEX_DIGITS + 1) or (Text[1] <> '#') then
    Exit(False);
  for Letter in Copy(Text, 2, HEX_DIGITS) do
    if not (Letter in ['0'..'9', 'a'..'f', 'A'..'F']) then
      Exit(False);
  Colour := StrToInt('$' + Copy(Text, 2, HEX_DIGITS));
  Result := True;
end;

procedure StampColourParts(Colour: integer; out Red, Green, Blue: double);
begin
  Red := ((Colour shr 16) and COLOUR_CHANNEL) / COLOUR_CHANNEL;
  Green := ((Colour shr 8) and COLOUR_CHANNEL) / COLOUR_CHANNEL;
  Blue := (Colour and COLOUR_CHANNEL) / COLOUR_CHANNEL;
end;

function CubicAt(const P0, P1, P2, P3: TVec2; Along: double): TVec2;
var
  Rest: double;
begin
  Rest := 1 - Along;
  Result := P0 * (Rest * Rest * Rest) + P1 * (3 * Rest * Rest * Along) + P2 * (3 * Rest * Along * Along) + P3 * (Along * Along * Along);
end;

function FlattenStampContour(const Contour: TStampContour; const At: TVec2; Scale, Tolerance: double): TVec2Array;
var
  Segment: TStampSegment;
  Last: TVec2;
  Pieces, Piece: integer;
  Span: double;
begin
  Result := [At + Contour.Start * Scale];
  Last := Contour.Start;
  for Segment in Contour.Segments do
  begin
    if Segment.Curve then
    begin
      // The control polygon is never shorter than the curve
      Span := (Distance(Last, Segment.Control1) + Distance(Segment.Control1, Segment.Control2) +
        Distance(Segment.Control2, Segment.Finish)) * Scale;
      Pieces := EnsureRange(Ceil(Sqrt(Span / Max(Tolerance, 1e-6))), 1, MAX_FLATTEN_PIECES);
      for Piece := 1 to Pieces - 1 do
        Insert(At + CubicAt(Last, Segment.Control1, Segment.Control2, Segment.Finish, Piece / Pieces) * Scale, Result, Length(Result));
    end;
    Insert(At + Segment.Finish * Scale, Result, Length(Result));
    Last := Segment.Finish;
  end;
end;

function StampToJSON(const Drawing: TStampDrawing): TJSONObject;
var
  List: TJSONArray;
  Item: TJSONObject;
  Path: TStampPath;
begin
  Result := TJSONObject.Create;
  try
    Result.Add('width', JSONFloat(Round(Drawing.Width * PATH_DECIMALS) / PATH_DECIMALS));
    Result.Add('height', JSONFloat(Round(Drawing.Height * PATH_DECIMALS) / PATH_DECIMALS));
    List := TJSONArray.Create;
    Result.Add('paths', List);
    for Path in Drawing.Paths do
    begin
      Item := TJSONObject.Create;
      List.Add(Item);
      Item.Add('d', StampPathData(Path, Vec2(0, 0), 1));
      // Each left out when not drawn
      if Path.Fill <> STAMP_NO_COLOUR then
        Item.Add('fill', StampColourText(Path.Fill));
      if Path.Stroke <> STAMP_NO_COLOUR then
      begin
        Item.Add('stroke', StampColourText(Path.Stroke));
        Item.Add('strokeWidth', JSONFloat(Round(Path.StrokeWidth * PATH_DECIMALS) / PATH_DECIMALS));
      end;
      if Path.EvenOdd then
        Item.Add('evenOdd', True);
    end;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function ReadStampPath(Item: TJSONData; out Path: TStampPath; out ErrorMessage: string): boolean;
var
  Obj: TJSONObject;
  Text: string;
begin
  Path := Default(TStampPath);
  Path.Fill := STAMP_NO_COLOUR;
  Path.Stroke := STAMP_NO_COLOUR;
  ErrorMessage := Format(rsStampBadDrawing, ['paths']);
  if Item.JSONType <> jtObject then
    Exit(False);
  Obj := TJSONObject(Item);
  if not GetJSONString(Obj, 'd', Text) then
    Exit(False);
  if not ParseStampPathData(Text, Path.Contours, ErrorMessage) then
    Exit(False);
  ErrorMessage := Format(rsStampBadDrawing, ['fill']);
  if Assigned(Obj.Find('fill')) and (not GetJSONString(Obj, 'fill', Text) or not ParseStampColour(Text, Path.Fill)) then
    Exit(False);
  ErrorMessage := Format(rsStampBadDrawing, ['stroke']);
  if Assigned(Obj.Find('stroke')) and (not GetJSONString(Obj, 'stroke', Text) or not ParseStampColour(Text, Path.Stroke)) then
    Exit(False);
  ErrorMessage := Format(rsStampBadDrawing, ['strokeWidth']);
  if Assigned(Obj.Find('strokeWidth')) and (not GetJSONNumber(Obj, 'strokeWidth', Path.StrokeWidth) or (Path.StrokeWidth < 0)) then
    Exit(False);
  ErrorMessage := Format(rsStampBadDrawing, ['evenOdd']);
  if Assigned(Obj.Find('evenOdd')) and not GetJSONBoolean(Obj, 'evenOdd', Path.EvenOdd) then
    Exit(False);
  ErrorMessage := '';
  Result := True;
end;

function StampFromJSON(Data: TJSONData; out Drawing: TStampDrawing; out ErrorMessage: string): boolean;
var
  Obj: TJSONObject;
  List: TJSONData;
  Index: integer;
begin
  Drawing := Default(TStampDrawing);
  ErrorMessage := Format(rsStampBadDrawing, ['drawing']);
  if Data.JSONType <> jtObject then
    Exit(False);
  Obj := TJSONObject(Data);
  if not GetJSONNumber(Obj, 'width', Drawing.Width) or not GetJSONNumber(Obj, 'height', Drawing.Height) or (Drawing.Width < 0) or
    (Drawing.Height < 0) then
    Exit(False);
  List := Obj.Find('paths');
  if not Assigned(List) or (List.JSONType <> jtArray) or (List.Count = 0) then
    Exit(False);
  SetLength(Drawing.Paths, List.Count);
  for Index := 0 to List.Count - 1 do
    if not ReadStampPath(List.Items[Index], Drawing.Paths[Index], ErrorMessage) then
    begin
      Drawing := Default(TStampDrawing);
      Exit(False);
    end;
  if StampSegmentCount(Drawing) > MAX_STAMP_SEGMENTS then
  begin
    ErrorMessage := Format(rsStampTooDetailed, [MAX_STAMP_SEGMENTS]);
    Drawing := Default(TStampDrawing);
    Exit(False);
  end;
  ErrorMessage := '';
  Result := True;
end;

end.
