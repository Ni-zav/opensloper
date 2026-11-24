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

// Unit suffixes where no unit belongs (issue #33). A number written with a
// unit (45mm) is a length, so an angle or ratio field whose formula works out
// to a length because of one, such as "45mm" or "@waist/4 + 1in", is refused
// as it is typed; "Line.length / 10cm" works out to a plain number and is
// taken. A formula's power of length is worked out from what is certain:
// suffixed numbers, measurements and length properties are 1, other
// properties and the results of sin, cos, tan, asin, acos, atan2 and bisect are 0,
// and a plain number multiplying or dividing counts as 0. Plain numbers
// added to something, and variables, could be either, so they settle nothing.
// Only formulas with a suffix are judged, so a pattern that never wrote one is
// not refused for what it already does. No LCL dependency.
unit Sloper.Core.UnitCheck;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Formula, Sloper.Core.Evaluator;

// False when Formula, for a field of Kind, uses a unit where none belongs:
// ErrorMessage says why and ErrorToken is the suffixed number's token
function CheckFormulaUnits(Formula: TFormula; Kind: TFieldUnitKind; out ErrorMessage: string; out ErrorToken: integer): boolean;

resourcestring
  // The suffixed number, such as 45mm
  rsUnitCheckAngle = 'An angle is plain degrees, but %s makes this a length';
  rsUnitCheckNumber = 'This is a plain number, not a length, but %s makes it one';
  // The suffixed number, and the function: sin
  rsUnitCheckFunction = '%1:s takes plain numbers, but %0:s is a length';
  rsUnitCheckMixed = '%s adds a length to a plain number';

implementation

uses
  SysUtils, Math, Sloper.Core.FormulaLexer, Sloper.Core.Draft;

const
  TOLERANCE = 1e-9;

type
  // What is certain about a part of a formula
  TPower = record
    Known: boolean;
    // Its power of length when Known: 0 a plain number, 1 a length
    Value: double;
    // A plain number as written, which counts as 0 beside * and /
    Bare: boolean;
    // A suffixed number in it, for the message; -1 when none
    SuffixToken: integer;
  end;

  EUnitRefused = class(Exception)
  public
    Token: integer;
  end;

function KnownPower(Value: double; SuffixToken: integer): TPower;
begin
  Result.Known := True;
  Result.Value := Value;
  Result.Bare := False;
  Result.SuffixToken := SuffixToken;
end;

function UnknownPower(SuffixToken: integer): TPower;
begin
  Result.Known := False;
  Result.Value := 0;
  Result.Bare := False;
  Result.SuffixToken := SuffixToken;
end;

function FirstSuffix(const First, Second: TPower): integer;
begin
  Result := First.SuffixToken;
  if Result < 0 then
    Result := Second.SuffixToken;
end;

function SuffixText(Formula: TFormula; Token: integer): string;
var
  Start, Size: integer;
begin
  Result := '';
  if Formula.StoredTokenSpan(Token, Start, Size) then
    Result := Copy(Formula.StoredText, Start, Size);
end;

procedure Refuse(const Message: string; Token: integer);
var
  Failure: EUnitRefused;
begin
  Failure := EUnitRefused.Create(Message);
  Failure.Token := Token;
  raise Failure;
end;

function Differ(const First, Second: TPower): boolean;
begin
  Result := First.Known and Second.Known and not SameValue(First.Value, Second.Value, TOLERANCE);
end;

function PowerOf(Formula: TFormula; const Shape: TFormulaShape; Index: integer): TPower; forward;

// A plain number beside * or / is a factor, a power of 0
function AsFactor(const Part: TPower): TPower;
begin
  Result := Part;
  if Part.Bare then
    Result := KnownPower(0, Part.SuffixToken);
end;

function ProductPower(const First, Second: TPower; Dividing: boolean): TPower;
var
  Left, Right: TPower;
begin
  Left := AsFactor(First);
  Right := AsFactor(Second);
  if not Left.Known or not Right.Known then
    Exit(UnknownPower(FirstSuffix(First, Second)));
  if Dividing then
    Result := KnownPower(Left.Value - Right.Value, FirstSuffix(First, Second))
  else
    Result := KnownPower(Left.Value + Right.Value, FirstSuffix(First, Second));
end;

// The operands of + and -, and of min and max, are alike: a length and a
// plain number together is a mistake when a unit made one of them a length
function AlikePower(Formula: TFormula; const First, Second: TPower; const Message: string): TPower;
begin
  if Differ(First, Second) and (FirstSuffix(First, Second) >= 0) then
    Refuse(Format(Message, [SuffixText(Formula, FirstSuffix(First, Second))]), FirstSuffix(First, Second));
  if First.Known then
    Result := KnownPower(First.Value, FirstSuffix(First, Second))
  else if Second.Known then
    Result := KnownPower(Second.Value, FirstSuffix(First, Second))
  else
    Result := UnknownPower(FirstSuffix(First, Second));
end;

// sin, cos, tan, asin and acos take a plain number, bisect two, and atan2
// two alike; all give a plain number
function FunctionPower(Formula: TFormula; const Name: string; const Parts: array of TPower): TPower;
var
  Index: integer;
  Combined: TPower;
begin
  Combined := UnknownPower(-1);
  for Index := 0 to High(Parts) do
    if Combined.SuffixToken < 0 then
      Combined.SuffixToken := Parts[Index].SuffixToken;
  case Name of
    'sin', 'cos', 'tan', 'asin', 'acos':
    begin
      if (Length(Parts) > 0) and Parts[0].Known and not SameValue(Parts[0].Value, 0, TOLERANCE) and (Parts[0].SuffixToken >= 0) then
        Refuse(Format(rsUnitCheckFunction, [SuffixText(Formula, Parts[0].SuffixToken), Name]), Parts[0].SuffixToken);
      Result := KnownPower(0, Combined.SuffixToken);
    end;
    'bisect':
    begin
      for Index := 0 to High(Parts) do
        if Parts[Index].Known and not SameValue(Parts[Index].Value, 0, TOLERANCE) and (Parts[Index].SuffixToken >= 0) then
          Refuse(Format(rsUnitCheckFunction, [SuffixText(Formula, Parts[Index].SuffixToken), Name]), Parts[Index].SuffixToken);
      Result := KnownPower(0, Combined.SuffixToken);
    end;
    'atan2':
    begin
      if (Length(Parts) = 2) and Differ(Parts[0], Parts[1]) and (FirstSuffix(Parts[0], Parts[1]) >= 0) then
        Refuse(Format(rsUnitCheckFunction, [SuffixText(Formula, FirstSuffix(Parts[0], Parts[1])), Name]), FirstSuffix(Parts[0], Parts[1]));
      Result := KnownPower(0, Combined.SuffixToken);
    end;
    'sqrt':
      if (Length(Parts) > 0) and Parts[0].Known then
        Result := KnownPower(Parts[0].Value / 2, Combined.SuffixToken)
      else
        Result := Combined;
    else
    begin
      // abs, round, min, max: the arguments and the result are alike
      if Length(Parts) = 0 then
        Exit(Combined);
      Result := Parts[0];
      for Index := 1 to High(Parts) do
        Result := AlikePower(Formula, Result, Parts[Index], rsUnitCheckMixed);
      Result.Bare := False;
    end;
  end;
end;

function PowerOf(Formula: TFormula; const Shape: TFormulaShape; Index: integer): TPower;
var
  Item: TFormulaShapeNode;
  Parts: array of TPower;
  Child: integer;
  Ref: TFormulaReference;
  Exponent: TFormulaShapeNode;
begin
  Item := Shape[Index];
  Parts := nil;
  for Child in Item.Children do
    Insert(PowerOf(Formula, Shape, Child), Parts, Length(Parts));
  case Item.Kind of
    fsNumber:
      if Item.Suffix <> nsNone then
        Result := KnownPower(1, Item.Token)
      else
      begin
        Result := UnknownPower(-1);
        Result.Bare := True;
      end;
    fsReference:
    begin
      Ref := Formula.References[Item.Reference];
      case Ref.Kind of
        rkMeasurement: Result := KnownPower(1, -1);
        rkVariable: Result := UnknownPower(-1);
        else
          if IsLengthProperty(Ref.Prop) then
            Result := KnownPower(1, -1)
          else
            Result := KnownPower(0, -1);
      end;
    end;
    fsNegate:
      Result := Parts[0];
    fsAdd, fsSubtract:
      Result := AlikePower(Formula, Parts[0], Parts[1], rsUnitCheckMixed);
    fsMultiply:
      Result := ProductPower(Parts[0], Parts[1], False);
    fsDivide:
      Result := ProductPower(Parts[0], Parts[1], True);
    fsPower:
    begin
      Exponent := Shape[Item.Children[1]];
      if Parts[0].Known and (Exponent.Kind = fsNumber) and (Exponent.Suffix = nsNone) then
        Result := KnownPower(Parts[0].Value * Exponent.Value, FirstSuffix(Parts[0], Parts[1]))
      else
        Result := UnknownPower(FirstSuffix(Parts[0], Parts[1]));
    end;
    else
      Result := FunctionPower(Formula, Item.FunctionName, Parts);
  end;
end;

function CheckFormulaUnits(Formula: TFormula; Kind: TFieldUnitKind; out ErrorMessage: string; out ErrorToken: integer): boolean;
var
  Shape: TFormulaShape;
  Root: TPower;
begin
  ErrorMessage := '';
  ErrorToken := -1;
  Shape := Formula.Shape;
  if Length(Shape) = 0 then
    Exit(True);
  try
    Root := PowerOf(Formula, Shape, 0);
  except
    on Failure: EUnitRefused do
    begin
      ErrorMessage := Failure.Message;
      ErrorToken := Failure.Token;
      Exit(False);
    end;
  end;
  Result := True;
  if not (Kind in [fkAngle, fkNumber]) or not Root.Known or SameValue(Root.Value, 0, TOLERANCE) or (Root.SuffixToken < 0) then
    Exit;
  ErrorToken := Root.SuffixToken;
  if Kind = fkAngle then
    ErrorMessage := Format(rsUnitCheckAngle, [SuffixText(Formula, ErrorToken)])
  else
    ErrorMessage := Format(rsUnitCheckNumber, [SuffixText(Formula, ErrorToken)]);
  Result := False;
end;

end.
