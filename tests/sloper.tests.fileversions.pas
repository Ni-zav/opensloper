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

// File format versions (issue #42): the upgrade steps, and files of every
// older version, kept in tests/files/v<n>/, loading and saving at the
// current version
unit Sloper.Tests.FileVersions;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.Core.FileVersions;

type
  TTestFileVersions = class(TOSTestCase)
  private
    function Upgraded(const Text: string; out Outcome: TVersionCheck; out ErrorMessage: string): string;
  published
    procedure TestOldestTakesEveryStep;
    procedure TestLaterTakesTheRest;
    procedure TestCurrentIsLeftAlone;
    procedure TestNewerIsRefused;
    procedure TestBelowOneIsRefused;
    procedure TestFailedStepSaysWhy;
    procedure TestMissingStep;
    procedure TestEveryFormatHasItsSteps;
    procedure TestOldFilesLoad;
  end;

implementation

uses
  Sloper.Core.JSON, Sloper.Core.Pattern, Sloper.Core.PatternFile, Sloper.Core.Measurements, Sloper.Output.Layout;

const
  // A made-up format at version 3: version 2 renamed "a" to "b", version 3 added "c"
  TEST_CURRENT = 3;

function RenameA(Root: TJSONObject; out ErrorMessage: string): boolean;
var
  Value: TJSONData;
begin
  ErrorMessage := '';
  Value := Root.Extract('a');
  Result := Assigned(Value);
  if Result then
    Root.Add('b', Value)
  else
    ErrorMessage := 'no a';
end;

function AddC(Root: TJSONObject; out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  Root.Add('c', 0);
  Result := True;
end;

function TestVersions: TFormatVersions;
begin
  Result.Current := TEST_CURRENT;
  Result.Steps := [@RenameA, @AddC];
end;

function TTestFileVersions.Upgraded(const Text: string; out Outcome: TVersionCheck; out ErrorMessage: string): string;
var
  Root: TJSONObject;
begin
  Root := GetJSON(Text) as TJSONObject;
  try
    Outcome := UpgradeFile(Root, Root.Integers['version'], TestVersions, ErrorMessage);
    Result := Root.AsJSON;
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestFileVersions.TestOldestTakesEveryStep;
var
  Outcome: TVersionCheck;
  Reason: string;
begin
  AssertEquals('{ "version" : 3, "b" : 5, "c" : 0 }', Upgraded('{"version": 1, "a": 5}', Outcome, Reason));
  AssertTrue('upgraded', Outcome = vcUpgraded);
end;

procedure TTestFileVersions.TestLaterTakesTheRest;
var
  Outcome: TVersionCheck;
  Reason: string;
begin
  AssertEquals('{ "version" : 3, "b" : 5, "c" : 0 }', Upgraded('{"version": 2, "b": 5}', Outcome, Reason));
  AssertTrue('upgraded', Outcome = vcUpgraded);
end;

procedure TTestFileVersions.TestCurrentIsLeftAlone;
var
  Outcome: TVersionCheck;
  Reason: string;
begin
  AssertEquals('{ "version" : 3, "b" : 5 }', Upgraded('{"version": 3, "b": 5}', Outcome, Reason));
  AssertTrue('current', Outcome = vcCurrent);
end;

procedure TTestFileVersions.TestNewerIsRefused;
var
  Outcome: TVersionCheck;
  Reason: string;
begin
  AssertEquals('unchanged', '{ "version" : 4, "a" : 5 }', Upgraded('{"version": 4, "a": 5}', Outcome, Reason));
  AssertTrue('newer', Outcome = vcNewer);
  AssertEquals(Format(rsFileVersionNewer, [4]), Reason);
end;

procedure TTestFileVersions.TestBelowOneIsRefused;
var
  Outcome: TVersionCheck;
  Reason: string;
begin
  AssertEquals('unchanged', '{ "version" : 0, "a" : 5 }', Upgraded('{"version": 0, "a": 5}', Outcome, Reason));
  AssertTrue('invalid', Outcome = vcInvalid);
  AssertEquals(Format(rsFileVersionInvalid, [0]), Reason);
end;

procedure TTestFileVersions.TestFailedStepSaysWhy;
var
  Outcome: TVersionCheck;
  Reason: string;
begin
  Upgraded('{"version": 1}', Outcome, Reason);
  AssertTrue('failed', Outcome = vcFailed);
  AssertEquals(Format(rsFileVersionStepFailed, [2, 'no a']), Reason);
end;

procedure TTestFileVersions.TestMissingStep;
var
  Versions: TFormatVersions;
  Root: TJSONObject;
  Reason: string;
begin
  Versions.Current := 2;
  Versions.Steps := nil;
  Root := TJSONObject.Create(['version', 1]);
  try
    AssertTrue('failed', UpgradeFile(Root, 1, Versions, Reason) = vcFailed);
    AssertEquals(Format(rsFileVersionNoStep, [1]), Reason);
  finally
    FreeAndNil(Root);
  end;
end;

procedure TTestFileVersions.TestEveryFormatHasItsSteps;
begin
  AssertEquals('pattern', PATTERN_VERSION, PatternFileVersions.Current);
  AssertEquals('pattern steps', PATTERN_VERSION - 1, Length(PatternFileVersions.Steps));
  AssertEquals('measurements', MEASUREMENT_VERSION, MeasurementFileVersions.Current);
  AssertEquals('measurement steps', MEASUREMENT_VERSION - 1, Length(MeasurementFileVersions.Steps));
  AssertEquals('layout', LAYOUT_VERSION, LayoutFileVersions.Current);
  AssertEquals('layout steps', LAYOUT_VERSION - 1, Length(LayoutFileVersions.Steps));
end;

// Saving writes the current version, and loading that again saves the same
function SavedAgain(const FileName: string; out Saved: string; out ErrorMessage: string): boolean;
var
  Text, Again: string;
  Pattern: TPattern;
  MeasurementSet: TMeasurementSet;
  Layout: TLayout;
begin
  Saved := '';
  if not ReadTextFile(FileName, Text, ErrorMessage) then
    Exit(False);
  Pattern := nil;
  MeasurementSet := nil;
  Layout := nil;
  try
    case ExtractFileExt(FileName) of
      '.sloper':
      begin
        Pattern := TPattern.Create;
        Result := LoadPatternFromText(Pattern, Text, ErrorMessage);
        if Result then
          Saved := SavePatternToText(Pattern);
        Result := Result and LoadPatternFromText(Pattern, Saved, ErrorMessage);
        if Result then
          Again := SavePatternToText(Pattern);
      end;
      '.slm':
      begin
        MeasurementSet := TMeasurementSet.Create;
        Result := MeasurementSet.LoadFromText(Text, ErrorMessage);
        if Result then
          Saved := MeasurementSet.SaveToText;
        Result := Result and MeasurementSet.LoadFromText(Saved, ErrorMessage);
        if Result then
          Again := MeasurementSet.SaveToText;
      end;
      else
      begin
        Layout := TLayout.Create;
        Result := Layout.LoadFromText(Text, ErrorMessage);
        if Result then
          Saved := Layout.SaveToText;
        Result := Result and Layout.LoadFromText(Saved, ErrorMessage);
        if Result then
          Again := Layout.SaveToText;
      end;
    end;
    if Result and (Again <> Saved) then
    begin
      ErrorMessage := 'saving it again gives other text';
      Result := False;
    end;
  finally
    FreeAndNil(Pattern);
    FreeAndNil(MeasurementSet);
    FreeAndNil(Layout);
  end;
end;

function CurrentVersion(const FileName: string): integer;
begin
  case ExtractFileExt(FileName) of
    '.sloper': Result := PATTERN_VERSION;
    '.slm': Result := MEASUREMENT_VERSION;
    else
      Result := LAYOUT_VERSION;
  end;
end;

// The pattern, measurement and layout files in each tests/files/v<n>
function OldFiles: TStringArray;
var
  Folder, VersionFolder: string;
  Versions, Found: TSearchRec;
begin
  Result := nil;
  Folder := ConcatPaths([ExtractFileDir(ExpandFileName(ParamStr(0))), 'files']);
  if FindFirst(ConcatPaths([Folder, 'v*']), faDirectory, Versions) = 0 then
  try
    repeat
      if (Versions.Attr and faDirectory) = 0 then
        Continue;
      VersionFolder := ConcatPaths([Folder, Versions.Name]);
      if FindFirst(ConcatPaths([VersionFolder, '*']), faAnyFile, Found) = 0 then
      try
        repeat
          case ExtractFileExt(Found.Name) of
            '.sloper', '.slm', '.slayout': Insert(ConcatPaths([VersionFolder, Found.Name]), Result, Length(Result));
          end;
        until FindNext(Found) <> 0;
      finally
        FindClose(Found);
      end;
    until FindNext(Versions) <> 0;
  finally
    FindClose(Versions);
  end;
end;

procedure TTestFileVersions.TestOldFilesLoad;
var
  Saved, Reason, FileName: string;
  Files: TStringArray;
  Root: TJSONData;
begin
  Files := OldFiles;
  AssertTrue('a file of each format', Length(Files) >= 3);
  for FileName in Files do
  begin
    AssertTrue(FileName + ': ' + Reason, SavedAgain(FileName, Saved, Reason));
    Root := GetJSON(Saved);
    try
      AssertEquals(FileName + ' is saved at the current version', CurrentVersion(FileName), TJSONObject(Root).Integers['version']);
    finally
      FreeAndNil(Root);
    end;
  end;
end;

initialization
  RegisterTest(TTestFileVersions);
end.
