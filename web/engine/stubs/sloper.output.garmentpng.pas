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

// Web engine stand-in for Sloper.Output.GarmentPNG, without BGRABitmap
unit Sloper.Output.GarmentPNG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Garment;

const
  GARMENT_PNG_MIN_WIDTH = 16;
  GARMENT_PNG_MAX_WIDTH = 4096;
  GARMENT_PNG_DEFAULT_WIDTH = 1200;

function GarmentToPNG(const Scene: TGarmentScene; const Light: TGarmentLight; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;

resourcestring
  rsGarmentPngWidth = 'The width must be from %d to %d pixels';
  rsGarmentPngNotInWasm = 'PNG is not available in the web engine; use SVG';

implementation

function GarmentToPNG(const Scene: TGarmentScene; const Light: TGarmentLight; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;
begin
  Png := '';
  ErrorMessage := rsGarmentPngNotInWasm;
  Result := False;
end;

end.
