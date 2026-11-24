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

// Changing a point's type in place (TPattern.ConvertPoint): it keeps its ID,
// name, marker and users, and stays where it is, or moves a little onto its
// new edge, line or crossing.
unit Sloper.Tests.ConvertPoint;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern;

type
  TTestConvertPoint = class(TOSTestCase)
  private
    FPattern: TPattern;
    function Pt(const AName: string; X, Y: double): string;
    function Line(const StartKey, EndKey: string): string;
    // Converts the point and evaluates, failing the test when it is refused
    function Convert(const Key: string; Conversion: TPointConversion; const Inputs: array of string): TPointObject;
    // Converts the point, expecting a refusal that names Expected, and the point left as it was
    procedure Refused(const Key: string; Conversion: TPointConversion; const Inputs: array of string; const Expected: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFreeToAlongEdgeKeepsIdNameAndUsers;
    procedure TestAlongEdgeFromTheNearerEnd;
    procedure TestAlongEdgeToFreeReplacesFormulas;
    procedure TestFreeToOffset;
    procedure TestBetweenMovesOntoTheLine;
    procedure TestIntersectPicksTheNearestCrossing;
    procedure TestIntersectExtendsOnlyWhenNeeded;
    procedure TestCircleEdge;
    procedure TestCircleCircleKeepsItsSide;
    procedure TestProjectSquareToTheEdge;
    procedure TestProjectAtAnAngle;
    procedure TestTooFarRefused;
    procedure TestAlreadySoRefused;
    procedure TestOffsetFromAnotherBaseAllowed;
    procedure TestWrongInputsRefused;
    procedure TestReadingItselfRefused;
    procedure TestCornerPointRefused;
    procedure TestMarkerKept;
    procedure TestWorksInCentimetres;
    procedure TestTypeNamesAreTheFiles;
  end;

implementation

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Units, Sloper.Core.TypeChange,
  Sloper.Core.PatternFile;

const
  // How far rounding a field to 0.1 mm can move a point (mm)
  ROUNDING_MOVE = 0.1;

procedure TTestConvertPoint.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestConvertPoint.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestConvertPoint.Pt(const AName: string; X, Y: double): string;
begin
  Result := FPattern.AddFreePoint(AName, FloatToStr(X), FloatToStr(Y)).Key;
end;

function TTestConvertPoint.Line(const StartKey, EndKey: string): string;
begin
  Result := FPattern.AddLine(StartKey, EndKey).Key;
end;

function TTestConvertPoint.Convert(const Key: string; Conversion: TPointConversion; const Inputs: array of string): TPointObject;
begin
  Result := FPattern.ConvertPoint(TPointObject(FPattern.FindNode(Key)), Conversion, Inputs);
  AssertNotNull(FPattern.LastError, Result);
  AssertEquals('same ID', Key, Result.Key);
  AssertTrue('found by its ID', FPattern.FindNode(Key) = Result);
  FPattern.Evaluate;
  AssertTrue('valid', Result.State = esValid);
end;

procedure TTestConvertPoint.Refused(const Key: string; Conversion: TPointConversion; const Inputs: array of string;
  const Expected: string);
var
  Before: TEvalNode;
begin
  Before := FPattern.FindNode(Key);
  AssertNull('refused', FPattern.ConvertPoint(TPointObject(Before), Conversion, Inputs));
  AssertTrue(FPattern.LastError, Pos(Expected, FPattern.LastError) > 0);
  AssertTrue('left as it was', FPattern.FindNode(Key) = Before);
end;

procedure TTestConvertPoint.TestFreeToAlongEdgeKeepsIdNameAndUsers;
var
  Edge, Key: string;
  Reader: TOffsetPoint;
  Converted: TPointObject;
begin
  Edge := Line(Pt('A', 0, 0), Pt('B', 100, 0));
  Key := Pt('P', 40, 0);
  Reader := FPattern.AddOffsetPoint('R', Key, omCartesian, '0', '20');
  AssertNotNull(FPattern.LastError, Reader);
  Converted := Convert(Key, pcAlongEdge, [Edge]);
  AssertTrue('along the edge', Converted is TAlongEdgePoint);
  AssertEquals('keeps its name', 'P', Converted.Name);
  AssertFalse('from the start', TAlongEdgePoint(Converted).FromEnd);
  AssertEquals('a length', Ord(amLength), Ord(TAlongEdgePoint(Converted).Mode));
  AssertEquals('40', Converted.Field('value').StoredText);
  AssertPointsNear('stays', Vec2(40, 0), Converted.Position);
  AssertTrue('the reader is fine', Reader.State = esValid);
  AssertPointsNear('and follows it', Vec2(40, 20), Reader.Position);
end;

procedure TTestConvertPoint.TestAlongEdgeFromTheNearerEnd;
var
  Converted: TPointObject;
begin
  Converted := Convert(Pt('P', 70, 0), pcAlongEdge, [Line(Pt('A', 0, 0), Pt('B', 100, 0))]);
  AssertTrue('from the end', TAlongEdgePoint(Converted).FromEnd);
  AssertEquals('30', Converted.Field('value').StoredText);
  AssertPointsNear('stays', Vec2(70, 0), Converted.Position);
end;

procedure TTestConvertPoint.TestAlongEdgeToFreeReplacesFormulas;
var
  Edge, Key: string;
  Converted: TPointObject;
begin
  Edge := Line(Pt('A', 0, 0), Pt('B', 100, 0));
  Key := FPattern.AddAlongEdgePoint('P', Edge, False, amRatio, '1/4').Key;
  Converted := Convert(Key, pcFree, []);
  AssertTrue('free', Converted is TFreePoint);
  AssertEquals('25', Converted.Field('x').StoredText);
  AssertEquals('0', Converted.Field('y').StoredText);
  AssertPointsNear('stays', Vec2(25, 0), Converted.Position);
end;

procedure TTestConvertPoint.TestFreeToOffset;
var
  Base: string;
  Converted: TPointObject;
begin
  Base := Pt('A', 10, 20);
  Converted := Convert(Pt('P', 40, -5), pcOffset, [Base]);
  AssertEquals('from A', Base, TOffsetPoint(Converted).Base);
  AssertEquals('across and down', Ord(omCartesian), Ord(TOffsetPoint(Converted).Mode));
  AssertEquals('30', Converted.Field('dx').StoredText);
  AssertEquals('-25', Converted.Field('dy').StoredText);
  AssertPointsNear('stays', Vec2(40, -5), Converted.Position);
end;

procedure TTestConvertPoint.TestBetweenMovesOntoTheLine;
var
  A, B: string;
  Converted: TPointObject;
begin
  A := Pt('A', 0, 0);
  B := Pt('B', 100, 0);
  Converted := Convert(Pt('P', 30, 2), pcBetween, [A, B]);
  AssertEquals('from A', A, TBetweenPoint(Converted).PointA);
  AssertEquals('30', Converted.Field('value').StoredText);
  AssertPointsNear('onto the line', Vec2(30, 0), Converted.Position);
end;

procedure TTestConvertPoint.TestIntersectPicksTheNearestCrossing;
var
  Across, Curve: string;
  Converted: TPointObject;
begin
  Across := Line(Pt('A', 0, 50), Pt('B', 100, 50));
  // An arch that crosses the line twice, at about 20 and 80
  Curve := FPattern.AddCurve(Pt('C', 0, 100), Pt('D', 100, 100), '80', '90', '100', '90').Key;
  FPattern.Evaluate;
  Converted := Convert(Pt('P', 79, 50), pcIntersect, [Across, Curve]);
  AssertEquals('the second crossing along the line', 2, TIntersectPoint(Converted).Pick);
  AssertFalse('not extended', TIntersectPoint(Converted).ExtendA or TIntersectPoint(Converted).ExtendB);
  AssertNear('on the line', 50, Converted.Position.Y);
  AssertTrue('the nearer crossing', Converted.Position.X > 50);
end;

procedure TTestConvertPoint.TestIntersectExtendsOnlyWhenNeeded;
var
  Short, Across: string;
  Converted: TPointObject;
begin
  // The short line stops at y = 40, short of the line at y = 50
  Short := Line(Pt('A', 50, 0), Pt('B', 50, 40));
  Across := Line(Pt('C', 0, 50), Pt('D', 100, 50));
  Converted := Convert(Pt('P', 50, 50), pcIntersect, [Short, Across]);
  AssertTrue('the short line extended', TIntersectPoint(Converted).ExtendA);
  AssertFalse('the other not', TIntersectPoint(Converted).ExtendB);
  AssertPointsNear('stays', Vec2(50, 50), Converted.Position);
  // Parallel, so they never cross however far they run
  Refused(Pt('Q', 55, 20), pcIntersect, [Short, Line(Pt('E', 60, 0), Pt('F', 60, 40))], 'do not cross');
end;

procedure TTestConvertPoint.TestCircleEdge;
var
  Centre: string;
  Converted: TPointObject;
begin
  Centre := Pt('C', 0, 0);
  Converted := Convert(Pt('P', 40, 30), pcCircleEdge, [Centre, Line(Pt('A', -100, 30), Pt('B', 100, 30))]);
  AssertEquals('50', Converted.Field('radius').StoredText);
  AssertPointsNear('the crossing it was at, not the other', Vec2(40, 30), Converted.Position);
end;

procedure TTestConvertPoint.TestCircleCircleKeepsItsSide;
var
  A, B: string;
  Converted: TPointObject;
begin
  A := Pt('A', 0, 0);
  B := Pt('B', 80, 0);
  Converted := Convert(Pt('P', 30, 40), pcCircleCircle, [A, B]);
  AssertEquals('50', Converted.Field('radiusA').StoredText);
  // The radius from B, 64.03, is written to the 0.1 mm a drag rounds to
  AssertEquals('64', Converted.Field('radiusB').StoredText);
  AssertPointsNear('below, where it was', Vec2(30, 40), Converted.Position, ROUNDING_MOVE);
  Converted := Convert(Pt('Q', 30, -40), pcCircleCircle, [A, B]);
  AssertPointsNear('above, where it was', Vec2(30, -40), Converted.Position, ROUNDING_MOVE);
end;

procedure TTestConvertPoint.TestProjectSquareToTheEdge;
var
  Converted: TPointObject;
begin
  Converted := Convert(Pt('P', 50, 0), pcProject, [Pt('S', 50, -50), Line(Pt('A', 0, 0), Pt('B', 100, 0))]);
  AssertEquals('square to it', Ord(pdPerpendicular), Ord(TProjectPoint(Converted).Direction));
  AssertPointsNear('stays', Vec2(50, 0), Converted.Position);
end;

procedure TTestConvertPoint.TestProjectAtAnAngle;
var
  Converted: TPointObject;
begin
  Converted := Convert(Pt('P', 70, 0), pcProject, [Pt('S', 50, -20), Line(Pt('A', 0, 0), Pt('B', 100, 0))]);
  AssertEquals('at an angle', Ord(pdAngle), Ord(TProjectPoint(Converted).Direction));
  // Down and to the right of S, so below 0 degrees
  AssertEquals('315', Converted.Field('angle').StoredText);
  AssertPointsNear('stays', Vec2(70, 0), Converted.Position, ROUNDING_MOVE);
end;

procedure TTestConvertPoint.TestTooFarRefused;
begin
  Refused(Pt('P', 50, 40), pcAlongEdge, [Line(Pt('A', 0, 0), Pt('B', 100, 0))], '40 mm');
end;

procedure TTestConvertPoint.TestAlreadySoRefused;
var
  Edge, Key: string;
begin
  Refused(Pt('P', 5, 5), pcFree, [], 'already');
  Edge := Line(Pt('A', 0, 0), Pt('B', 100, 0));
  Key := FPattern.AddAlongEdgePoint('Q', Edge, False, amRatio, '0.5').Key;
  Refused(Key, pcAlongEdge, [Edge], 'already');
end;

procedure TTestConvertPoint.TestOffsetFromAnotherBaseAllowed;
var
  Key: string;
  Converted: TPointObject;
begin
  Key := FPattern.AddOffsetPoint('P', Pt('A', 0, 0), omPolar, '50', '0').Key;
  Converted := Convert(Key, pcOffset, [Pt('B', 20, 10)]);
  AssertEquals('30', Converted.Field('dx').StoredText);
  AssertEquals('-10', Converted.Field('dy').StoredText);
  AssertPointsNear('stays', Vec2(50, 0), Converted.Position);
end;

procedure TTestConvertPoint.TestWrongInputsRefused;
var
  Key, A: string;
begin
  Key := Pt('P', 50, 0);
  A := Pt('A', 0, 0);
  Refused(Key, pcBetween, [A], 'two points');
  Refused(Key, pcAlongEdge, [A], 'A');
end;

procedure TTestConvertPoint.TestReadingItselfRefused;
var
  Key: string;
begin
  Key := Pt('P', 0, 0);
  Refused(Key, pcAlongEdge, [Line(Key, Pt('B', 100, 0))], 'P');
  AssertTrue('still free', FPattern.FindNode(Key) is TFreePoint);
end;

procedure TTestConvertPoint.TestCornerPointRefused;
var
  Index: integer;
  B: string;
begin
  B := Pt('B', 100, 0);
  AssertNotNull(FPattern.LastError, FPattern.AddRoundCorner(Line(Pt('A', 0, 0), B), Line(B, Pt('C', 100, 100)), '10'));
  FPattern.Evaluate;
  for Index := 0 to FPattern.ObjectCount - 1 do
    if FPattern.Objects[Index] is TCornerPoint then
    begin
      Refused(FPattern.Objects[Index].Key, pcFree, [], 'rounded corner');
      Exit;
    end;
  Fail('no corner point');
end;

// The API names conversions by the types the pattern file saves
procedure TTestConvertPoint.TestTypeNamesAreTheFiles;
var
  Made: array[TPointConversion] of TPointObject;
  Conversion: TPointConversion;
begin
  Made[pcFree] := TFreePoint.Create('1');
  Made[pcOffset] := TOffsetPoint.Create('2', '9', omCartesian);
  Made[pcAlongEdge] := TAlongEdgePoint.Create('3', '9', False, amLength);
  Made[pcBetween] := TBetweenPoint.Create('4', '8', '9', amLength);
  Made[pcIntersect] := TIntersectPoint.Create('5', '8', '9', False, False, 0);
  Made[pcCircleEdge] := TCircleEdgePoint.Create('6', '8', '9', False, 0);
  Made[pcCircleCircle] := TCircleCirclePoint.Create('7', '8', '9', 0);
  Made[pcProject] := TProjectPoint.Create('10', '8', '9', pdPerpendicular, False);
  try
    for Conversion := Low(TPointConversion) to High(TPointConversion) do
      AssertEquals(PatternObjectTypeName(Made[Conversion]), POINT_CONVERSION_TYPES[Conversion]);
  finally
    for Conversion := Low(TPointConversion) to High(TPointConversion) do
      Made[Conversion].Free;
  end;
end;

procedure TTestConvertPoint.TestMarkerKept;
var
  Key: string;
  Converted: TPointObject;
begin
  Key := Pt('P', 40, 0);
  AssertTrue(FPattern.LastError, FPattern.SetMarker(Key, pmHole, '4'));
  Converted := Convert(Key, pcAlongEdge, [Line(Pt('A', 0, 0), Pt('B', 100, 0))]);
  AssertEquals('still a hole', Ord(pmHole), Ord(Converted.Marker));
end;

procedure TTestConvertPoint.TestWorksInCentimetres;
var
  Converted: TPointObject;
begin
  FPattern.Units := muCentimetre;
  // 4 cm and 2.5 cm from the origin, written in cm
  Converted := Convert(FPattern.AddFreePoint('P', '4', '2.5').Key, pcOffset, [FPattern.AddFreePoint('A', '1', '0.5').Key]);
  AssertEquals('3', Converted.Field('dx').StoredText);
  AssertEquals('2', Converted.Field('dy').StoredText);
  AssertPointsNear('stays', Vec2(40, 25), Converted.Position);
end;

initialization
  RegisterTest(TTestConvertPoint);
end.
