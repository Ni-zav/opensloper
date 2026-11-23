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

// Importing the variables of another pattern file, so values set up once,
// such as eases, need not be typed again (issue #79). A variable whose name
// this pattern already has is kept as it is, never overwritten: delete it
// and import again for the other one. An imported formula that reads a kept
// variable reads this pattern's one of that name. No LCL dependency.
unit Sloper.Core.VariableImport;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Pattern;

type
  TVariableImport = record
    // The variables added, in the order the other file lists them
    Added: TStringArray;
    // Names this pattern already has with another formula, kept as they are
    Kept: TStringArray;
    // Names this pattern already has with the same formula
    Same: TStringArray;
  end;

// Adds Source's variables whose names Pattern does not have, with new IDs.
// Refused, with ErrorMessage, when the patterns' units differ, since a
// formula's plain numbers are in its pattern's unit. On failure the pattern
// may hold some of them (a document change undoes that). Call Evaluate
// afterwards.
function ImportVariables(Pattern, Source: TPattern; out Imported: TVariableImport; out ErrorMessage: string): boolean;
// The same from a pattern file
function ImportVariablesFromFile(Pattern: TPattern; const FileName: string; out Imported: TVariableImport;
  out ErrorMessage: string): boolean;
// The same from a pattern file's contents
function ImportVariablesFromText(Pattern: TPattern; const Text: string; out Imported: TVariableImport;
  out ErrorMessage: string): boolean;

resourcestring
  rsImportUnits = 'The variables are in %s and this pattern is in %s; convert one of them first';
  rsImportNotRead = 'Could not read %s: %s';

implementation

uses
  fpjson, Sloper.Core.Variables, Sloper.Core.PatternFile, Sloper.Core.Units;

procedure AddText(var List: TStringArray; const Text: string);
begin
  Insert(Text, List, Length(List));
end;

function ImportVariables(Pattern, Source: TPattern; out Imported: TVariableImport; out ErrorMessage: string): boolean;
var
  IdMap: TPatternIdMap;
  Items: TJSONArray;
  Variable, Existing: TVariable;
  Index, NextId: integer;
begin
  Imported := Default(TVariableImport);
  ErrorMessage := '';
  if Source.Units <> Pattern.Units then
  begin
    ErrorMessage := Format(rsImportUnits, [MEASURE_UNIT_NAMES[Source.Units], MEASURE_UNIT_NAMES[Pattern.Units]]);
    Exit(False);
  end;
  NextId := Pattern.NextId;
  IdMap := TPatternIdMap.Create;
  Items := TJSONArray.Create;
  try
    // Every variable is mapped first, so a formula may read one listed after it
    for Index := 0 to Source.VariableCount - 1 do
    begin
      Variable := Source.Variables[Index];
      Existing := Pattern.FindVariable(Variable.Name);
      if Assigned(Existing) then
      begin
        IdMap.AddOrSetValue(Variable.Key, Existing.Key);
        if Existing.Formula.DisplayText(Pattern.Resolver) = Variable.Formula.DisplayText(Source.Resolver) then
          AddText(Imported.Same, Existing.Name)
        else
          AddText(Imported.Kept, Existing.Name);
      end
      else
      begin
        IdMap.AddOrSetValue(Variable.Key, IntToStr(NextId));
        AddText(Imported.Added, IntToStr(NextId));
        Inc(NextId);
        Items.Add(PatternVariableToJSON(Variable));
      end;
    end;
    // Variables read only variables and measurements, so every ID is mapped
    Result := AddPatternItems(Pattern, Items, nil, IdMap, True, ErrorMessage);
  finally
    FreeAndNil(Items);
    FreeAndNil(IdMap);
  end;
end;

function ImportVariablesFromFile(Pattern: TPattern; const FileName: string; out Imported: TVariableImport;
  out ErrorMessage: string): boolean;
var
  Source: TPattern;
  Reason: string;
begin
  Imported := Default(TVariableImport);
  Source := TPattern.Create;
  try
    if not LoadPatternFromFile(Source, FileName, Reason) then
    begin
      ErrorMessage := Format(rsImportNotRead, [ExtractFileName(FileName), Reason]);
      Exit(False);
    end;
    Result := ImportVariables(Pattern, Source, Imported, ErrorMessage);
  finally
    FreeAndNil(Source);
  end;
end;

function ImportVariablesFromText(Pattern: TPattern; const Text: string; out Imported: TVariableImport;
  out ErrorMessage: string): boolean;
var
  Source: TPattern;
begin
  Imported := Default(TVariableImport);
  Source := TPattern.Create;
  try
    if not LoadPatternFromText(Source, Text, ErrorMessage) then
      Exit(False);
    Result := ImportVariables(Pattern, Source, Imported, ErrorMessage);
  finally
    FreeAndNil(Source);
  end;
end;

end.
