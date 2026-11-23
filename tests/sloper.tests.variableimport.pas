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

// Importing another pattern's variables: new names added with new IDs,
// names already here kept, formulas reading kept ones, units and files.
unit Sloper.Tests.VariableImport;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Pattern, Sloper.Core.VariableImport;

type
  TTestVariableImport = class(TOSTestCase)
  private
    FPattern, FSource: TPattern;
    FSet: TMeasurementSet;
    function Import(out Imported: TVariableImport): boolean;
    function FormulaOf(const AName: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddsNewNames;
    // A name already here is never overwritten, whatever its formula
    procedure TestKeepsExisting;
    // An imported formula reading a kept variable reads this pattern's one
    procedure TestReadsKeptVariable;
    // A formula may read a variable the other file lists after it
    procedure TestReadsLaterVariable;
    procedure TestNewIds;
    procedure TestOtherUnitsRefused;
    procedure TestFromFile;
    procedure TestMissingFile;
  end;

implementation

uses
  Sloper.Core.Units, Sloper.Core.Variables, Sloper.Core.PatternFile, Sloper.Core.Evaluator;

procedure TTestVariableImport.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('hip', 960);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
  FSource := TPattern.Create;
  FSource.Measurements := FSet;
  FSource.AddVariable('hip_ease', '40', 'Ease round the hip');
  FSource.AddVariable('waist_ease', '10');
  FSource.AddVariable('half_hip', '@hip / 2 + #hip_ease / 2');
end;

procedure TTestVariableImport.TearDown;
begin
  FreeAndNil(FSource);
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

function TTestVariableImport.Import(out Imported: TVariableImport): boolean;
var
  Reason: string;
begin
  Result := ImportVariables(FPattern, FSource, Imported, Reason);
  AssertEquals('no reason', '', Reason);
  FPattern.Evaluate;
end;

function TTestVariableImport.FormulaOf(const AName: string): string;
var
  Variable: TVariable;
begin
  Variable := FPattern.FindVariable(AName);
  AssertNotNull(AName, Variable);
  Result := Variable.Formula.DisplayText(FPattern.Resolver);
end;

procedure TTestVariableImport.TestAddsNewNames;
var
  Imported: TVariableImport;
begin
  AssertTrue(Import(Imported));
  AssertEquals('added', 3, Length(Imported.Added));
  AssertEquals('none kept', 0, Length(Imported.Kept));
  AssertEquals('in order', 'hip_ease', TVariable(FPattern.FindNode(Imported.Added[0])).Name);
  AssertEquals('formula', '@hip / 2 + #hip_ease / 2', FormulaOf('half_hip'));
  AssertEquals('description', 'Ease round the hip', FPattern.FindVariable('hip_ease').Description);
end;

procedure TTestVariableImport.TestKeepsExisting;
var
  Imported: TVariableImport;
begin
  FPattern.AddVariable('HIP_EASE', '60');
  FPattern.AddVariable('waist_ease', '10');
  AssertTrue(Import(Imported));
  AssertEquals('added', 1, Length(Imported.Added));
  AssertEquals('kept', 1, Length(Imported.Kept));
  AssertEquals('kept by its name here', 'HIP_EASE', Imported.Kept[0]);
  AssertEquals('the same', 1, Length(Imported.Same));
  AssertEquals('same', 'waist_ease', Imported.Same[0]);
  AssertEquals('not overwritten', '60', FormulaOf('hip_ease'));
  AssertEquals('variables', 3, FPattern.VariableCount);
end;

procedure TTestVariableImport.TestReadsKeptVariable;
var
  Imported: TVariableImport;
begin
  FPattern.AddVariable('hip_ease', '60');
  AssertTrue(Import(Imported));
  AssertEquals('reads the one here', '@hip / 2 + #hip_ease / 2', FormulaOf('half_hip'));
  AssertEquals('by its key', FPattern.FindVariable('hip_ease').Key,
    ReferenceKey(FPattern.FindVariable('half_hip').Formula.References[1]));
end;

procedure TTestVariableImport.TestReadsLaterVariable;
var
  Imported: TVariableImport;
begin
  FSource.AddVariable('later', '20');
  AssertTrue(FSource.SetFormula(FSource.FindVariable('hip_ease'), 'formula', '#later * 2'));
  AssertTrue(Import(Imported));
  AssertEquals('reads it', '#later * 2', FormulaOf('hip_ease'));
  AssertNear('worked out', 40, FPattern.FindVariable('hip_ease').Value);
end;

procedure TTestVariableImport.TestNewIds;
var
  Imported: TVariableImport;
  Before: integer;
begin
  FPattern.AddFreePoint('A', '0', '0');
  FPattern.AddFreePoint('B', '0', '0');
  Before := FPattern.NextId;
  AssertTrue(Import(Imported));
  AssertEquals('first new ID', IntToStr(Before), Imported.Added[0]);
  AssertEquals('kept above', Before + 3, FPattern.NextId);
end;

procedure TTestVariableImport.TestOtherUnitsRefused;
var
  Imported: TVariableImport;
  Reason: string;
begin
  FPattern.Units := muCentimetre;
  AssertFalse(ImportVariables(FPattern, FSource, Imported, Reason));
  AssertEquals(Format(rsImportUnits, ['mm', 'cm']), Reason);
  AssertEquals('nothing added', 0, FPattern.VariableCount);
end;

procedure TTestVariableImport.TestFromFile;
var
  FileName, Reason: string;
  Imported: TVariableImport;
begin
  FileName := GetTempFileName(GetTempDir, 'sloper') + '.sloper';
  try
    AssertTrue(SavePatternToFile(FSource, FileName, Reason));
    AssertTrue(ImportVariablesFromFile(FPattern, FileName, Imported, Reason));
    AssertEquals('added', 3, Length(Imported.Added));
  finally
    DeleteFile(FileName);
  end;
end;

procedure TTestVariableImport.TestMissingFile;
var
  Imported: TVariableImport;
  Reason: string;
begin
  AssertFalse(ImportVariablesFromFile(FPattern, ConcatPaths([GetTempDir, 'no-such-pattern.sloper']), Imported, Reason));
  AssertTrue('says which', Pos('no-such-pattern.sloper', Reason) > 0);
end;

initialization
  RegisterTest(TTestVariableImport);
end.
