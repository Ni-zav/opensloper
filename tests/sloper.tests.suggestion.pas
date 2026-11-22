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

// Formula suggestions (issue #26), and dragging a point by one field
unit Sloper.Tests.Suggestion;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Evaluator, Sloper.Core.Measurements, Sloper.Core.Pattern,
  Sloper.Core.Draft, Sloper.Editor.Suggestion;

type
  TTestSuggestion = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    FBase, FFree: TFreePoint;
    FOffset, FPolar: TOffsetPoint;
    FAlong: TAlongEdgePoint;
    FHem: TLineObject;
    function Suggested(Node: TEvalNode; const FieldName: string; Target: double): TSuggestions;
    function Texts(const Found: TSuggestions): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestKinds;
    procedure TestNumbersAndFormulas;
    procedure TestFormulaLeavesItselfOut;
    procedure TestTarget;
    procedure TestTargetInPatternUnit;
    procedure TestQuarterWaistFirst;
    procedure TestClosestFirst;
    procedure TestWithinTolerance;
    procedure TestNothingClose;
    procedure TestNegative;
    procedure TestDirectionRanks;
    procedure TestDifference;
    procedure TestAmountAdded;
    procedure TestVariable;
    procedure TestEdgeLength;
    procedure TestPointCoordinates;
    procedure TestMidpoints;
    procedure TestLeavesOutDependents;
    procedure TestAngles;
    procedure TestAngleWrapsRound;
    procedure TestRatios;
    procedure TestNotePositionIsARatio;
    procedure TestCentimetres;
    procedure TestTexts;
    procedure TestDragField;
    procedure TestDragPolarLength;
    procedure TestDragPolarAngle;
    procedure TestDragFieldOtherIsFormula;
    procedure TestDragFormulaField;
    procedure TestFieldPosition;
    procedure TestFieldGuide;
    procedure TestEvaluateText;
    procedure TestGradeNeedsSizes;
    procedure TestGradeValues;
    procedure TestGradeGhosts;
  end;

implementation

uses
  Math, Sloper.Core.Geometry, Sloper.Core.Drag, Sloper.Core.Units, Sloper.Core.Note, Sloper.Editor.SuggestionGrade;

procedure TTestSuggestion.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FSet.Add('hip', 960);
  FSet.Add('height_waist', 1040);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
  FPattern.AddVariable('ease', '20');
  FBase := FPattern.AddFreePoint('A', '0', '0');
  FFree := FPattern.AddFreePoint('B', '400', '300');
  FOffset := FPattern.AddOffsetPoint('C', FBase.Key, omCartesian, '175', '30');
  FPolar := FPattern.AddOffsetPoint('D', FBase.Key, omPolar, '100', '0');
  FHem := FPattern.AddLine(FBase.Key, FFree.Key, erOutline, 'Hem');
  FAlong := FPattern.AddAlongEdgePoint('E', FHem.Key, False, amRatio, '0.33');
  FPattern.Evaluate;
end;

procedure TTestSuggestion.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestSuggestion.Suggested(Node: TEvalNode; const FieldName: string; Target: double): TSuggestions;
var
  Source: TSuggestionSource;
begin
  Source := TSuggestionSource.Create(FPattern, Node, FieldName);
  try
    Result := Source.Match(Target);
  finally
    FreeAndNil(Source);
  end;
end;

function TTestSuggestion.Texts(const Found: TSuggestions): string;
var
  Item: TSuggestion;
begin
  Result := '';
  for Item in Found.Items do
    Result := Result + Item.Text + ';';
end;

procedure TTestSuggestion.TestKinds;
begin
  AssertTrue('dx', SuggestionKind(FOffset, 'dx') = skLength);
  AssertTrue('x', SuggestionKind(FFree, 'x') = skLength);
  AssertTrue('angle', SuggestionKind(FPolar, 'angle') = skAngle);
  AssertTrue('ratio along an edge', SuggestionKind(FAlong, 'value') = skRatio);
  AssertTrue('no such field', SuggestionKind(FOffset, 'radius') = skNone);
end;

// A formula can be swapped for another too, but not one that cannot be worked out
procedure TTestSuggestion.TestNumbersAndFormulas;
begin
  AssertTrue('a number', CanSuggest(FPattern, FOffset, 'dx'));
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dx', '@waist/4'));
  FPattern.Evaluate;
  AssertTrue('a formula', CanSuggest(FPattern, FOffset, 'dx'));
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dx', '@waist/(1 - 1)'));
  FPattern.Evaluate;
  AssertFalse('a formula that fails', CanSuggest(FPattern, FOffset, 'dx'));
  AssertTrue('locked', FPattern.SetLocked(FFree, True));
  AssertFalse('locked', CanSuggest(FPattern, FFree, 'x'));
end;

// Offering the formula the field already has would only repeat it
procedure TTestSuggestion.TestFormulaLeavesItselfOut;
var
  Source: TSuggestionSource;
  Found: string;
begin
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dx', '@waist / 4'));
  FPattern.Evaluate;
  Source := TSuggestionSource.Create(FPattern, FOffset, 'dx');
  try
    Found := Texts(Source.Match(180));
  finally
    FreeAndNil(Source);
  end;
  AssertEquals('itself, however it is spaced', 0, Pos('@waist/4;', Found));
  AssertTrue('the others', Found <> '');
end;

procedure TTestSuggestion.TestTarget;
var
  Value: double;
begin
  AssertTrue('dx', SuggestionTarget(FPattern, FOffset, 'dx', Value));
  AssertNear('dx', 175, Value);
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dx', '2cm'));
  AssertTrue('with a unit', SuggestionTarget(FPattern, FOffset, 'dx', Value));
  AssertNear('with a unit, in mm', 20, Value);
  AssertTrue('angle', SuggestionTarget(FPattern, FPolar, 'angle', Value));
  AssertNear('angle', 0, Value);
  // A formula's value as it works out, in mm
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dx', '@waist/4 + Hem.length'));
  FPattern.Evaluate;
  AssertTrue('a formula', SuggestionTarget(FPattern, FOffset, 'dx', Value));
  AssertNear('a formula', 680, Value);
  FPattern.Units := muCentimetre;
  AssertTrue('in cm', SuggestionTarget(FPattern, FOffset, 'dx', Value));
  AssertNear('still in mm', 680, Value);
end;

procedure TTestSuggestion.TestTargetInPatternUnit;
var
  Value: double;
begin
  FPattern.Units := muCentimetre;
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dx', '18'));
  AssertTrue('dx', SuggestionTarget(FPattern, FOffset, 'dx', Value));
  AssertNear('in mm', 180, Value);
end;

procedure TTestSuggestion.TestQuarterWaistFirst;
var
  Found: TSuggestions;
begin
  Found := Suggested(FOffset, 'dx', 180);
  AssertTrue('some', Length(Found.Items) > 0);
  AssertEquals('first', '@waist/4', Found.Items[0].Text);
  AssertNear('value', 180, Found.Items[0].Value);
  AssertNear('exact', 0, Found.Items[0].Delta);
end;

procedure TTestSuggestion.TestClosestFirst;
var
  Found: TSuggestions;
  Index: integer;
begin
  Found := Suggested(FOffset, 'dx', 179.6);
  AssertEquals('first', '@waist/4', Found.Items[0].Text);
  AssertNear('over by 0.4', 0.4, Found.Items[0].Delta);
  for Index := 1 to High(Found.Items) do
    AssertTrue('not much closer than the one before', Abs(Found.Items[Index].Delta) >= Abs(Found.Items[Index - 1].Delta) - 0.5);
end;

procedure TTestSuggestion.TestWithinTolerance;
var
  Found: TSuggestions;
  Item: TSuggestion;
begin
  Found := Suggested(FOffset, 'dx', 175);
  AssertTrue('some', Length(Found.Items) > 0);
  AssertTrue('at most the limit', Length(Found.Items) <= MAX_SUGGESTIONS);
  for Item in Found.Items do
    AssertTrue(Item.Text + ' within 5 mm', Abs(Item.Delta) <= 5 + 1e-9);
  AssertTrue('a quarter waist is 5 off', Pos('@waist/4;', Texts(Found)) > 0);
end;

procedure TTestSuggestion.TestNothingClose;
var
  Found: TSuggestions;
begin
  Found := Suggested(FPolar, 'length', 100000);
  AssertEquals('none', 0, Length(Found.Items));
  AssertTrue('the nearest', Found.HasNearest);
  AssertTrue('the nearest is short', Found.Nearest.Delta < 0);
end;

procedure TTestSuggestion.TestNegative;
var
  Found: TSuggestions;
begin
  Found := Suggested(FOffset, 'dx', -180);
  AssertEquals('first', '-@waist/4', Found.Items[0].Text);
  AssertNear('value', -180, Found.Items[0].Value);
  Found := Suggested(FOffset, 'dx', -185);
  AssertTrue('brackets round a sum', Pos('-(@waist/4 + 5);', Texts(Found)) > 0);
end;

// Across, a share of a girth comes before a height with an amount added,
// though both land as close
procedure TTestSuggestion.TestDirectionRanks;
var
  Found: string;
begin
  // @hip/4 - 20 and @height_waist/4 - 20 are 220 and 240; @height_waist + ... is not
  FSet.Add('waist_to_hip', 200);
  Found := Texts(Suggested(FOffset, 'dx', 220));
  AssertTrue('a girth share', Pos('@hip/4 - 20;', Found) > 0);
  AssertTrue('a length', Pos('@waist_to_hip + 20;', Found) > 0);
  AssertTrue('the girth first', Pos('@hip/4 - 20;', Found) < Pos('@waist_to_hip + 20;', Found));
  // Down, the other way round
  Found := Texts(Suggested(FOffset, 'dy', 220));
  AssertTrue('the length first', Pos('@waist_to_hip + 20;', Found) < Pos('@hip/4 - 20;', Found));
end;

procedure TTestSuggestion.TestDifference;
begin
  AssertTrue('a difference', Pos('(@hip - @waist)/4;', Texts(Suggested(FOffset, 'dx', 60))) > 0);
  AssertTrue('a whole difference', Pos('@hip - @waist;', Texts(Suggested(FOffset, 'dx', 240))) > 0);
end;

procedure TTestSuggestion.TestAmountAdded;
begin
  AssertTrue('a round amount', Pos('@waist/4 + 30;', Texts(Suggested(FOffset, 'dx', 210))) > 0);
  AssertTrue('a variable', Pos('@waist/4 + #ease;', Texts(Suggested(FOffset, 'dx', 200))) > 0);
  AssertTrue('taken off', Pos('@waist/4 - #ease;', Texts(Suggested(FOffset, 'dx', 160))) > 0);
end;

procedure TTestSuggestion.TestVariable;
begin
  AssertTrue('alone', Pos('#ease;', Texts(Suggested(FOffset, 'dx', 20))) > 0);
  AssertTrue('a share', Pos('#ease/2;', Texts(Suggested(FOffset, 'dx', 10))) > 0);
end;

procedure TTestSuggestion.TestEdgeLength;
begin
  // Hem runs from A to B, 500 mm
  AssertTrue('an edge', Pos('Hem.length/2;', Texts(Suggested(FOffset, 'dx', 250))) > 0);
end;

// A free point's x or y can line up with another point's
procedure TTestSuggestion.TestPointCoordinates;
var
  Loose: TFreePoint;
  Found: TSuggestions;
begin
  Loose := FPattern.AddFreePoint('F', '10', '10');
  FPattern.AddFreePoint('G', '-50', '-20');
  FPattern.Evaluate;
  AssertTrue('across', Pos('B.x;', Texts(Suggested(Loose, 'x', 400))) > 0);
  AssertTrue('down', Pos('C.y;', Texts(Suggested(Loose, 'y', 30))) > 0);
  // A coordinate keeps its sign: a point left of the origin is matched as it is
  Found := Suggested(Loose, 'x', -50);
  AssertTrue('below 0', Pos(';G.x;', ';' + Texts(Found)) > 0);
  AssertEquals('no minus in front', 0, Pos('-G.x', Texts(Found)));
  AssertEquals('not its own', 0, Pos('F.x', Texts(Suggested(Loose, 'x', 10))));
  // Not on an offset's dx, which is not a position
  AssertEquals('only a position', 0, Pos('B.x', Texts(Suggested(FOffset, 'dx', 400))));
end;

// Halfway between two points, the ends of an edge first
procedure TTestSuggestion.TestMidpoints;
var
  Loose: TFreePoint;
  Found: string;
begin
  Loose := FPattern.AddFreePoint('F', '10', '10');
  FPattern.AddFreePoint('G', '225', '0');
  FPattern.Evaluate;
  // Hem runs from A (0, 0) to B (400, 300); C is at (175, 30), G at (225, 0)
  Found := Texts(Suggested(Loose, 'x', 200));
  AssertTrue('across', Pos('(A.x + B.x)/2;', Found) > 0);
  AssertTrue('down', Pos('(A.y + B.y)/2;', Texts(Suggested(Loose, 'y', 150))) > 0);
  // (C.x + G.x)/2 is 200 too, but A and B are the ends of an edge
  AssertTrue('another pair', Pos('(C.x + G.x)/2;', Found) > 0);
  AssertTrue('the edge''s ends first', Pos('(A.x + B.x)/2;', Found) < Pos('(C.x + G.x)/2;', Found));
  // E is on Hem, which ends at B, so B cannot read it
  AssertEquals('leaves out dependents', 0, Pos('E.x', Texts(Suggested(FFree, 'x', 66))));
end;

procedure TTestSuggestion.TestLeavesOutDependents;
begin
  // Hem ends at B, so B cannot read it
  AssertEquals('its own edge', 0, Pos('Hem.', Texts(Suggested(FFree, 'x', 250))));
end;

procedure TTestSuggestion.TestAngles;
var
  Found: TSuggestions;
begin
  Found := Suggested(FPolar, 'angle', 90.4);
  AssertEquals('round', '90', Found.Items[0].Text);
  AssertNear('under', -0.4, Found.Items[0].Delta);
  // Hem is at -36.87°: 90 less is square to it
  AssertTrue('square', Pos('Hem.angle + 90;', Texts(Suggested(FPolar, 'angle', 53.13))) > 0);
  AssertTrue('along', Pos('Hem.angle;', Texts(Suggested(FPolar, 'angle', -36.87))) > 0);
end;

procedure TTestSuggestion.TestAngleWrapsRound;
var
  Found: TSuggestions;
begin
  Found := Suggested(FPolar, 'angle', 359.5);
  AssertEquals('0 is half a degree on', '0', Found.Items[0].Text);
  AssertNear('the short way', 0.5, Found.Items[0].Delta);
end;

procedure TTestSuggestion.TestRatios;
var
  Found: TSuggestions;
begin
  Found := Suggested(FAlong, 'value', 0.33);
  AssertEquals('a third', '1/3', Found.Items[0].Text);
  AssertEquals('no 2/6', 0, Pos('2/6', Texts(Found)));
end;

// A note hanging from an edge sits a share of the way along it (issue #41)
procedure TTestSuggestion.TestNotePositionIsARatio;
var
  Note: TNoteObject;
  Found: TSuggestions;
begin
  Note := FPattern.AddNote('Label', 'Hem', naEdge, FHem.Key, '0.495', '0', '0');
  AssertTrue('added: ' + FPattern.LastError, Assigned(Note));
  FPattern.Evaluate;
  AssertTrue('a ratio', SuggestionKind(Note, 'position') = skRatio);
  AssertTrue('a plain number', CanSuggest(FPattern, Note, 'position'));
  Found := Suggested(Note, 'position', 0.495);
  AssertTrue('some', Length(Found.Items) > 0);
  AssertEquals('a half', '1/2', Found.Items[0].Text);
  AssertTrue('its offset is a length', SuggestionKind(Note, 'dx') = skLength);
end;

procedure TTestSuggestion.TestCentimetres;
var
  Found: TSuggestions;
begin
  FPattern.Units := muCentimetre;
  Found := Suggested(FOffset, 'dx', 190);
  AssertTrue('an amount in cm', Pos('@waist/4 + 1;', Texts(Found)) > 0);
end;

procedure TTestSuggestion.TestTexts;
begin
  AssertEquals('exact', rsSuggestExact, SuggestionDeltaText(0.01, skLength, muMillimetre));
  AssertEquals('over', '+0.4', SuggestionDeltaText(0.4, skLength, muMillimetre));
  AssertEquals('under, in cm', '-0.12', SuggestionDeltaText(-1.2, skLength, muCentimetre));
  AssertEquals('angle', '+0.5', SuggestionDeltaText(0.5, skAngle, muMillimetre));
  AssertEquals('value in cm', '18', SuggestionValueText(180, skLength, muCentimetre));
  AssertEquals('tolerance', '5 mm', SuggestionToleranceText(skLength, muMillimetre));
end;

procedure TTestSuggestion.TestDragField;
var
  Reason: string;
begin
  AssertTrue('dx', DragPointField(FPattern, FOffset, 'dx', Vec2(200, 80), Reason));
  FPattern.Evaluate;
  AssertEquals('dx follows', '200', FPattern.FormulaText(FOffset, 'dx'));
  AssertEquals('dy stays', '30', FPattern.FormulaText(FOffset, 'dy'));
  AssertTrue('y', DragPointField(FPattern, FFree, 'y', Vec2(10, 20), Reason));
  FPattern.Evaluate;
  AssertEquals('x stays', '400', FPattern.FormulaText(FFree, 'x'));
  AssertEquals('y follows', '20', FPattern.FormulaText(FFree, 'y'));
  AssertFalse('not a drag field', DragPointField(FPattern, FOffset, 'length', Vec2(0, 0), Reason));
end;

procedure TTestSuggestion.TestDragPolarLength;
var
  Reason: string;
begin
  // Along the angle, whatever the sideways part
  AssertTrue('length', DragPointField(FPattern, FPolar, 'length', Vec2(150, 40), Reason));
  FPattern.Evaluate;
  AssertEquals('length', '150', FPattern.FormulaText(FPolar, 'length'));
  AssertEquals('angle stays', '0', FPattern.FormulaText(FPolar, 'angle'));
end;

procedure TTestSuggestion.TestDragPolarAngle;
var
  Reason: string;
begin
  AssertTrue('angle', DragPointField(FPattern, FPolar, 'angle', Vec2(0, -300), Reason));
  FPattern.Evaluate;
  AssertEquals('angle', '90', FPattern.FormulaText(FPolar, 'angle'));
  AssertEquals('length stays', '100', FPattern.FormulaText(FPolar, 'length'));
end;

procedure TTestSuggestion.TestDragFieldOtherIsFormula;
var
  Reason: string;
begin
  AssertTrue('set', FPattern.SetFormula(FOffset, 'dy', '@waist/10'));
  FPattern.Evaluate;
  AssertFalse('a whole drag is refused', CanDrag(FPattern, FOffset, Reason));
  AssertTrue('the plain field can be dragged', DragPointField(FPattern, FOffset, 'dx', Vec2(120, 0), Reason));
  AssertEquals('the other keeps its formula', '@waist/10', FPattern.FormulaText(FOffset, 'dy'));
end;

// With suggestions open on a formula field, a drag puts a plain number in
// place of the formula, so a better one can be found by moving the point
procedure TTestSuggestion.TestDragFormulaField;
var
  Reason: string;
begin
  AssertTrue('set dy', FPattern.SetFormula(FOffset, 'dy', '@waist/10'));
  AssertTrue('set x', FPattern.SetFormula(FFree, 'x', '@waist/2'));
  AssertTrue('set value', FPattern.SetFormula(FAlong, 'value', '1/3'));
  FPattern.Evaluate;
  AssertTrue('can', CanDragField(FPattern, FOffset, 'dy', Reason));
  AssertTrue('an offset', DragPointField(FPattern, FOffset, 'dy', Vec2(0, 50), Reason));
  AssertEquals('a number', '50', FPattern.FormulaText(FOffset, 'dy'));
  AssertEquals('the other field is kept', '175', FPattern.FormulaText(FOffset, 'dx'));
  AssertTrue('a free point', DragPointField(FPattern, FFree, 'y', Vec2(0, 320), Reason));
  AssertEquals('its y', '320', FPattern.FormulaText(FFree, 'y'));
  AssertEquals('its x keeps the formula', '@waist/2', FPattern.FormulaText(FFree, 'x'));
  FPattern.Evaluate;
  AssertTrue('along an edge', DragPointField(FPattern, FAlong, 'value', FHem.PointAtLength(FHem.Length / 2), Reason));
  AssertEquals('a ratio', '0.5', FPattern.FormulaText(FAlong, 'value'));
  // A whole drag still leaves formulas alone
  AssertFalse('a whole drag', CanDrag(FPattern, FFree, Reason));
end;

procedure TTestSuggestion.TestFieldPosition;
var
  Position: TVec2;
begin
  AssertTrue('dx', FieldPosition(FPattern, FOffset, 'dx', 180, Position));
  AssertPointsNear('dx', Vec2(180, 30), Position);
  AssertTrue('angle', FieldPosition(FPattern, FPolar, 'angle', 90, Position));
  AssertPointsNear('angle', Vec2(0, -100), Position);
  AssertTrue('length', FieldPosition(FPattern, FPolar, 'length', 50, Position));
  AssertPointsNear('length', Vec2(50, 0), Position);
  AssertTrue('ratio', FieldPosition(FPattern, FAlong, 'value', 0.5, Position));
  AssertPointsNear('ratio', Vec2(200, 150), Position);
end;

procedure TTestSuggestion.TestFieldGuide;
var
  Guide: TFieldGuide;
begin
  Guide := FieldGuide(FPattern, FOffset, 'dx');
  AssertTrue('a line', Guide.Kind = fgLine);
  AssertNear('across', 0, Guide.Finish.Y - Guide.Start.Y);
  Guide := FieldGuide(FPattern, FPolar, 'angle');
  AssertTrue('a circle', Guide.Kind = fgCircle);
  AssertNear('round the base', 100, Guide.Radius);
  Guide := FieldGuide(FPattern, FAlong, 'value');
  AssertTrue('the edge is drawn', Guide.Kind = fgNone);
end;

procedure TTestSuggestion.TestEvaluateText;
var
  Value: double;
begin
  AssertTrue('a measurement', FPattern.EvaluateText('@waist/4', Value));
  AssertNear('a measurement', 180, Value);
  AssertTrue('an edge', FPattern.EvaluateText('Hem.length + #ease', Value));
  AssertNear('an edge', 520, Value);
  AssertFalse('no such name', FPattern.EvaluateText('@nothing', Value));
  AssertTrue('a reason', FPattern.LastError <> '');
end;

procedure TTestSuggestion.TestGradeNeedsSizes;
var
  Grade: TGradeCheck;
begin
  Grade := TGradeCheck.Create(FPattern, FOffset, 'dx');
  try
    AssertFalse('one size', Grade.Available);
    AssertEquals('no ghosts', 0, Length(Grade.Ghosts('@waist/4')));
  finally
    FreeAndNil(Grade);
  end;
end;

// Sizes S, M and L, the waist 40 mm apart, and the hip missing at L; M is shown
procedure AddSizes(MeasurementSet: TMeasurementSet);
var
  Waist: TMeasurement;
begin
  MeasurementSet.AddSize('S');
  MeasurementSet.AddSize('M');
  MeasurementSet.AddSize('L');
  Waist := MeasurementSet.Find('waist');
  Waist.SetValueFor(0, 680);
  Waist.SetValueFor(1, 720);
  Waist.SetValueFor(2, 760);
  MeasurementSet.Find('hip').SetValueFor(1, 960);
  MeasurementSet.SelectSize('M');
end;

procedure TTestSuggestion.TestGradeValues;
var
  Grade: TGradeCheck;
  Values: TSizeValues;
begin
  AddSizes(FSet);
  FPattern.Evaluate;
  Grade := TGradeCheck.Create(FPattern, FOffset, 'dx');
  try
    AssertTrue('sizes', Grade.Available);
    AssertEquals('three', 3, Grade.SizeCount);
    Values := Grade.Values('@waist/4');
    AssertNear('S', 170, Values[0]);
    AssertNear('M', 180, Values[1]);
    AssertNear('L', 190, Values[2]);
    AssertEquals('range', '170–190', SizeRangeText(Values, skLength, muMillimetre));
    AssertEquals('each size', 'S: 170, M: 180, L: 190', SizeValuesText(Grade, Values, skLength, muMillimetre));
    // The hip has no value at L: the first size took the set's values
    Values := Grade.Values('@hip/4');
    AssertNear('M', 240, Values[1]);
    AssertTrue('missing at L', IsNan(Values[2]));
    AssertEquals('no range', '', SizeRangeText(Values, skLength, muMillimetre));
  finally
    FreeAndNil(Grade);
  end;
  AssertEquals('the pattern keeps its size', 'M', FSet.SizeName);
end;

procedure TTestSuggestion.TestGradeGhosts;
var
  Grade: TGradeCheck;
  Ghosts: TGradeGhostArray;
begin
  AddSizes(FSet);
  FPattern.AddLine(FOffset.Key, FFree.Key, erOutline, 'Side');
  FPattern.Evaluate;
  Grade := TGradeCheck.Create(FPattern, FOffset, 'dx');
  try
    Ghosts := Grade.Ghosts('@waist/4');
    AssertEquals('smallest and largest', 2, Length(Ghosts));
    AssertTrue('a point', Ghosts[0].HasPoint);
    AssertPointsNear('smallest', Vec2(170, 30), Ghosts[0].Point);
    AssertPointsNear('largest', Vec2(190, 30), Ghosts[1].Point);
    AssertEquals('the edge it ends', 1, Length(Ghosts[1].Lines));
    AssertPointsNear('the edge starts there', Vec2(190, 30), Ghosts[1].Lines[0][0]);
    // The copy is put back each time
    Ghosts := Grade.Ghosts('@waist/8');
    AssertPointsNear('again', Vec2(85, 30), Ghosts[0].Point);
  finally
    FreeAndNil(Grade);
  end;
  AssertEquals('the pattern is not changed', '175', FPattern.FormulaText(FOffset, 'dx'));
  AssertPointsNear('nor its geometry', Vec2(175, 30), FOffset.Position);
end;

initialization
  RegisterTest(TTestSuggestion);
end.
