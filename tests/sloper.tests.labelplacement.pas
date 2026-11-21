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

unit Sloper.Tests.LabelPlacement;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.LabelPlacement;

type
  TTestLabelPlacement = class(TOSTestCase)
  private
    function Request(const At: TVec2; Width, Height: double): TLabelRequest;
    function Overlaps(const First, Second: TRect2): boolean;
    function Box(const TopLeft: TVec2; const Item: TLabelRequest): TRect2;
  published
    procedure TestClearLabelKeepsItsPlace;
    procedure TestLabelMovesOffANote;
    procedure TestLabelsAtOnePointDoNotOverlap;
    procedure TestLabelStaysWithin;
    procedure TestBoxedInTakesTheLeastOverlap;
    procedure TestEarlierLabelsGetTheBetterPlace;
    procedure TestLineNameTriedAtItsMiddleFirst;
    procedure TestManyLabelsAllClear;
    procedure TestNoLabels;
  end;

implementation

uses
  SysUtils;

function TTestLabelPlacement.Request(const At: TVec2; Width, Height: double): TLabelRequest;
begin
  Result.Width := Width;
  Result.Height := Height;
  Result.Places := PlacesAround(At, Width, Height, 2, 2);
end;

function TTestLabelPlacement.Overlaps(const First, Second: TRect2): boolean;
const
  SLACK = 1e-9;
begin
  Result := (First.MinX < Second.MaxX - SLACK) and (Second.MinX < First.MaxX - SLACK) and (First.MinY < Second.MaxY - SLACK) and
    (Second.MinY < First.MaxY - SLACK);
end;

function TTestLabelPlacement.Box(const TopLeft: TVec2; const Item: TLabelRequest): TRect2;
begin
  Result := Rect2(TopLeft.X, TopLeft.Y, TopLeft.X + Item.Width, TopLeft.Y + Item.Height);
end;

procedure TTestLabelPlacement.TestClearLabelKeepsItsPlace;
var
  Places: TVec2Array;
begin
  // Above right of the point, Gap from it, as labels always went
  Places := PlaceLabels([Request(Vec2(10, 20), 30, 5)], nil, False, Default(TRect2));
  AssertNear('x', 12, Places[0].X);
  AssertNear('y', 13, Places[0].Y);
end;

procedure TTestLabelPlacement.TestLabelMovesOffANote;
var
  Item: TLabelRequest;
  Note: TRect2;
  Places: TVec2Array;
begin
  Item := Request(Vec2(10, 20), 30, 5);
  // A note over where the label would go
  Note := Rect2(11, 10, 50, 18);
  Places := PlaceLabels([Item], [Note], False, Default(TRect2));
  AssertFalse('clear of the note', Overlaps(Box(Places[0], Item), Note));
  // Below right is the next best
  AssertNear('x', 12, Places[0].X);
  AssertNear('y', 22, Places[0].Y);
end;

procedure TTestLabelPlacement.TestLabelsAtOnePointDoNotOverlap;
var
  Items: TLabelRequestArray;
  Places: TVec2Array;
  First, Second: integer;
begin
  Items := [Request(Vec2(0, 0), 20, 5), Request(Vec2(0, 0), 20, 5), Request(Vec2(1, 0), 20, 5), Request(Vec2(0, 1), 20, 5)];
  Places := PlaceLabels(Items, nil, False, Default(TRect2));
  for First := 0 to High(Items) do
    for Second := First + 1 to High(Items) do
      AssertFalse(Format('%d and %d', [First, Second]), Overlaps(Box(Places[First], Items[First]), Box(Places[Second], Items[Second])));
end;

procedure TTestLabelPlacement.TestLabelStaysWithin;
var
  Item: TLabelRequest;
  Places: TVec2Array;
begin
  // A point at the right edge: its name goes to the left instead of off it
  Item := Request(Vec2(100, 50), 30, 5);
  Places := PlaceLabels([Item], nil, True, Rect2(0, 0, 100, 100));
  AssertTrue('inside', Places[0].X + Item.Width <= 100);
  AssertNear('above left', 68, Places[0].X);
  AssertNear('still above', 43, Places[0].Y);
end;

procedure TTestLabelPlacement.TestBoxedInTakesTheLeastOverlap;
var
  Item: TLabelRequest;
  Places: TVec2Array;
begin
  Item.Width := 10;
  Item.Height := 5;
  Item.Places := [Vec2(0, 0), Vec2(100, 0)];
  // The first place is wholly covered, the second only partly
  Places := PlaceLabels([Item], [Rect2(-5, -5, 20, 20), Rect2(105, 0, 120, 20)], False, Default(TRect2));
  AssertNear('the less covered', 100, Places[0].X);
end;

procedure TTestLabelPlacement.TestEarlierLabelsGetTheBetterPlace;
var
  Items: TLabelRequestArray;
  Places: TVec2Array;
begin
  Items := [Request(Vec2(0, 0), 20, 5), Request(Vec2(0, 0), 20, 5)];
  Places := PlaceLabels(Items, nil, False, Default(TRect2));
  AssertNear('first keeps above right', Items[0].Places[0].Y, Places[0].Y);
  AssertNear('second moves below', Items[1].Places[1].Y, Places[1].Y);
end;

procedure TTestLabelPlacement.TestLineNameTriedAtItsMiddleFirst;
var
  Along: TVec2Array;
begin
  Along := PolylinePlaces([Vec2(0, 0), Vec2(50, 0), Vec2(100, 0)]);
  AssertEquals('places', Length(LABEL_ALONG_FRACTIONS), Length(Along));
  AssertNear('middle', 50, Along[0].X);
  AssertNear('then towards the start', 40, Along[1].X);
  AssertNear('and the end', 60, Along[2].X);
  AssertEquals('an empty line has none', 0, Length(PolylinePlaces(nil)));
end;

// A row of points close together, as along a waistline: none of their names
// cover one another
procedure TTestLabelPlacement.TestManyLabelsAllClear;
const
  Count = 40;
var
  Items: TLabelRequestArray;
  Places: TVec2Array;
  Index, Other: integer;
begin
  Items := nil;
  SetLength(Items, Count);
  for Index := 0 to Count - 1 do
    Items[Index] := Request(Vec2(Index * 8, 0), 12, 5);
  Places := PlaceLabels(Items, nil, False, Default(TRect2));
  for Index := 0 to Count - 1 do
    for Other := Index + 1 to Count - 1 do
      AssertFalse(Format('%d and %d', [Index, Other]), Overlaps(Box(Places[Index], Items[Index]), Box(Places[Other], Items[Other])));
end;

procedure TTestLabelPlacement.TestNoLabels;
begin
  AssertEquals('nothing', 0, Length(PlaceLabels(nil, [Rect2(0, 0, 1, 1)], False, Default(TRect2))));
end;

initialization
  RegisterTest(TTestLabelPlacement);

end.
