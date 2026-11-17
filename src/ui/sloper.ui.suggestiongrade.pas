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

// The grade check of formula suggestions (issue #26): with a size table, what
// each suggestion comes to at every size, and the shape its object would
// have at the smallest and largest sizes, so a formula that matches only by
// coincidence at the size shown is easy to spot. It works on copies of the
// pattern, one for each size, so the pattern itself is never changed. Kept
// free of the LCL so it can be unit-tested.
unit Sloper.UI.SuggestionGrade;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Generics.Collections, Sloper.Core.Geometry, Sloper.Core.Evaluator, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.Units,
  Sloper.UI.Suggestion;

type
  TPolylineArray = array of TVec2Array;

  // What the field's object would look like at one size: the outlines of the
  // pieces that use it, or else the edges that do, and the point itself
  TGradeGhost = record
    Lines: TPolylineArray;
    HasPoint: boolean;
    Point: TVec2;
  end;
  TGradeGhostArray = array of TGradeGhost;

  TSizeValues = array of double;

  TGradeCheck = class
  private
    // One copy of the pattern for each size, with its own measurements,
    // evaluated at that size
    FPatterns: specialize TObjectList<TPattern>;
    FSets: specialize TObjectList<TMeasurementSet>;
    FSizes: TStringArray;
    FNodeKey, FFieldName, FOriginal: string;
    FKind: TSuggestionKind;
    FCache: specialize TDictionary<string, TSizeValues>;
    function GetSizeCount: integer;
    function GetSize(Index: integer): string;
    function GhostAt(SizeIndex: integer; const FormulaText: string): TGradeGhost;
  public
    // Nothing to check unless the pattern's measurements are a table of
    // more than one size
    constructor Create(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
    destructor Destroy; override;
    // What the formula comes to at each size, in the table's order, as the
    // field takes it (mm, degrees or a ratio); NaN where it cannot be worked out
    function Values(const FormulaText: string): TSizeValues;
    // The object with FormulaText in the field, at the first and last sizes of
    // the table, which are taken to be the smallest and largest
    function Ghosts(const FormulaText: string): TGradeGhostArray;
    // False when there is only one size
    function Available: boolean;
    property SizeCount: integer read GetSizeCount;
    property Sizes[Index: integer]: string read GetSize;
  end;

// "34: 158, 36: 162.5 ..." for a row's tooltip
function SizeValuesText(Grade: TGradeCheck; const Values: TSizeValues; Kind: TSuggestionKind; Units: TMeasureUnit): string;
// "158–174": the first and last sizes' values, or '' when either is missing
function SizeRangeText(const Values: TSizeValues; Kind: TSuggestionKind; Units: TMeasureUnit): string;

resourcestring
  // A size and what a formula comes to at it
  rsGradeSizeValue = '%s: %s';
  rsGradeNoValue = '-';
  // The first and last sizes' values
  rsGradeRange = '%s–%s';

implementation

uses
  Math, Sloper.Core.EvalTypes, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.PatternFile;

const
  // How closely an edge's ghost follows a curve, in mm
  GHOST_FLATNESS = 0.5;

constructor TGradeCheck.Create(Pattern: TPattern; Node: TEvalNode; const FieldName: string);
var
  Text, SetText, Reason: string;
  Index: integer;
  Copied: TPattern;
  CopiedSet: TMeasurementSet;
begin
  inherited Create;
  FPatterns := specialize TObjectList<TPattern>.Create(True);
  FSets := specialize TObjectList<TMeasurementSet>.Create(True);
  FCache := specialize TDictionary<string, TSizeValues>.Create;
  FNodeKey := Node.Key;
  FFieldName := FieldName;
  FKind := SuggestionKind(Node, FieldName);
  if not Assigned(Pattern.Measurements) or (Pattern.Measurements.SizeCount < 2) then
    Exit;
  FOriginal := Pattern.FormulaText(Node, FieldName);
  Text := SavePatternToText(Pattern);
  SetText := Pattern.Measurements.SaveToText;
  SetLength(FSizes, Pattern.Measurements.SizeCount);
  for Index := 0 to High(FSizes) do
  begin
    FSizes[Index] := Pattern.Measurements.Sizes[Index];
    // Each goes into its list first, which then owns it
    CopiedSet := TMeasurementSet.Create;
    FSets.Add(CopiedSet);
    Copied := TPattern.Create;
    FPatterns.Add(Copied);
    if not CopiedSet.LoadFromText(SetText, Reason) or not CopiedSet.SelectSize(FSizes[Index]) or not LoadPatternFromText(Copied, Text, Reason) then
    begin
      // A copy that cannot be made leaves nothing to check
      FPatterns.Clear;
      FSets.Clear;
      FSizes := nil;
      Exit;
    end;
    Copied.Measurements := CopiedSet;
    Copied.MeasurementScale := Pattern.MeasurementScale;
    Copied.Evaluate;
  end;
end;

destructor TGradeCheck.Destroy;
begin
  // The patterns read their sets, so they go first
  FreeAndNil(FPatterns);
  FreeAndNil(FSets);
  FreeAndNil(FCache);
  inherited Destroy;
end;

function TGradeCheck.Available: boolean;
begin
  Result := Length(FSizes) > 1;
end;

function TGradeCheck.GetSizeCount: integer;
begin
  Result := Length(FSizes);
end;

function TGradeCheck.GetSize(Index: integer): string;
begin
  Result := FSizes[Index];
end;

// A candidate never reads the field's object, so its values do not change
// while the field does, and are kept
function TGradeCheck.Values(const FormulaText: string): TSizeValues;
var
  Index: integer;
  Value: double;
begin
  if FCache.TryGetValue(FormulaText, Result) then
    Exit;
  Result := nil;
  SetLength(Result, Length(FSizes));
  for Index := 0 to High(FSizes) do
    if FPatterns[Index].EvaluateText(FormulaText, Value) and not IsNan(Value) and not IsInfinite(Value) then
    begin
      if FKind = skLength then
        Value := Value * MILLIMETRES_PER_UNIT[FPatterns[Index].Units];
      Result[Index] := Value;
    end
    else
      Result[Index] := NaN;
  FCache.Add(FormulaText, Result);
end;

// A piece's seam line does not repeat its first point
function ClosedOutline(const Outline: TVec2Array): TVec2Array;
begin
  Result := Copy(Outline);
  Insert(Outline[0], Result, Length(Result));
end;

// The copy is put back afterwards, so it stays as the pattern is
function TGradeCheck.GhostAt(SizeIndex: integer; const FormulaText: string): TGradeGhost;
var
  Copied: TPattern;
  Node: TEvalNode;
  Index: integer;
  Other: TDraftObject;
  UsedByPiece: boolean;
begin
  Result := Default(TGradeGhost);
  Copied := FPatterns[SizeIndex];
  Node := Copied.FindNode(FNodeKey);
  if not Assigned(Node) or not Copied.SetFormula(Node, FFieldName, FormulaText) then
    Exit;
  try
    Copied.Evaluate;
    if (Node is TPointObject) and (Node.State = esValid) then
    begin
      Result.HasPoint := True;
      Result.Point := TPointObject(Node).Position;
    end;
    UsedByPiece := False;
    for Index := 0 to Copied.ObjectCount - 1 do
    begin
      Other := Copied.Objects[Index];
      if (Other is TPieceObject) and (Other.State = esValid) and Copied.Reaches(Other, Node) and (Length(TPieceObject(Other).Outline) > 0) then
      begin
        UsedByPiece := True;
        Insert(ClosedOutline(TPieceObject(Other).Outline), Result.Lines, Length(Result.Lines));
      end;
    end;
    if UsedByPiece then
      Exit;
    for Index := 0 to Copied.ObjectCount - 1 do
    begin
      Other := Copied.Objects[Index];
      if (Other is TEdgeObject) and (Other.State = esValid) and ((Other = Node) or Copied.Reaches(Other, Node)) then
        Insert(TEdgeObject(Other).Flatten(GHOST_FLATNESS), Result.Lines, Length(Result.Lines));
    end;
  finally
    Copied.SetFormula(Node, FFieldName, FOriginal);
    Copied.Evaluate;
  end;
end;

function TGradeCheck.Ghosts(const FormulaText: string): TGradeGhostArray;
begin
  Result := nil;
  if not Available then
    Exit;
  Result := [GhostAt(0, FormulaText), GhostAt(High(FSizes), FormulaText)];
end;

function ValueText(Value: double; Kind: TSuggestionKind; Units: TMeasureUnit): string;
begin
  if IsNan(Value) then
    Result := rsGradeNoValue
  else
    Result := SuggestionValueText(Value, Kind, Units);
end;

function SizeValuesText(Grade: TGradeCheck; const Values: TSizeValues; Kind: TSuggestionKind; Units: TMeasureUnit): string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to Min(High(Values), Grade.SizeCount - 1) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Format(rsGradeSizeValue, [Grade.Sizes[Index], ValueText(Values[Index], Kind, Units)]);
  end;
end;

function SizeRangeText(const Values: TSizeValues; Kind: TSuggestionKind; Units: TMeasureUnit): string;
begin
  Result := '';
  if (Length(Values) < 2) or IsNan(Values[0]) or IsNan(Values[High(Values)]) then
    Exit;
  Result := Format(rsGradeRange, [ValueText(Values[0], Kind, Units), ValueText(Values[High(Values)], Kind, Units)]);
end;

end.
