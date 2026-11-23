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

// Formula suggestions: formulas whose value is close to a field that holds a
// plain number, such as @waist/4 for a dx of 175 mm. A brute-force search over
// a few shapes of formula, ranked by how close each lands and how simple it
// is. Kept free of the LCL so it can be unit-tested.
unit Sloper.Editor.Suggestion;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Evaluator, Sloper.Core.Pattern, Sloper.Core.Units;

type
  // What a field holds, for what can be suggested: none for a count or text
  TSuggestionKind = (skNone, skLength, skAngle, skRatio);

  TSuggestion = record
    // In display form, as the user would type it
    Text: string;
    // As the field works it out: mm for a length, degrees, or a ratio
    Value: double;
    // Value less the field's value; for an angle, the shortest turn
    Delta: double;
  end;
  TSuggestionArray = array of TSuggestion;

  TSuggestions = record
    // Within the tolerance, best first
    Items: TSuggestionArray;
    // The closest of all, for when nothing is within the tolerance
    Nearest: TSuggestion;
    HasNearest: boolean;
  end;

  // A candidate before it is matched: its value does not depend on the field,
  // since formulas reading the field's object are left out, so a source is
  // built once and matched as the field's value changes
  TCandidate = record
    Text: string;
    Value: double;
    // Lower is simpler and more likely what was meant
    Cost: double;
    // Has an operator outside brackets, so a minus in front needs them
    Compound: boolean;
    // A position, such as B.x, matched with its own sign: a length below 0
    // does not put a minus in front of it
    Signed: boolean;
  end;
  TCandidateArray = array of TCandidate;

  // Every candidate formula for one field of one object
  TSuggestionSource = class
  private
    FKind: TSuggestionKind;
    FCandidates: TCandidateArray;
    FCount: integer;
    FUnits: TMeasureUnit;
    // The formula the field holds, as FormulaKey gives it, which is left out;
    // empty for a plain number
    FCurrent: string;
    procedure Add(const Text: string; Value, Cost: double; Compound: boolean = False; Signed: boolean = False);
    procedure AddPositions(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
    procedure AddLengths(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
    procedure AddAngles(Pattern: TPattern; Node: TEvalNode);
    procedure AddRatios;
  public
    constructor Create(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
    // The candidates close to Target, best first, and the nearest of all
    function Match(Target: double): TSuggestions;
    property Kind: TSuggestionKind read FKind;
    property Count: integer read FCount;
  end;

// What can be suggested for the field
function SuggestionKind(Node: TEvalNode; const FieldName: string): TSuggestionKind;
// True when a suggestion could replace what the field holds, a plain number
// or a formula that works out, and its object can be edited
function CanSuggest(Pattern: TPattern; Node: TEvalNode; const FieldName: string): boolean;
// What the field holds, as the field works it out: mm, degrees or a ratio. A
// formula is worked out with the pattern as last evaluated; False when it
// cannot be.
function SuggestionTarget(Pattern: TPattern; Node: TEvalNode; const FieldName: string; out Value: double): boolean;
// How far a suggestion may be from the field's value: mm, degrees or a ratio
function SuggestionTolerance(Kind: TSuggestionKind): double;
// For the list: a value in the pattern's unit, and how far off it is
// ("exact", "+0.4", "-1.2")
function SuggestionValueText(Value: double; Kind: TSuggestionKind; Units: TMeasureUnit): string;
function SuggestionDeltaText(Delta: double; Kind: TSuggestionKind; Units: TMeasureUnit): string;
// "5 mm", "1°", for the line shown when nothing is close
function SuggestionToleranceText(Kind: TSuggestionKind; Units: TMeasureUnit): string;
// The objects the formulas read, such as B for B.x, in the order first read:
// what the canvas labels while the suggestions show, so their names can be
// found on it. A formula that does not parse adds nothing.
function SuggestionObjectKeys(Pattern: TPattern; const Formulas: array of string): TStringArray;

const
  // The most suggestions a match gives
  MAX_SUGGESTIONS = 30;

resourcestring
  rsSuggestExact = 'exact';
  rsSuggestDegrees = '%s°';

implementation

uses
  Math, Generics.Collections, Sloper.Core.EvalTypes, Sloper.Core.Formula, Sloper.Core.Draft, Sloper.Core.Drag,
  Sloper.Core.JSON, Sloper.Core.Note, Sloper.Core.Measurements, Sloper.Core.Variables;

const
  LENGTH_TOLERANCE = 5; // mm
  ANGLE_TOLERANCE = 1; // degrees
  RATIO_TOLERANCE = 0.01;
  // Closeness is ranked in steps of this share of the tolerance, and
  // suggestions in the same step by how simple they are
  CLOSENESS_STEPS = 10;
  DIVISORS: array[0..8] of integer = (1, 2, 3, 4, 6, 8, 10, 12, 16);
  RATIO_DENOMINATORS: array[0..8] of integer = (2, 3, 4, 5, 6, 8, 10, 12, 16);
  // Round amounts added to a share of a measurement, in each unit
  ROUND_AMOUNTS: array[TMeasureUnit, 0..7] of double = (
    (5, 10, 15, 20, 25, 30, 40, 50),
    (0.5, 1, 1.5, 2, 2.5, 3, 4, 5),
    (0.125, 0.25, 0.375, 0.5, 0.75, 1, 1.5, 2));
  QUARTER_TURN = 90;
  HALF_TURN = 180;
  FULL_TURN = 360;
  ROUND_ANGLE_STEP = 45;
  // Decimals shown for an angle and a ratio
  ANGLE_DECIMALS = 1;
  RATIO_DECIMALS = 3;

  // What each part of a formula adds to its cost
  COST_MEASUREMENT = 1;
  COST_VARIABLE = 1;
  COST_EDGE = 1.5;
  COST_POINT = 1;
  COST_MIDPOINT = 2;
  COST_DIFFERENCE = 2.5;
  COST_DIVISOR = 1;
  COST_ROUND_AMOUNT = 1.5;
  COST_VARIABLE_AMOUNT = 1;
  COST_ROUND_ANGLE = 0.5;
  COST_EDGE_ANGLE = 1;
  COST_TURNED_ANGLE = 1.5;
  COST_RATIO = 1;
  COST_FINE_RATIO = 0.5;
  // Taken off for a measurement that suits the field's direction (and added
  // for one that runs the other way), a circumference shared four ways
  // across, and one the pattern already uses
  RELEVANT_DIRECTION = 0.5;
  RELEVANT_QUARTER = 0.25;
  RELEVANT_USED = 0.3;
  // Taken off a point halfway between the ends of an edge
  RELEVANT_EDGE_ENDS = 0.5;
  MIDPOINT_DIVISOR = 2;
  FINE_RATIO_DENOMINATOR = 4;
  QUARTER = 4;
  // Far enough that no candidate is nearer
  NO_DISTANCE = 1e300;

type
  TFieldDirection = (fdAcross, fdDown, fdOther);
  TKeySet = specialize THashSet<string>;

  // The field's literal is worked out without a pattern: only its suffix
  // needs the unit
  TLiteralContext = class(TFormulaContext)
  private
    FUnits: TMeasureUnit;
  public
    constructor Create(AUnits: TMeasureUnit);
    function MeasurementValue(const Key: string; out Value: double): boolean; override;
    function VariableValue(const Id: string; out Value: double): boolean; override;
    function PropertyValue(const ObjectId, Prop: string; out Value: double): boolean; override;
    function LengthScale: double; override;
  end;

constructor TLiteralContext.Create(AUnits: TMeasureUnit);
begin
  inherited Create;
  FUnits := AUnits;
end;

function TLiteralContext.MeasurementValue(const Key: string; out Value: double): boolean;
begin
  Value := 0;
  Result := False;
end;

function TLiteralContext.VariableValue(const Id: string; out Value: double): boolean;
begin
  Value := 0;
  Result := False;
end;

function TLiteralContext.PropertyValue(const ObjectId, Prop: string; out Value: double): boolean;
begin
  Value := 0;
  Result := False;
end;

function TLiteralContext.LengthScale: double;
begin
  Result := MILLIMETRES_PER_UNIT[FUnits];
end;

function SuggestionKind(Node: TEvalNode; const FieldName: string): TSuggestionKind;
begin
  Result := skNone;
  if not (Node is TDraftObject) or not Assigned(Node.Field(FieldName)) then
    Exit;
  case Node.FieldUnitKind(FieldName) of
    fkLength: Result := skLength;
    fkAngle: Result := skAngle;
    fkNumber:
      // Only the ratio along an edge or between points, and where a note
      // hangs along its edge, is a share; other plain numbers are counts
      if ((FieldName = 'value') and ((Node is TAlongEdgePoint) or (Node is TBetweenPoint))) or
        ((FieldName = NOTE_POSITION_FIELD) and (Node is TNoteObject)) then
        Result := skRatio;
  end;
end;

function CanSuggest(Pattern: TPattern; Node: TEvalNode; const FieldName: string): boolean;
var
  Value: double;
begin
  Result := Assigned(Node) and (SuggestionKind(Node, FieldName) <> skNone) and not Pattern.IsLocked(Node) and
    SuggestionTarget(Pattern, Node, FieldName, Value);
end;

function SuggestionTarget(Pattern: TPattern; Node: TEvalNode; const FieldName: string; out Value: double): boolean;
var
  Context: TLiteralContext;
begin
  Value := 0;
  if not Assigned(Node) or not Assigned(Node.Field(FieldName)) or not Node.Field(FieldName).Valid then
    Exit(False);
  if Node.Field(FieldName).IsLiteral then
  begin
    Context := TLiteralContext.Create(Pattern.Units);
    try
      Result := Node.Field(FieldName).Evaluate(Context, Value);
    finally
      FreeAndNil(Context);
    end;
  end
  else
    Result := Pattern.EvaluateText(Pattern.FormulaText(Node, FieldName), Value) and not IsNan(Value) and not IsInfinite(Value);
  if Result and (SuggestionKind(Node, FieldName) = skLength) then
    Value := Value * MILLIMETRES_PER_UNIT[Pattern.Units];
end;

function SuggestionTolerance(Kind: TSuggestionKind): double;
begin
  case Kind of
    skAngle: Result := ANGLE_TOLERANCE;
    skRatio: Result := RATIO_TOLERANCE;
    else
      Result := LENGTH_TOLERANCE;
  end;
end;

function SuggestionValueText(Value: double; Kind: TSuggestionKind; Units: TMeasureUnit): string;
begin
  case Kind of
    skAngle: Result := Format(rsSuggestDegrees, [RoundedText(Value, ANGLE_DECIMALS)]);
    skRatio: Result := RoundedText(Value, RATIO_DECIMALS);
    else
      Result := FormatLength(Value, Units);
  end;
end;

function SuggestionDeltaText(Delta: double; Kind: TSuggestionKind; Units: TMeasureUnit): string;
begin
  case Kind of
    skAngle: Result := RoundedText(Delta, ANGLE_DECIMALS);
    skRatio: Result := RoundedText(Delta, RATIO_DECIMALS);
    else
      Result := FormatLength(Delta, Units);
  end;
  if (Result = '0') or (Result = '-0') then
    Result := rsSuggestExact
  else if Result[1] <> '-' then
    Result := '+' + Result;
end;

function SuggestionToleranceText(Kind: TSuggestionKind; Units: TMeasureUnit): string;
begin
  case Kind of
    skAngle: Result := Format(rsSuggestDegrees, [RoundedText(ANGLE_TOLERANCE, ANGLE_DECIMALS)]);
    skRatio: Result := RoundedText(RATIO_TOLERANCE, RATIO_DECIMALS);
    else
      Result := LengthWithUnit(LENGTH_TOLERANCE, Units);
  end;
end;

function SuggestionObjectKeys(Pattern: TPattern; const Formulas: array of string): TStringArray;
var
  Formula: TFormula;
  Seen: TKeySet;
  Text, Key: string;
  Ref: TFormulaReference;
  Count: integer;
begin
  Result := nil;
  Count := 0;
  Seen := TKeySet.Create;
  Formula := TFormula.Create;
  try
    for Text in Formulas do
    begin
      if not Formula.Parse(Text, Pattern.Resolver) then
        Continue;
      for Ref in Formula.References do
      begin
        Key := ReferenceKey(Ref);
        if (Ref.Kind <> rkObject) or not Seen.Add(Key) then
          Continue;
        if Count = Length(Result) then
          SetLength(Result, Max(8, 2 * Count));
        Result[Count] := Key;
        Inc(Count);
      end;
    end;
  finally
    FreeAndNil(Formula);
    FreeAndNil(Seen);
  end;
  SetLength(Result, Count);
end;

// Which way a length field runs on the page, for which measurements suit it
function FieldDirection(const FieldName: string): TFieldDirection;
begin
  if (FieldName = 'x') or (FieldName = 'dx') then
    Result := fdAcross
  else if (FieldName = 'y') or (FieldName = 'dy') then
    Result := fdDown
  else
    Result := fdOther;
end;

// Measurements are named in words: circumferences, arcs and widths run across
// the body, heights and lengths down it
function MeasurementDirection(const Key: string): TFieldDirection;
var
  Lower: string;
begin
  Lower := LowerCase(Key);
  if (Pos('circ', Lower) > 0) or (Pos('arc', Lower) > 0) or (Pos('width', Lower) > 0) or (Pos('across', Lower) > 0) or
    (Pos('separation', Lower) > 0) then
    Result := fdAcross
  else if (Pos('height', Lower) > 0) or (Pos('length', Lower) > 0) or (Pos('_to_', Lower) > 0) or (Pos('rise', Lower) > 0) or
    (Pos('inside_leg', Lower) > 0) then
    Result := fdDown
  // Short keys such as waist and hip are girths
  else if (Pos('waist', Lower) = 1) or (Pos('hip', Lower) = 1) or (Pos('bust', Lower) = 1) or (Pos('neck', Lower) = 1) then
    Result := fdAcross
  else
    Result := fdOther;
end;

function IsCircumference(const Key: string): boolean;
begin
  Result := MeasurementDirection(Key) = fdAcross;
end;

function CommonDivisor(First, Second: integer): integer;
var
  Rest: integer;
begin
  while Second <> 0 do
  begin
    Rest := First mod Second;
    First := Second;
    Second := Rest;
  end;
  Result := First;
end;

// Measurement keys any formula in the pattern reads, in lower case
function UsedMeasurements(Pattern: TPattern): TKeySet;
var
  Node: TEvalNode;
  Index: integer;
  Ref: TFormulaReference;
begin
  Result := TKeySet.Create;
  try
    for Node in Pattern.AllNodes do
      for Index := 0 to Node.FieldCount - 1 do
        for Ref in Node.Fields[Index].Formula.References do
          if Ref.Kind = rkMeasurement then
            Result.Add(LowerCase(Ref.Id));
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// What a formula for Node may read of Other: neither itself nor anything
// that reads it, which would go round in a circle
function MayRead(Pattern: TPattern; Node: TEvalNode; Other: TDraftObject): boolean;
begin
  Result := (Other <> Node) and (Other.State = esValid) and Other.HasResult and not Pattern.Reaches(Other, Node);
end;

function DivisorText(Divisor: integer): string;
begin
  if Divisor = 1 then
    Result := ''
  else
    Result := '/' + IntToStr(Divisor);
end;

function DivisorCost(Divisor: integer): double;
begin
  if Divisor = 1 then
    Result := 0
  else
    Result := COST_DIVISOR;
end;

// Formula text to compare, whatever its spacing and case
function FormulaKey(const Text: string): string;
begin
  Result := LowerCase(StringReplace(Text, ' ', '', [rfReplaceAll]));
end;

{ TSuggestionSource }

constructor TSuggestionSource.Create(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
begin
  inherited Create;
  FUnits := Pattern.Units;
  FKind := SuggestionKind(Node, FieldName);
  if Assigned(Node.Field(FieldName)) and not Node.Field(FieldName).IsLiteral then
    FCurrent := FormulaKey(Pattern.FormulaText(Node, FieldName));
  case FKind of
    skLength: AddLengths(Pattern, Node, FieldName);
    skAngle: AddAngles(Pattern, Node);
    skRatio: AddRatios;
  end;
end;

procedure TSuggestionSource.Add(const Text: string; Value, Cost: double; Compound, Signed: boolean);
begin
  if FCount = Length(FCandidates) then
    SetLength(FCandidates, Max(64, 2 * FCount));
  FCandidates[FCount].Text := Text;
  FCandidates[FCount].Value := Value;
  FCandidates[FCount].Cost := Cost;
  FCandidates[FCount].Compound := Compound;
  FCandidates[FCount].Signed := Signed;
  Inc(FCount);
end;

// For a free point's x or y: another point's, such as B.x, and halfway
// between two points, such as (B.x + C.x)/2, the ends of an edge first. Values
// are mm, as the points' positions are.
procedure TSuggestionSource.AddPositions(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
var
  Points: array of TDraftObject;
  EdgeEnds: TKeySet;
  Other: TDraftObject;
  Index, First, Second, PointCount: integer;
  Cost: double;
begin
  if not (Node is TFreePoint) or ((FieldName <> 'x') and (FieldName <> 'y')) then
    Exit;
  SetLength(Points, Pattern.ObjectCount);
  PointCount := 0;
  EdgeEnds := TKeySet.Create;
  try
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      Other := Pattern.Objects[Index];
      if Other is TEdgeObject then
      begin
        EdgeEnds.Add(TEdgeObject(Other).StartKey + ' ' + TEdgeObject(Other).EndKey);
        EdgeEnds.Add(TEdgeObject(Other).EndKey + ' ' + TEdgeObject(Other).StartKey);
      end
      else if (Other is TPointObject) and MayRead(Pattern, Node, Other) then
      begin
        Points[PointCount] := Other;
        Inc(PointCount);
      end;
    end;
    SetLength(Points, PointCount);
    for First := 0 to High(Points) do
    begin
      Add(Points[First].DisplayName + '.' + FieldName, Points[First].PropertyValue(FieldName), COST_POINT, False, True);
      for Second := First + 1 to High(Points) do
      begin
        // Halfway between two points level with each other is either of them
        if SameValue(Points[First].PropertyValue(FieldName), Points[Second].PropertyValue(FieldName)) then
          Continue;
        Cost := COST_MIDPOINT;
        if EdgeEnds.Contains(Points[First].Key + ' ' + Points[Second].Key) then
          Cost := Cost - RELEVANT_EDGE_ENDS;
        Add('(' + Points[First].DisplayName + '.' + FieldName + ' + ' + Points[Second].DisplayName + '.' + FieldName + ')/' +
          IntToStr(MIDPOINT_DIVISOR), (Points[First].PropertyValue(FieldName) + Points[Second].PropertyValue(FieldName)) /
          MIDPOINT_DIVISOR, Cost, False, True);
      end;
    end;
  finally
    FreeAndNil(EdgeEnds);
  end;
end;

// Shares of measurements, of a measurement less another, of variables and of
// other edges' lengths, and a share of a measurement with a round amount or
// a variable added or taken off. Values are mm; formulas read the pattern unit.
procedure TSuggestionSource.AddLengths(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
type
  TTerm = record
    Text: string;
    Value, Cost: double;
  end;
var
  Scale: double;
  Direction: TFieldDirection;
  Used: TKeySet;
  Terms: array of TTerm;
  Amounts: array of TTerm;

  procedure AddTerm(var List: array of TTerm; var Count: integer; const Text: string; Value, Cost: double);
  begin
    List[Count].Text := Text;
    List[Count].Value := Value;
    List[Count].Cost := Cost;
    Inc(Count);
  end;

  function MeasurementCost(const Key: string): double;
  begin
    Result := COST_MEASUREMENT;
    // Suiting the field's direction counts for it, running the other way against it
    if (Direction <> fdOther) and (MeasurementDirection(Key) = Direction) then
      Result := Result - RELEVANT_DIRECTION
    else if (Direction <> fdOther) and (MeasurementDirection(Key) <> fdOther) then
      Result := Result + RELEVANT_DIRECTION;
    if Used.Contains(LowerCase(Key)) then
      Result := Result - RELEVANT_USED;
  end;

  procedure AddMeasurements;
  var
    First, Second: TMeasurement;
    FirstIndex, SecondIndex, Count: integer;
    Divisor: integer;
    Cost: double;
  begin
    if not Assigned(Pattern.Measurements) then
      Exit;
    SetLength(Terms, Pattern.Measurements.Count);
    Count := 0;
    for FirstIndex := 0 to Pattern.Measurements.Count - 1 do
    begin
      First := Pattern.Measurements[FirstIndex];
      if First.HasValue and (First.Value > 0) then
        AddTerm(Terms, Count, '@' + First.Key, First.Value * Pattern.MeasurementScale, MeasurementCost(First.Key));
    end;
    SetLength(Terms, Count);
    for FirstIndex := 0 to High(Terms) do
      for Divisor in DIVISORS do
      begin
        Cost := Terms[FirstIndex].Cost + DivisorCost(Divisor);
        if (Divisor = QUARTER) and (Direction = fdAcross) and IsCircumference(Copy(Terms[FirstIndex].Text, 2, MaxInt)) then
          Cost := Cost - RELEVANT_QUARTER;
        Add(Terms[FirstIndex].Text + DivisorText(Divisor), Terms[FirstIndex].Value / Divisor, Cost);
      end;
    // A difference such as (@hip - @waist)/4, the larger first
    for FirstIndex := 0 to Pattern.Measurements.Count - 1 do
      for SecondIndex := 0 to Pattern.Measurements.Count - 1 do
      begin
        First := Pattern.Measurements[FirstIndex];
        Second := Pattern.Measurements[SecondIndex];
        if (FirstIndex = SecondIndex) or not First.HasValue or not Second.HasValue or (First.Value <= Second.Value) or (Second.Value <= 0) then
          Continue;
        for Divisor in DIVISORS do
          if Divisor = 1 then
            Add('@' + First.Key + ' - @' + Second.Key, (First.Value - Second.Value) * Pattern.MeasurementScale,
              COST_DIFFERENCE, True)
          else
            Add('(@' + First.Key + ' - @' + Second.Key + ')' + DivisorText(Divisor),
              (First.Value - Second.Value) * Pattern.MeasurementScale / Divisor, COST_DIFFERENCE + COST_DIVISOR);
      end;
  end;

  // Round amounts and variables added to or taken off a share of a measurement
  procedure AddAmounts;
  var
    Count, Index, TermIndex: integer;
    Amount: double;
    Variable: TVariable;
    Divisor: integer;
    Base: TTerm;
  begin
    SetLength(Amounts, Length(ROUND_AMOUNTS[FUnits]) + Pattern.VariableCount);
    Count := 0;
    for Amount in ROUND_AMOUNTS[FUnits] do
      AddTerm(Amounts, Count, FormatJSONFloat(Amount), Amount * Scale, COST_ROUND_AMOUNT);
    for Index := 0 to Pattern.VariableCount - 1 do
    begin
      Variable := Pattern.Variables[Index];
      if (Variable.State = esValid) and (Variable.Value > 0) then
        AddTerm(Amounts, Count, '#' + Variable.Name, Variable.Value * Scale, COST_VARIABLE_AMOUNT);
    end;
    SetLength(Amounts, Count);
    for TermIndex := 0 to High(Terms) do
      for Divisor in DIVISORS do
      begin
        Base := Terms[TermIndex];
        for Index := 0 to High(Amounts) do
        begin
          Add(Base.Text + DivisorText(Divisor) + ' + ' + Amounts[Index].Text, Base.Value / Divisor + Amounts[Index].Value,
            Base.Cost + DivisorCost(Divisor) + Amounts[Index].Cost, True);
          if Base.Value / Divisor > Amounts[Index].Value then
            Add(Base.Text + DivisorText(Divisor) + ' - ' + Amounts[Index].Text, Base.Value / Divisor - Amounts[Index].Value,
              Base.Cost + DivisorCost(Divisor) + Amounts[Index].Cost, True);
        end;
      end;
  end;

  procedure AddVariables;
  var
    Index: integer;
    Divisor: integer;
    Variable: TVariable;
  begin
    for Index := 0 to Pattern.VariableCount - 1 do
    begin
      Variable := Pattern.Variables[Index];
      if (Variable.State = esValid) and (Variable.Value > 0) then
        for Divisor in DIVISORS do
          Add('#' + Variable.Name + DivisorText(Divisor), Variable.Value * Scale / Divisor, COST_VARIABLE + DivisorCost(Divisor));
    end;
  end;

  procedure AddEdges;
  var
    Index: integer;
    Divisor: integer;
    Other: TDraftObject;
  begin
    for Index := 0 to Pattern.ObjectCount - 1 do
    begin
      Other := Pattern.Objects[Index];
      if not (Other is TEdgeObject) or not Other.HasProperty('length') or not MayRead(Pattern, Node, Other) then
        Continue;
      if Other.PropertyValue('length') <= 0 then
        Continue;
      for Divisor in DIVISORS do
        Add(Other.DisplayName + '.length' + DivisorText(Divisor), Other.PropertyValue('length') / Divisor,
          COST_EDGE + DivisorCost(Divisor));
    end;
  end;

begin
  Scale := MILLIMETRES_PER_UNIT[FUnits];
  Direction := FieldDirection(FieldName);
  Used := UsedMeasurements(Pattern);
  try
    AddMeasurements;
    AddAmounts;
    AddVariables;
    AddEdges;
    AddPositions(Pattern, Node, FieldName);
  finally
    FreeAndNil(Used);
  end;
end;

// Round angles, and along, square to or back along a straight edge
procedure TSuggestionSource.AddAngles(Pattern: TPattern; Node: TEvalNode);
var
  Angle, Index: integer;
  Other: TDraftObject;
  Name: string;
  EdgeAngle: double;
begin
  Angle := 0;
  while Angle < FULL_TURN do
  begin
    Add(IntToStr(Angle), Angle, COST_ROUND_ANGLE);
    Inc(Angle, ROUND_ANGLE_STEP);
  end;
  for Index := 0 to Pattern.ObjectCount - 1 do
  begin
    Other := Pattern.Objects[Index];
    if not (Other is TEdgeObject) or not Other.HasProperty('angle') or not MayRead(Pattern, Node, Other) then
      Continue;
    Name := Other.DisplayName + '.angle';
    EdgeAngle := Other.PropertyValue('angle');
    Add(Name, EdgeAngle, COST_EDGE_ANGLE);
    Add(Name + ' + ' + IntToStr(QUARTER_TURN), EdgeAngle + QUARTER_TURN, COST_TURNED_ANGLE, True);
    Add(Name + ' - ' + IntToStr(QUARTER_TURN), EdgeAngle - QUARTER_TURN, COST_TURNED_ANGLE, True);
    Add(Name + ' + ' + IntToStr(HALF_TURN), EdgeAngle + HALF_TURN, COST_TURNED_ANGLE, True);
  end;
end;

// Fractions in their lowest terms: 1/2, 1/3, 2/3, 1/4 ...
procedure TSuggestionSource.AddRatios;
var
  Denominator, Numerator: integer;
  Cost: double;
begin
  for Denominator in RATIO_DENOMINATORS do
    for Numerator := 1 to Denominator - 1 do
      if CommonDivisor(Numerator, Denominator) = 1 then
      begin
        Cost := COST_RATIO;
        if Denominator > FINE_RATIO_DENOMINATOR then
          Cost := Cost + COST_FINE_RATIO;
        Add(IntToStr(Numerator) + '/' + IntToStr(Denominator), Numerator / Denominator, Cost);
      end;
end;

// Angles differ by the shortest turn
function Difference(Value, Target: double; Kind: TSuggestionKind): double;
begin
  Result := Value - Target;
  if Kind = skAngle then
  begin
    Result := Result - FULL_TURN * Floor(Result / FULL_TURN);
    if Result > HALF_TURN then
      Result := Result - FULL_TURN;
  end;
end;

function TSuggestionSource.Match(Target: double): TSuggestions;
var
  Tolerance, Step, Delta, NearestDistance: double;
  Negative: boolean;
  Index, Found: integer;
  Steps: array of integer;
  Order: array of integer;

// A length below 0 is matched by the candidates with a minus in front
  function CandidateText(CandidateIndex: integer): string;
  begin
    Result := FCandidates[CandidateIndex].Text;
    if FCandidates[CandidateIndex].Signed then
      Exit;
    if Negative and FCandidates[CandidateIndex].Compound then
      Result := '-(' + Result + ')'
    else if Negative then
      Result := '-' + Result;
  end;

  function CandidateValue(CandidateIndex: integer): double;
  begin
    Result := FCandidates[CandidateIndex].Value;
    if Negative and not FCandidates[CandidateIndex].Signed then
      Result := -Result;
  end;

  // By closeness step, then by cost, then the shorter text
  function Before(First, Second: integer): boolean;
  begin
    if Steps[First] <> Steps[Second] then
      Exit(Steps[First] < Steps[Second]);
    if not SameValue(FCandidates[Order[First]].Cost, FCandidates[Order[Second]].Cost) then
      Exit(FCandidates[Order[First]].Cost < FCandidates[Order[Second]].Cost);
    if Length(FCandidates[Order[First]].Text) <> Length(FCandidates[Order[Second]].Text) then
      Exit(Length(FCandidates[Order[First]].Text) < Length(FCandidates[Order[Second]].Text));
    Result := FCandidates[Order[First]].Text < FCandidates[Order[Second]].Text;
  end;

  procedure Sort;
  var
    Outer, Inner, KeptOrder, KeptStep: integer;
  begin
    // Insertion sort: few candidates are ever within the tolerance
    for Outer := 1 to Found - 1 do
    begin
      KeptOrder := Order[Outer];
      KeptStep := Steps[Outer];
      Inner := Outer;
      Order[Found] := KeptOrder;
      Steps[Found] := KeptStep;
      while (Inner > 0) and Before(Found, Inner - 1) do
      begin
        Order[Inner] := Order[Inner - 1];
        Steps[Inner] := Steps[Inner - 1];
        Dec(Inner);
      end;
      Order[Inner] := KeptOrder;
      Steps[Inner] := KeptStep;
    end;
  end;

var
  Seen: TKeySet;
  Text: string;
  Kept: integer;
begin
  Result := Default(TSuggestions);
  Tolerance := SuggestionTolerance(FKind);
  Step := Tolerance / CLOSENESS_STEPS;
  Negative := (FKind = skLength) and (Target < 0);
  // One spare place for sorting
  SetLength(Order, FCount + 1);
  SetLength(Steps, FCount + 1);
  Found := 0;
  NearestDistance := NO_DISTANCE;
  for Index := 0 to FCount - 1 do
  begin
    Delta := Difference(CandidateValue(Index), Target, FKind);
    if Abs(Delta) < NearestDistance then
    begin
      NearestDistance := Abs(Delta);
      Result.Nearest.Text := CandidateText(Index);
      Result.Nearest.Value := CandidateValue(Index);
      Result.Nearest.Delta := Delta;
      Result.HasNearest := True;
    end;
    if Abs(Delta) <= Tolerance then
    begin
      Order[Found] := Index;
      Steps[Found] := Trunc(Abs(Delta) / Step);
      Inc(Found);
    end;
  end;
  Sort;
  Seen := TKeySet.Create;
  try
    Kept := 0;
    SetLength(Result.Items, Min(Found, MAX_SUGGESTIONS));
    for Index := 0 to Found - 1 do
    begin
      if Kept = Length(Result.Items) then
        Break;
      Text := CandidateText(Order[Index]);
      if Seen.Contains(Text) or ((FCurrent <> '') and (FormulaKey(Text) = FCurrent)) then
        Continue;
      Seen.Add(Text);
      Result.Items[Kept].Text := Text;
      Result.Items[Kept].Value := CandidateValue(Order[Index]);
      Result.Items[Kept].Delta := Difference(Result.Items[Kept].Value, Target, FKind);
      Inc(Kept);
    end;
    SetLength(Result.Items, Kept);
  finally
    FreeAndNil(Seen);
  end;
end;

end.
