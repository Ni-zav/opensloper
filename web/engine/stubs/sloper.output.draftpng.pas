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

// Web engine stand-in for Sloper.Output.DraftPNG: the same interface without
// BGRABitmap, which the Wasm engine leaves out. PNG is refused.
unit Sloper.Output.DraftPNG;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern, Sloper.Output.DraftSVG;

const
  PNG_MIN_WIDTH = 16;
  PNG_MAX_WIDTH = 4096;
  PNG_DEFAULT_WIDTH = 1600;
  PNG_MAX_HEIGHT = 4 * PNG_MAX_WIDTH;

function DraftToPNG(Pattern: TPattern; const Options: TDraftSVGOptions; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;
function DrawingFontFamilies: string;

resourcestring
  rsPngWidth = 'The width must be from %d to %d pixels';
  rsPngNoFonts = 'No fonts to draw text with were found in data/fonts';
  rsPngEmptyArea = 'The area to draw has no width or no height';
  rsPngNotInWasm = 'PNG is not available in the web engine; use SVG';

implementation

function DraftToPNG(Pattern: TPattern; const Options: TDraftSVGOptions; Width: integer; out Png: rawbytestring;
  out ErrorMessage: string): boolean;
begin
  Png := '';
  ErrorMessage := rsPngNotInWasm;
  Result := False;
end;

function DrawingFontFamilies: string;
begin
  Result := '';
end;

end.
