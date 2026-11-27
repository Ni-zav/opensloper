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

// The measurements window's body figure as SVG, for the web Measurements
// page, which shows it as an image: the front, back and side outlines, the
// set's measurements drawn faintly on them and one highlighted, as
// Sloper.Measurements.BodyFigure paints them on the desktop. Which measurement
// a point on the figure picks is worked out here too. No LCL dependency.
unit Sloper.Output.BodyFigureSVG;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Catalogue, Sloper.Core.Geometry;

// The figure drawn AWidth by AHeight pixels; Keys are the set's measurements
function BodyFigureToSVG(Catalogue: TCatalogue; AWidth, AHeight: double; const Keys: TStringArray;
  const Highlight: string): string;
// The set's measurement whose line is within a few pixels of the point, or ''
function BodyFigureKeyAt(Catalogue: TCatalogue; AWidth, AHeight: double; const Point: TVec2;
  const Keys: TStringArray): string;
// The closed curve through the points, as the desktop draws an outline
// (BGRABitmap's crossing spline: a Mitchell kernel)
function ClosedFigureCurve(const Points: TFigurePath): TFigurePath;

resourcestring
  rsFigureFront = 'Front';
  rsFigureBack = 'Back';
  rsFigureSide = 'Side';

implementation

uses
  Math;

const
  // As the desktop's figure, in pixels
  HIT_PIXELS = 5;
  OVERLAY_WIDTH = 1.5;
  HIGHLIGHT_WIDTH = 3;
  OUTLINE_WIDTH = 1.2;
  CAPTION_HEIGHT = 13;
  CAPTION_GAP = 2;
  CAPTION_ROOM = CAPTION_HEIGHT + 3 * CAPTION_GAP;
  DESK = '#FFFFFF';
  BODY_FILL = '#F0EEEA';
  BODY_EDGE = '#5A5A60';
  OVERLAY_INK = '#7896BE';
  HIGHLIGHT_INK = '#C8322A';
  // Points a part of an outline, enough for a smooth curve at any size
  CURVE_STEPS = 12;
  NUMBER_DECIMALS = 2;

function Num(Value: double): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FloatToStrF(Value, ffFixed, 15, NUMBER_DECIMALS, Settings);
end;

function XmlText(const Text: string): string;
begin
  Result := StringReplace(Text, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

// Mitchell-Netravali with B = C = 1/3, as BGRABitmap's TMitchellKernel
function Mitchell(Along: double): double;
begin
  Along := Abs(Along);
  if Along < 1 then
    Result := (21 * Along * Along * Along - 36 * Along * Along + 16) / 18
  else if Along < 2 then
    Result := (-7 * Along * Along * Along + 36 * Along * Along - 60 * Along + 32) / 18
  else
    Result := 0;
end;

function ClosedFigureCurve(const Points: TFigurePath): TFigurePath;
var
  Count, Index, Step: integer;
  Before, Here, After, Beyond: TVec2;
  Along: double;
begin
  Count := Length(Points);
  if Count <= 2 then
    Exit(Copy(Points));
  Result := nil;
  SetLength(Result, Count * CURVE_STEPS);
  for Index := 0 to Count - 1 do
  begin
    Before := Points[(Index + Count - 1) mod Count];
    Here := Points[Index];
    After := Points[(Index + 1) mod Count];
    Beyond := Points[(Index + 2) mod Count];
    for Step := 0 to CURVE_STEPS - 1 do
    begin
      Along := Step / CURVE_STEPS;
      Result[Index * CURVE_STEPS + Step] := Before * Mitchell(Along + 1) + Here * Mitchell(Along) + After * Mitchell(Along - 1) +
        Beyond * Mitchell(Along - 2);
    end;
  end;
end;

function FigureLayout(AWidth, AHeight: double): TFigureLayout;
begin
  Result := LayoutFigures(AWidth, AHeight - CAPTION_ROOM);
end;

function PointsText(const Layout: TFigureLayout; View: TCatalogueView; const Path: TFigurePath): string;
var
  Point, Spot: TVec2;
begin
  Result := '';
  for Point in Path do
  begin
    Spot := FigureToScreen(Layout, View, Point);
    Result := Result + Num(Spot.X) + ',' + Num(Spot.Y) + ' ';
  end;
  Result := Trim(Result);
end;

function OverlayElement(const Layout: TFigureLayout; Entry: TCatalogueEntry; const Ink: string; AWidth: double): string;
begin
  Result := Format('<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round" ' +
    'stroke-linecap="round"/>', [PointsText(Layout, Entry.View, Entry.Overlay), Ink, Num(AWidth)]) + #10;
end;

function BodyFigureToSVG(Catalogue: TCatalogue; AWidth, AHeight: double; const Keys: TStringArray;
  const Highlight: string): string;
const
  CAPTIONS: array[TCatalogueView] of string = (rsFigureFront, rsFigureBack, rsFigureSide);
var
  Layout: TFigureLayout;
  View: TCatalogueView;
  Path: TFigurePath;
  Middle: TVec2;
  Key: string;
  Entry: TCatalogueEntry;
  Text: TStringBuilder;
begin
  AWidth := Max(AWidth, 1);
  AHeight := Max(AHeight, 1);
  Layout := FigureLayout(AWidth, AHeight);
  Text := TStringBuilder.Create;
  try
    Text.Append(Format('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %0:s %1:s" width="%0:s" height="%1:s">',
      [Num(AWidth), Num(AHeight)])).Append(#10);
    Text.Append(Format('<rect width="%s" height="%s" fill="%s"/>', [Num(AWidth), Num(AHeight), DESK])).Append(#10);
    for View := Low(TCatalogueView) to High(TCatalogueView) do
    begin
      if not Assigned(Catalogue.Figures[View]) then
        Continue;
      for Path in Catalogue.Figures[View] do
        Text.Append(Format('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
          [PointsText(Layout, View, ClosedFigureCurve(Path)), BODY_FILL, BODY_EDGE, Num(OUTLINE_WIDTH)])).Append(#10);
      Middle := FigureToScreen(Layout, View, Vec2(FIGURE_WIDTH / 2, FIGURE_HEIGHT));
      Text.Append(Format('<text x="%s" y="%s" font-family="sans-serif" font-size="%d" fill="%s" ' +
        'text-anchor="middle" dominant-baseline="hanging">%s</text>', [Num(Middle.X), Num(Middle.Y + CAPTION_GAP),
        CAPTION_HEIGHT, BODY_EDGE, XmlText(CAPTIONS[View])])).Append(#10);
    end;
    for Key in Keys do
    begin
      Entry := Catalogue.Find(Key);
      if Assigned(Entry) then
        Text.Append(OverlayElement(Layout, Entry, OVERLAY_INK, OVERLAY_WIDTH));
    end;
    Entry := Catalogue.Find(Highlight);
    if Assigned(Entry) then
      Text.Append(OverlayElement(Layout, Entry, HIGHLIGHT_INK, HIGHLIGHT_WIDTH));
    Text.Append('</svg>').Append(#10);
    Result := Text.ToString;
  finally
    FreeAndNil(Text);
  end;
end;

function BodyFigureKeyAt(Catalogue: TCatalogue; AWidth, AHeight: double; const Point: TVec2;
  const Keys: TStringArray): string;
var
  Layout: TFigureLayout;
  View: TCatalogueView;
  OnFigure: TVec2;
  Entry: TCatalogueEntry;
begin
  Result := '';
  Layout := FigureLayout(Max(AWidth, 1), Max(AHeight, 1));
  if not ScreenToFigure(Layout, Point, View, OnFigure) then
    Exit;
  Entry := Catalogue.OverlayAt(View, OnFigure, HIT_PIXELS / Layout.Scale, Keys);
  if Assigned(Entry) then
    Result := Entry.Key;
end;

end.
