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

// The drape app's view as SVG, from one of its fixed views: the body and the
// placed pieces as Sloper.Core.DrapeScene draws them, back to front, the
// seams' links and the attached edges over them, and each piece numbered by its place in the
// drape's list, so whoever looks can name it. For the Claude tab, which sees
// it as an image. No LCL dependency.
unit Sloper.Output.DrapeSVG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.DrapeFile, Sloper.Core.DrapePlacement;

function DrapeViewToSVG(Drape: TDrape; View: TDrapeView): string;

implementation

uses
  SysUtils, Math, Sloper.Core.Geometry, Sloper.Core.Materials, Sloper.Core.DrapeScene;

const
  // Room round the drawing, in screen units
  MARGIN = 20;
  PIECE_STROKE = '#333333';
  SEAM_STROKE = '#E07020';
  ATTACHED_STROKE = '#2E9A40';
  LABEL_COLOR = '#000000';
  LABEL_HALO = '#FFFFFF';
  // Widths and sizes, in screen units
  PIECE_STROKE_WIDTH = 1;
  BODY_STROKE_WIDTH = 0.5;
  SEAM_STROKE_WIDTH = 1.5;
  ATTACHED_STROKE_WIDTH = 4;
  LABEL_SIZE = 14;
  LABEL_HALO_WIDTH = 3;
  NUMBER_DECIMALS = 2;

function Num(Value: double): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Result := FloatToStrF(Value, ffFixed, 15, NUMBER_DECIMALS, Settings);
end;

function PointsText(const Points: TVec2Array): string;
var
  Point: TVec2;
begin
  Result := '';
  for Point in Points do
    Result := Result + Num(Point.X) + ',' + Num(Point.Y) + ' ';
end;

function DrapeViewToSVG(Drape: TDrape; View: TDrapeView): string;
var
  Faces: TDrapeFaceArray;
  Lines: TDrapeLineArray;
  Face: TDrapeFace;
  Line: TDrapeLine;
  Point: TVec2;
  Low, High, Middle: TVec2;
  First: boolean;
  Body, Labels: TStringBuilder;
  Labelled: array of boolean;
  Color, Stroke: string;
  Attached: TVec2Array;
  StrokeWidth: double;
begin
  Faces := BuildDrapeScene(Drape, CameraForView(DefaultDrapeCamera, View));
  Lines := DrapeSceneLines(Drape, CameraForView(DefaultDrapeCamera, View));
  Low := Vec2(0, 0);
  High := Vec2(0, 0);
  First := True;
  for Face in Faces do
    for Point in Face.Points do
    begin
      if First then
      begin
        Low := Point;
        High := Point;
        First := False;
      end;
      Low := Vec2(Min(Low.X, Point.X), Min(Low.Y, Point.Y));
      High := Vec2(Max(High.X, Point.X), Max(High.Y, Point.Y));
    end;
  Low := Low - Vec2(MARGIN, MARGIN);
  High := High + Vec2(MARGIN, MARGIN);
  Labelled := nil;
  SetLength(Labelled, Length(Drape.Items));
  Body := TStringBuilder.Create;
  Labels := TStringBuilder.Create;
  try
    Body.Append(Format('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%s %s %s %s" width="%s" height="%s">',
      [Num(Low.X), Num(Low.Y), Num(High.X - Low.X), Num(High.Y - Low.Y), Num(High.X - Low.X), Num(High.Y - Low.Y)])).Append(#10);
    Body.Append(Format('<rect x="%s" y="%s" width="%s" height="%s" fill="#FFFFFF"/>', [Num(Low.X), Num(Low.Y), Num(High.X - Low.X),
      Num(High.Y - Low.Y)])).Append(#10);
    for Face in Faces do
    begin
      Color := MaterialColorText(Face.Color);
      if Face.Item < 0 then
      begin
        // The body's small triangles, edged in their own colour so no gaps show
        Stroke := Color;
        StrokeWidth := BODY_STROKE_WIDTH;
      end
      else
      begin
        Stroke := PIECE_STROKE;
        StrokeWidth := PIECE_STROKE_WIDTH;
      end;
      Body.Append(Format('<polygon points="%s" fill="%s" stroke="%s" stroke-width="%s" stroke-linejoin="round"/>',
        [PointsText(Face.Points), Color, Stroke, Num(StrokeWidth)])).Append(#10);
      // Numbered once, at its outline's middle
      if (Face.Item >= 0) and (Face.Item <= System.High(Labelled)) and not Labelled[Face.Item] then
      begin
        Labelled[Face.Item] := True;
        Middle := PolygonMiddle(Face.Points);
        // A halo first, then the number over it, so it reads on any colour
        Labels.Append(Format('<text x="%0:s" y="%1:s" font-family="sans-serif" font-size="%2:d" text-anchor="middle" ' +
          'fill="%3:s" stroke="%3:s" stroke-width="%4:d">%5:d</text>', [Num(Middle.X), Num(Middle.Y), LABEL_SIZE, LABEL_HALO,
          LABEL_HALO_WIDTH, Face.Item])).Append(#10);
        Labels.Append(Format('<text x="%0:s" y="%1:s" font-family="sans-serif" font-size="%2:d" text-anchor="middle" ' +
          'fill="%3:s">%4:d</text>', [Num(Middle.X), Num(Middle.Y), LABEL_SIZE, LABEL_COLOR, Face.Item])).Append(#10);
      end;
    end;
    for Line in Lines do
      Body.Append(Format('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="%s" stroke-width="%s"/>', [Num(Line.From.X),
        Num(Line.From.Y), Num(Line.Onto.X), Num(Line.Onto.Y), SEAM_STROKE, Num(SEAM_STROKE_WIDTH)])).Append(#10);
    for Attached in DrapeAttachedLines(Drape, CameraForView(DefaultDrapeCamera, View)) do
      Body.Append(Format('<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linejoin="round" ' +
        'stroke-linecap="round"/>', [PointsText(Attached), ATTACHED_STROKE, Num(ATTACHED_STROKE_WIDTH)])).Append(#10);
    Body.Append(Labels.ToString);
    Body.Append('</svg>').Append(#10);
    Result := Body.ToString;
  finally
    FreeAndNil(Labels);
    FreeAndNil(Body);
  end;
end;

end.
