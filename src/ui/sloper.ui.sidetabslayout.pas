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

// Where the side panel's tab buttons go down its icon column: the tabs in
// order from the top, and those kept at the foot, such as Problems, at the
// bottom. Kept free of the LCL so it can be unit-tested.
unit Sloper.UI.SideTabsLayout;

{$mode ObjFPC}{$H+}

interface

type
  TButtonTops = array of integer;

// The top of each of TopCount buttons and then FootCount buttons, each
// ButtonHeight high, in a column Height high. When the column is too short
// for both, the foot buttons follow straight on from the others.
function PlaceTabButtons(TopCount, FootCount, ButtonHeight, Height: integer): TButtonTops;

implementation

uses
  Math;

function PlaceTabButtons(TopCount, FootCount, ButtonHeight, Height: integer): TButtonTops;
var
  Index, FootStart: integer;
begin
  Result := nil;
  SetLength(Result, TopCount + FootCount);
  for Index := 0 to TopCount - 1 do
    Result[Index] := Index * ButtonHeight;
  FootStart := Max(TopCount * ButtonHeight, Height - FootCount * ButtonHeight);
  for Index := 0 to FootCount - 1 do
    Result[TopCount + Index] := FootStart + Index * ButtonHeight;
end;

end.
