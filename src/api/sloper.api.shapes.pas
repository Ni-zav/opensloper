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

// Shapes as the editors draw them, in JSON: points and segments as flat lists
// of numbers, for the design canvas and the publish preview. No LCL dependency.
unit Sloper.API.Shapes;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson, Sloper.Core.Geometry;

// Points as one flat list: x1, y1, x2, y2 and on
function LineToJSON(const Line: TVec2Array): TJSONArray;
// Line segments as one flat list: x1, y1, x2, y2 for each
function SegmentsToJSON(const Segments: TLine2Array): TJSONArray;

implementation

uses
  Sloper.Core.PatternCheck;

function LineToJSON(const Line: TVec2Array): TJSONArray;
var
  Point: TVec2;
begin
  Result := TJSONArray.Create;
  for Point in Line do
  begin
    Result.Add(ReportFloat(Point.X));
    Result.Add(ReportFloat(Point.Y));
  end;
end;

function SegmentsToJSON(const Segments: TLine2Array): TJSONArray;
var
  Segment: TLine2;
begin
  Result := TJSONArray.Create;
  for Segment in Segments do
  begin
    Result.Add(ReportFloat(Segment.P1.X));
    Result.Add(ReportFloat(Segment.P1.Y));
    Result.Add(ReportFloat(Segment.P2.X));
    Result.Add(ReportFloat(Segment.P2.Y));
  end;
end;

end.
