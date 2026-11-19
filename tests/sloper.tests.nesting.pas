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

// True-shape nesting: where a piece's cutting line fits among the others
unit Sloper.Tests.Nesting;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Math, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Output.Nesting;

type
  TTestNesting = class(TOSTestCase)
  private
    FShapes: TNestShapes;
    function Rectangle(Width, Height: double): integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFirstGoesTopLeft;
    procedure TestNextKeepsTheGap;
    procedure TestFillsANotch;
    procedure TestTooWide;
    procedure TestExactlyAsWide;
    procedure TestTurnsToFit;
    procedure TestNoTurnWhenNotAllowed;
    procedure TestDepthLimits;
    procedure TestOnTheGrid;
    procedure TestSameOutlineSameShape;
  end;

implementation

const
  GAP = 10;
  // The drag grid, in mm
  SLACK = 0.5;

function TTestNesting.Rectangle(Width, Height: double): integer;
begin
  Result := FShapes.Add([Vec2(0, 0), Vec2(Width, 0), Vec2(Width, Height), Vec2(0, Height)]);
end;

procedure TTestNesting.SetUp;
begin
  FShapes := TNestShapes.Create(GAP);
end;

procedure TTestNesting.TearDown;
begin
  FreeAndNil(FShapes);
end;

procedure TTestNesting.TestFirstGoesTopLeft;
var
  Sheet: TNestSheet;
  X, Y: double;
  Turned: boolean;
begin
  Sheet := TNestSheet.Create(FShapes, 1000, Infinity);
  try
    AssertTrue('fits', Sheet.Find(Rectangle(100, 100), True, X, Y, Turned));
    AssertNear('left', 0, X);
    AssertNear('top', 0, Y);
    AssertFalse('as it lies', Turned);
  finally
    FreeAndNil(Sheet);
  end;
end;

procedure TTestNesting.TestNextKeepsTheGap;
var
  Sheet: TNestSheet;
  Square: integer;
  X, Y: double;
  Turned: boolean;
begin
  Square := Rectangle(100, 100);
  Sheet := TNestSheet.Create(FShapes, 1000, Infinity);
  try
    Sheet.Put(Square, False, 0, 0);
    AssertTrue('fits', Sheet.Find(Square, True, X, Y, Turned));
    AssertNear('beside it', 0, Y);
    AssertTrue(Format('at least the gap clear, at %g', [X]), X >= 100 + GAP);
    AssertTrue(Format('not much more, at %g', [X]), X <= 100 + GAP + SLACK);
  finally
    FreeAndNil(Sheet);
  end;
end;

// Boxes would set the square below the L; its shape takes it into the notch
procedure TTestNesting.TestFillsANotch;
var
  Sheet: TNestSheet;
  Shape: integer;
  X, Y: double;
  Turned: boolean;
begin
  Shape := FShapes.Add([Vec2(0, 0), Vec2(150, 0), Vec2(150, 150), Vec2(300, 150), Vec2(300, 300), Vec2(0, 300)]);
  Sheet := TNestSheet.Create(FShapes, 300, Infinity);
  try
    Sheet.Put(Shape, False, 0, 0);
    AssertTrue('fits', Sheet.Find(Rectangle(100, 100), True, X, Y, Turned));
    AssertNear('at the top, in the notch', 0, Y);
    AssertTrue(Format('clear of the L, at %g', [X]), X >= 150 + GAP);
    AssertTrue(Format('on the sheet, at %g', [X]), X <= 200);
  finally
    FreeAndNil(Sheet);
  end;
end;

procedure TTestNesting.TestTooWide;
var
  Sheet: TNestSheet;
  X, Y: double;
  Turned: boolean;
begin
  Sheet := TNestSheet.Create(FShapes, 300, Infinity);
  try
    AssertFalse('either way round', Sheet.Find(Rectangle(400, 400), True, X, Y, Turned));
  finally
    FreeAndNil(Sheet);
  end;
end;

procedure TTestNesting.TestExactlyAsWide;
var
  Sheet: TNestSheet;
  X, Y: double;
  Turned: boolean;
begin
  Sheet := TNestSheet.Create(FShapes, 300, Infinity);
  try
    AssertTrue('fits', Sheet.Find(Rectangle(300, 50), False, X, Y, Turned));
    AssertNear('left', 0, X);
  finally
    FreeAndNil(Sheet);
  end;
end;

procedure TTestNesting.TestTurnsToFit;
var
  Sheet: TNestSheet;
  X, Y: double;
  Turned: boolean;
begin
  Sheet := TNestSheet.Create(FShapes, 300, Infinity);
  try
    AssertTrue('fits', Sheet.Find(Rectangle(400, 100), True, X, Y, Turned));
    AssertTrue('a quarter turn', Turned);
    AssertNear('left', 0, X);
  finally
    FreeAndNil(Sheet);
  end;
end;

procedure TTestNesting.TestNoTurnWhenNotAllowed;
var
  Sheet: TNestSheet;
  X, Y: double;
  Turned: boolean;
begin
  Sheet := TNestSheet.Create(FShapes, 300, Infinity);
  try
    AssertFalse('too wide as it lies', Sheet.Find(Rectangle(400, 100), False, X, Y, Turned));
  finally
    FreeAndNil(Sheet);
  end;
end;

// Two 200 mm squares fit side by side on 500 by 250; a third has no room
procedure TTestNesting.TestDepthLimits;
var
  Sheet: TNestSheet;
  Square: integer;
  X, Y: double;
  Turned: boolean;
begin
  Square := Rectangle(200, 200);
  Sheet := TNestSheet.Create(FShapes, 500, 250);
  try
    AssertTrue('first', Sheet.Find(Square, True, X, Y, Turned));
    Sheet.Put(Square, Turned, X, Y);
    AssertTrue('second', Sheet.Find(Square, True, X, Y, Turned));
    AssertNear('beside it', 0, Y);
    Sheet.Put(Square, Turned, X, Y);
    AssertFalse('no third', Sheet.Find(Square, True, X, Y, Turned));
  finally
    FreeAndNil(Sheet);
  end;
end;

// Packed pieces can be lined up by hand on the window's half-millimetre grid
procedure TTestNesting.TestOnTheGrid;
var
  Sheet: TNestSheet;
  Shape: integer;
  X, Y: double;
  Turned: boolean;
begin
  Shape := Rectangle(33.3, 77.7);
  Sheet := TNestSheet.Create(FShapes, 1000, Infinity);
  try
    Sheet.Put(Shape, False, 0, 0);
    AssertTrue('fits', Sheet.Find(Shape, False, X, Y, Turned));
    AssertNear('on the grid across', 0, Frac(X * 2));
    AssertNear('on the grid down', 0, Frac(Y * 2));
  finally
    FreeAndNil(Sheet);
  end;
end;

procedure TTestNesting.TestSameOutlineSameShape;
begin
  AssertEquals('copies share a shape', Rectangle(100, 50), Rectangle(100, 50));
  AssertFalse('another is new', Rectangle(100, 50) = Rectangle(50, 100));
end;

initialization
  RegisterTest(TTestNesting);
end.
