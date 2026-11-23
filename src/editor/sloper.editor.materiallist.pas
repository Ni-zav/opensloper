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

// The pattern's materials as the Materials tab and dialog list them, one row
// each with its colour, name, fill, allowance and size, and the captions of
// the fills and fabrics. The desktop's material grid shows these rows and
// the web editor gets them as data (editor_materials).
unit Sloper.Editor.MaterialList;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Pattern, Sloper.Core.Materials;

type
  TMaterialRow = record
    Name: string;
    // As stored, #RRGGBB
    Color: string;
    Fill: TMaterialFill;
    FillCaption: string;
    // Empty when it has none
    AllowanceText: string;
    SizeText: string;
    // The angle its hatching is drawn at, by its place in the list
    HatchAngle: double;
  end;
  TMaterialRowArray = array of TMaterialRow;

function MaterialRows(Pattern: TPattern): TMaterialRowArray;
function MaterialFillCaption(Fill: TMaterialFill): string;
function FabricCaption(Fabric: TFabric): string;

resourcestring
  rsMaterialColour = 'Colour';
  rsMaterialName = 'Material';
  rsMaterialFill = 'Fill';
  rsMaterialFillTint = 'Tint';
  rsMaterialFillHatch = 'Hatching';
  rsMaterialAllowance = 'Allowance';
  rsMaterialSize = 'Size';
  rsFabricNone = 'Not set (drapes as cotton)';
  rsFabricCotton = 'Cotton';
  rsFabricSilk = 'Silk';
  rsFabricJersey = 'Jersey (knit)';
  rsFabricWool = 'Wool';
  rsFabricDenim = 'Denim';
  rsFabricCanvas = 'Canvas';
  rsFabricLeather = 'Leather';

implementation

uses
  Sloper.Core.JSON, Sloper.Core.Units, Sloper.Core.PatternMaterials;

function MaterialFillCaption(Fill: TMaterialFill): string;
begin
  if Fill = ffHatch then
    Result := rsMaterialFillHatch
  else
    Result := rsMaterialFillTint;
end;

function FabricCaption(Fabric: TFabric): string;
const
  CAPTIONS: array[TFabric] of string = (rsFabricNone, rsFabricCotton, rsFabricSilk, rsFabricJersey, rsFabricWool,
    rsFabricDenim, rsFabricCanvas, rsFabricLeather);
begin
  Result := CAPTIONS[Fabric];
end;

function MaterialRows(Pattern: TPattern): TMaterialRowArray;
var
  Index: integer;
  Material: TPatternMaterial;
begin
  Result := nil;
  SetLength(Result, Pattern.MaterialCount);
  for Index := 0 to Pattern.MaterialCount - 1 do
  begin
    Material := Pattern.Materials[Index];
    Result[Index].Name := Material.Name;
    Result[Index].Color := Material.Color;
    Result[Index].Fill := Material.Fill;
    Result[Index].FillCaption := MaterialFillCaption(Material.Fill);
    if Material.HasAllowance then
      Result[Index].AllowanceText := FormatJSONFloat(Material.Allowance)
    else
      Result[Index].AllowanceText := '';
    Result[Index].SizeText := MaterialSizeText(Material, MEASURE_UNIT_NAMES[Pattern.Units]);
    Result[Index].HatchAngle := MaterialHatchAngle(Index);
  end;
end;

end.
