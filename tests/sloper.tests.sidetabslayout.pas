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

// Where the side panel's tab buttons go
unit Sloper.Tests.SideTabsLayout;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.UI.SideTabsLayout;

type
  TTestSideTabsLayout = class(TOSTestCase)
  published
    procedure TestTopAndFoot;
    procedure TestNoFoot;
    procedure TestOnlyFoot;
    procedure TestNoButtons;
    procedure TestTooShort;
  end;

implementation

const
  BUTTON = 30;

procedure TTestSideTabsLayout.TestTopAndFoot;
var
  Tops: TButtonTops;
begin
  Tops := PlaceTabButtons(3, 1, BUTTON, 300);
  AssertEquals(4, Length(Tops));
  AssertEquals('first at the top', 0, Tops[0]);
  AssertEquals(30, Tops[1]);
  AssertEquals(60, Tops[2]);
  AssertEquals('foot at the bottom', 270, Tops[3]);
end;

procedure TTestSideTabsLayout.TestNoFoot;
var
  Tops: TButtonTops;
begin
  Tops := PlaceTabButtons(2, 0, BUTTON, 300);
  AssertEquals(2, Length(Tops));
  AssertEquals(30, Tops[1]);
end;

procedure TTestSideTabsLayout.TestOnlyFoot;
var
  Tops: TButtonTops;
begin
  Tops := PlaceTabButtons(0, 2, BUTTON, 300);
  AssertEquals(240, Tops[0]);
  AssertEquals(270, Tops[1]);
end;

procedure TTestSideTabsLayout.TestNoButtons;
begin
  AssertEquals(0, Length(PlaceTabButtons(0, 0, BUTTON, 300)));
end;

// The foot buttons follow the others rather than cover them
procedure TTestSideTabsLayout.TestTooShort;
var
  Tops: TButtonTops;
begin
  Tops := PlaceTabButtons(3, 1, BUTTON, 100);
  AssertEquals('straight after the third', 90, Tops[3]);
end;

initialization
  RegisterTest(TTestSideTabsLayout);
end.
