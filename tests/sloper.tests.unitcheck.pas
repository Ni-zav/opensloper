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

// Unit suffixes in angle and ratio fields (issue #33): a formula whose unit
// makes it a length is refused where a plain number belongs
unit Sloper.Tests.UnitCheck;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.Draft,
  Sloper.Core.UnitCheck;

type
  TTestUnitCheck = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    FPolar: TOffsetPoint;
    FAlong: TAlongEdgePoint;
    procedure Refused(const Field, Text, Expected: string; ExpectedPos: integer);
    procedure Taken(const Field, Text: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAngleWithAUnit;
    procedure TestRatioWithAUnit;
    procedure TestLengthsThatCancel;
    procedure TestPlainFormulasLeftAlone;
    procedure TestInsideAFunction;
    procedure TestAddingALengthToANumber;
    procedure TestLengthFieldsLeftAlone;
    procedure TestNewObjectsToo;
    procedure TestLoadingIsNotChecked;
  end;

implementation

uses
  Sloper.Core.PatternFile;

procedure TTestUnitCheck.SetUp;
var
  Base, Other: TFreePoint;
  Hem: TLineObject;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
  FPattern.AddVariable('ease', '20');
  Base := FPattern.AddFreePoint('A', '0', '0');
  Other := FPattern.AddFreePoint('B', '400', '300');
  FPolar := FPattern.AddOffsetPoint('C', Base.Key, omPolar, '100', '0');
  Hem := FPattern.AddLine(Base.Key, Other.Key, erOutline, 'Hem');
  FAlong := FPattern.AddAlongEdgePoint('E', Hem.Key, False, amRatio, '0.5');
  FPattern.Evaluate;
end;

procedure TTestUnitCheck.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

procedure TTestUnitCheck.Refused(const Field, Text, Expected: string; ExpectedPos: integer);
var
  Node: TDraftObject;
begin
  Node := FPolar;
  if Field = 'value' then
    Node := FAlong;
  AssertFalse(Text + ' is refused', FPattern.SetFormula(Node, Field, Text));
  AssertEquals(Text, Expected, FPattern.LastError);
  AssertEquals(Text + ': where', ExpectedPos, FPattern.LastErrorPos);
  AssertEquals(Text + ': the field', Field, FPattern.LastErrorField);
end;

procedure TTestUnitCheck.Taken(const Field, Text: string);
var
  Node: TDraftObject;
begin
  Node := FPolar;
  if Field = 'value' then
    Node := FAlong;
  AssertTrue(Text + ': ' + FPattern.LastError, FPattern.SetFormula(Node, Field, Text));
end;

procedure TTestUnitCheck.TestAngleWithAUnit;
begin
  Refused('angle', '45mm', Format(rsUnitCheckAngle, ['45mm']), 1);
  Refused('angle', '90 + 2cm', Format(rsUnitCheckAngle, ['2cm']), 6);
  AssertEquals('kept as it was', '0', FPattern.FormulaText(FPolar, 'angle'));
end;

procedure TTestUnitCheck.TestRatioWithAUnit;
begin
  Refused('value', '0.5cm', Format(rsUnitCheckNumber, ['0.5cm']), 1);
  Refused('value', '@waist/4 + 1in', Format(rsUnitCheckNumber, ['1in']), 12);
end;

// A length divided by a length is a plain number
procedure TTestUnitCheck.TestLengthsThatCancel;
begin
  Taken('value', 'Hem.length / 1000mm');
  Taken('value', '10cm / @waist');
  Taken('angle', 'atan2(5cm, Hem.length)');
  Taken('angle', 'asin(50mm / Hem.length)');
  Taken('angle', 'Hem.angle + 90');
end;

// Only formulas with a unit are judged, so patterns that never wrote one
// are not refused for what they already do
procedure TTestUnitCheck.TestPlainFormulasLeftAlone;
begin
  Taken('angle', '@waist / 4');
  Taken('value', '#ease / 40');
  Taken('angle', '2 * 45');
end;

procedure TTestUnitCheck.TestInsideAFunction;
begin
  Refused('angle', 'sin(5cm) * 90', Format(rsUnitCheckFunction, ['5cm', 'sin']), 5);
  Refused('angle', 'atan2(5cm, Hem.angle)', Format(rsUnitCheckFunction, ['5cm', 'atan2']), 7);
  // A plain number beside a length can be a length in the pattern's unit
  Taken('angle', 'atan2(5cm, 2)');
end;

procedure TTestUnitCheck.TestAddingALengthToANumber;
begin
  Refused('angle', 'Hem.angle + 1cm', Format(rsUnitCheckMixed, ['1cm']), 13);
end;

// A length field's own units are not judged here: the issue is plain-number fields
procedure TTestUnitCheck.TestLengthFieldsLeftAlone;
begin
  Taken('length', '10cm');
  Taken('length', '@waist / 4 + 2in');
end;

procedure TTestUnitCheck.TestNewObjectsToo;
begin
  AssertFalse('a new point', Assigned(FPattern.AddOffsetPoint('D', FPolar.Key, omPolar, '10', '30mm')));
  AssertEquals(Format(rsUnitCheckAngle, ['30mm']), FPattern.LastError);
  AssertEquals('angle', FPattern.LastErrorField);
end;

// A file is read as it is, so a pattern written before the check still opens
procedure TTestUnitCheck.TestLoadingIsNotChecked;
var
  Loaded: TPattern;
  Reason: string;
begin
  Loaded := TPattern.Create;
  try
    AssertTrue(Reason, LoadPatternFromText(Loaded, '{"format": "pattern", "version": 1, "objects": [' +
      '{"id": 1, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
      '{"id": 2, "type": "offsetPoint", "name": "B", "base": 1, "mode": "polar", "length": "10", "angle": "45mm"}]}', Reason));
  finally
    FreeAndNil(Loaded);
  end;
end;

initialization
  RegisterTest(TTestUnitCheck);
end.
