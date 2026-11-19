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

// Problem lists and value reports for evaluated patterns.
unit Sloper.Tests.PatternCheck;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Measurements, Sloper.Core.Pattern;

type
  TTestPatternCheck = class(TOSTestCase)
  private
    FSet: TMeasurementSet;
    FPattern: TPattern;
    procedure LoadText(const Text: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNoProblems;
    procedure TestProblemsAndBlocked;
    procedure TestReport;
    procedure TestLooseOutlineEdgeReported;
    procedure TestNoOutlineReportBeforeAPiece;
    procedure TestSplitOutlineEdgeNotReported;
    procedure TestProblemsNameTheirObjects;
    procedure TestSettingsKeepProblemsToggle;
  end;

implementation

uses
  SysUtils, fpjson, Sloper.Core.JSON, Sloper.Core.Draft, Sloper.Core.PatternFile, Sloper.Core.PatternCheck, Sloper.Core.Geometry,
  Sloper.Core.Piece, Sloper.Core.PieceDetect, Sloper.Core.Settings;

// A 200 by 100 outline rectangle, as a piece when MakePiece
function OutlineRectangle(Pattern: TPattern; MakePiece: boolean; out Edges: TRectangleEdges): TPieceObject;
var
  Path: TPiecePath;
  Reason: string;
begin
  Result := nil;
  if not Pattern.AddRectangle(Pattern.AddFreePoint('O', '0', '0').Key, '200', '100', erOutline, Edges) then
    raise Exception.Create(Pattern.LastError);
  Pattern.Evaluate;
  if not MakePiece then
    Exit;
  if not DetectPiecePath(Pattern, Vec2(50, 50), Path, Reason) then
    raise Exception.Create(Reason);
  Result := Pattern.AddPiece('Front', Path, '10');
  Pattern.Evaluate;
end;

function HasProblem(Pattern: TPattern; const Problem: string): boolean;
var
  BlockedCount: integer;
  Found: string;
begin
  Result := False;
  for Found in PatternProblems(Pattern, BlockedCount) do
    Result := Result or (Found = Problem);
end;

procedure TTestPatternCheck.SetUp;
begin
  FSet := TMeasurementSet.Create;
  FSet.Add('waist', 720);
  FPattern := TPattern.Create;
  FPattern.Measurements := FSet;
end;

procedure TTestPatternCheck.TearDown;
begin
  FreeAndNil(FPattern);
  FreeAndNil(FSet);
end;

procedure TTestPatternCheck.LoadText(const Text: string);
var
  Err: string;
begin
  if not LoadPatternFromText(FPattern, Text, Err) then
    Fail('Load failed: ' + Err);
  FPattern.Evaluate;
end;

procedure TTestPatternCheck.TestNoProblems;
var
  BlockedCount: integer;
begin
  LoadText('{"format": "pattern", "version": 1,' +
    ' "variables": [{"id": 1, "name": "half", "formula": "@waist / 2"}],' +
    ' "objects": [{"id": 2, "type": "freePoint", "name": "A", "x": "{1}", "y": "0"}]}');
  AssertEquals('problems', 0, Length(PatternProblems(FPattern, BlockedCount)));
  AssertEquals('blocked', 0, BlockedCount);
end;

// A missing measurement, parallel lines and a formula that does not parse;
// the variables and the point that read them are blocked
procedure TTestPatternCheck.TestProblemsAndBlocked;
var
  Problems: TStringArray;
  BlockedCount: integer;
begin
  LoadText('{"format": "pattern", "version": 1,' +
    ' "variables": [{"id": 1, "name": "a", "formula": "@chest"}, {"id": 2, "name": "b", "formula": "{1} * 2"}],' +
    ' "objects": [{"id": 3, "type": "freePoint", "name": "A", "x": "0", "y": "0"},' +
    ' {"id": 4, "type": "freePoint", "name": "B", "x": "10", "y": "0"},' +
    ' {"id": 5, "type": "freePoint", "name": "C", "x": "0", "y": "10"},' +
    ' {"id": 6, "type": "freePoint", "name": "D", "x": "10", "y": "10"},' +
    ' {"id": 7, "type": "line", "start": 3, "end": 4},' +
    ' {"id": 8, "type": "line", "start": 5, "end": 6},' +
    ' {"id": 9, "type": "intersectPoint", "name": "X", "edgeA": 7, "edgeB": 8},' +
    ' {"id": 10, "type": "offsetPoint", "name": "Y", "base": 9, "length": "1", "angle": "0"},' +
    ' {"id": 11, "type": "freePoint", "name": "Z", "x": "1 +", "y": "0"}]}');
  Problems := PatternProblems(FPattern, BlockedCount);
  AssertEquals('problems', 3, Length(Problems));
  AssertEquals(Format(rsCheckProblem, ['@chest', rsCheckError, '@chest is not in the measurement set']), Problems[0]);
  AssertEquals(Format(rsCheckProblem, ['X', rsCheckInvalid, Format(rsDraftNoCrossing, ['Line_A_B', 'Line_C_D'])]),
    Problems[1]);
  AssertEquals('Z (error): ', Copy(Problems[2], 1, Length('Z (error): ')));
  AssertEquals('a, b and Y are blocked', 3, BlockedCount);
end;

procedure TTestPatternCheck.TestReport;
var
  Report: TJSONObject;
begin
  LoadText('{"format": "pattern", "version": 1,' +
    ' "variables": [{"id": 1, "name": "third", "formula": "1 / 3"}, {"id": 2, "name": "bad", "formula": "@chest"}],' +
    ' "objects": [{"id": 3, "type": "freePoint", "name": "A", "x": "{1}", "y": "-0.0000001"},' +
    ' {"id": 4, "type": "freePoint", "name": "B", "x": "3", "y": "4"},' +
    ' {"id": 5, "type": "line", "start": 3, "end": 4}]}');
  Report := PatternReport(FPattern, 'test.sloper', 'bill.slm');
  try
    AssertEquals(
      '{'#10 +
      '  "pattern": "test.sloper",'#10 +
      '  "measurements": "bill.slm",'#10 +
      '  "variables": ['#10 +
      '    {'#10 +
      '      "id": 1,'#10 +
      '      "name": "third",'#10 +
      '      "state": "valid",'#10 +
      '      "value": 0.333333'#10 +
      '    },'#10 +
      '    {'#10 +
      '      "id": 2,'#10 +
      '      "name": "bad",'#10 +
      '      "state": "blocked",'#10 +
      '      "message": "Blocked by @chest"'#10 +
      '    }'#10 +
      '  ],'#10 +
      '  "objects": ['#10 +
      '    {'#10 +
      '      "id": 3,'#10 +
      '      "name": "A",'#10 +
      '      "state": "valid",'#10 +
      '      "x": 0.333333,'#10 +
      '      "y": 0'#10 +
      '    },'#10 +
      '    {'#10 +
      '      "id": 4,'#10 +
      '      "name": "B",'#10 +
      '      "state": "valid",'#10 +
      '      "x": 3,'#10 +
      '      "y": 4'#10 +
      '    },'#10 +
      '    {'#10 +
      '      "id": 5,'#10 +
      '      "name": "Line_A_B",'#10 +
      '      "state": "valid",'#10 +
      '      "length": 4.807402'#10 +
      '    }'#10 +
      '  ]'#10 +
      '}'#10, JSONToText(Report));
  finally
    FreeAndNil(Report);
  end;
end;

procedure TTestPatternCheck.TestLooseOutlineEdgeReported;
var
  Edges: TRectangleEdges;
  Loose: TLineObject;
begin
  OutlineRectangle(FPattern, True, Edges);
  Loose := FPattern.AddLine(FPattern.AddFreePoint('P', '300', '0').Key, FPattern.AddFreePoint('Q', '300', '100').Key, erOutline);
  FPattern.Evaluate;
  AssertTrue('the loose edge', HasProblem(FPattern, Format(rsCheckOutlineLoose, [Loose.DisplayName])));
  AssertFalse('the piece''s own', HasProblem(FPattern, Format(rsCheckOutlineLoose, [Edges[0].DisplayName])));
  AssertTrue(FPattern.LastError, FPattern.SetEdgeRole(Loose, erConstruction));
  FPattern.Evaluate;
  AssertFalse('construction is fine', HasProblem(FPattern, Format(rsCheckOutlineLoose, [Loose.DisplayName])));
end;

procedure TTestPatternCheck.TestNoOutlineReportBeforeAPiece;
var
  Edges: TRectangleEdges;
begin
  OutlineRectangle(FPattern, False, Edges);
  AssertFalse('still drafting', HasProblem(FPattern, Format(rsCheckOutlineLoose, [Edges[0].DisplayName])));
end;

procedure TTestPatternCheck.TestSplitOutlineEdgeNotReported;
var
  Edges: TRectangleEdges;
  First, Second: TSplitPart;
  BlockedCount: integer;
begin
  OutlineRectangle(FPattern, True, Edges);
  AssertTrue(FPattern.LastError, FPattern.SplitEdge(Edges[0].Key, FPattern.AddAlongEdgePoint('M', Edges[0].Key, False, amRatio, '0.5').Key,
    First, Second));
  FPattern.Evaluate;
  AssertEquals('its parts stand in for it', 0, Length(PatternProblems(FPattern, BlockedCount)));
end;

procedure TTestPatternCheck.TestProblemsNameTheirObjects;
var
  Edges: TRectangleEdges;
  Loose: TLineObject;
  Piece: TPieceObject;
  List: TPatternProblemArray;
  Texts: TStringArray;
  BlockedCount, Index: integer;
begin
  Piece := OutlineRectangle(FPattern, True, Edges);
  FPattern.SetPieceMaterial(Piece, nil);
  Loose := FPattern.AddLine(FPattern.AddFreePoint('P', '300', '0').Key, FPattern.AddFreePoint('Q', '300', '100').Key, erOutline);
  FPattern.Evaluate;
  List := PatternProblemList(FPattern, BlockedCount);
  Texts := PatternProblems(FPattern, BlockedCount);
  AssertEquals('the same problems', Length(Texts), Length(List));
  for Index := 0 to High(List) do
    AssertEquals('in the same order', Texts[Index], List[Index].Text);
  AssertEquals(2, Length(List));
  AssertEquals('the piece with no material', Piece.Key, List[0].Key);
  AssertEquals('the loose edge', Loose.Key, List[1].Key);
end;

procedure TTestPatternCheck.TestSettingsKeepProblemsToggle;
var
  Settings: TAppSettings;
  Reason: string;
begin
  Settings := TAppSettings.Create;
  try
    AssertTrue('on by default', Settings.ShowProblems);
    Settings.ShowProblems := False;
    AssertTrue(Reason, Settings.LoadFromText(Settings.SaveToText, Reason));
    AssertFalse(Settings.ShowProblems);
  finally
    FreeAndNil(Settings);
  end;
end;

initialization
  RegisterTest(TTestPatternCheck);

end.
