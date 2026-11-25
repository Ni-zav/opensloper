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

// Layout files, tiling and the tiled PDF.
// Layouts whose patterns and measurement sets are given as text, as the web
// Publish app gives them, rather than read from disk.
unit Sloper.Tests.SourceFiles;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Output.Layout, Sloper.Output.LayoutDocument,
  Sloper.Core.PatternSources;

type
  TTestSourceFiles = class(TOSTestCase)
  private
    FDocument: TLayoutDocument;
    // The text of a file of the skirt block example
    function Example(const FileName: string): string;
    // A layout's text listing one source
    function LayoutText(const PatternFile, MeasurementFile: string): string;
    function BlockingText: string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNormalPaths;
    procedure TestReadsGivenFiles;
    procedure TestMissingSetIsNamed;
    procedure TestSetBesidePatternInFolder;
    procedure TestLayoutsOwnSet;
    procedure TestUndoReadsGivenFilesAgain;
    procedure TestNewForGivenPattern;
    procedure TestGivenFilesAreNotWatched;
    procedure TestOpenFromDiskReadsDisk;
  end;

implementation

uses
  Sloper.Core.JSON;

const
  PATTERN_FILE = 'skirt-darts.sloper';
  SET_FILE = 'skirt.slm';

function ExamplePath(const FileName: string): string;
begin
  Result := ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs', 'examples', 'skirt-block',
    FileName]);
end;

function TTestSourceFiles.Example(const FileName: string): string;
var
  Reason: string;
begin
  AssertTrue(Reason, ReadTextFile(ExamplePath(FileName), Result, Reason));
end;

function TTestSourceFiles.LayoutText(const PatternFile, MeasurementFile: string): string;
var
  Layout: TLayout;
begin
  Layout := TLayout.Create;
  try
    Layout.Name := 'skirt';
    Layout.AddSource(PatternFile, MeasurementFile, '');
    Result := Layout.SaveToText;
  finally
    FreeAndNil(Layout);
  end;
end;

function TTestSourceFiles.BlockingText: string;
var
  Problem: TLayoutProblem;
begin
  Result := '';
  for Problem in FDocument.Layout.Problems do
    if Problem.Blocking then
      Result := Result + Problem.Text + LineEnding;
end;

procedure TTestSourceFiles.SetUp;
begin
  FDocument := TLayoutDocument.Create;
end;

procedure TTestSourceFiles.TearDown;
begin
  FreeAndNil(FDocument);
end;

procedure TTestSourceFiles.TestNormalPaths;
begin
  AssertEquals('as it is', 'skirt.slm', NormalSourcePath('skirt.slm'));
  AssertEquals('dots', 'a/c.slm', NormalSourcePath('./a/b/../c.slm'));
  AssertEquals('backslashes', 'a/b.sloper', NormalSourcePath('a\b.sloper'));
  AssertEquals('above the layout', '../m/s.slm', NormalSourcePath('p/../../m/s.slm'));
  AssertEquals('doubled', '../../s.slm', NormalSourcePath('../../s.slm'));
  AssertEquals('rooted', '/home/s.slm', NormalSourcePath('/home//x/../s.slm'));
  AssertEquals('nothing above the root', '/s.slm', NormalSourcePath('/../s.slm'));
end;

procedure TTestSourceFiles.TestReadsGivenFiles;
var
  Reason: string;
  Source: TPatternSource;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, Example(PATTERN_FILE));
  FDocument.SourceFiles.Add(SET_FILE, Example(SET_FILE));
  AssertTrue(Reason, FDocument.OpenText(LayoutText(PATTERN_FILE, ''), Reason));
  Source := FDocument.Layout.Sources[0];
  AssertEquals('read', '', Source.LoadError);
  AssertTrue('from text', Source.InMemory);
  AssertNotNull('the pattern', Source.Pattern);
  AssertEquals('its set', SET_FILE, Source.MeasurementPath);
  AssertEquals('no file name', '', FDocument.Layout.FileName);
  AssertTrue('its pieces wait to be placed', Length(FDocument.Layout.Unplaced) > 0);
  AssertFalse('opened unchanged', FDocument.Modified);
end;

procedure TTestSourceFiles.TestMissingSetIsNamed;
var
  Reason: string;
  Source: TPatternSource;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, Example(PATTERN_FILE));
  AssertTrue(Reason, FDocument.OpenText(LayoutText(PATTERN_FILE, ''), Reason));
  Source := FDocument.Layout.Sources[0];
  AssertEquals('names the set', SET_FILE, Source.MissingFile);
  AssertTrue('blocks: ' + BlockingText, Pos(SET_FILE, BlockingText) > 0);
  FDocument.SourceFiles.Add(SET_FILE, Example(SET_FILE));
  FDocument.Reload;
  AssertEquals('read once given', '', Source.LoadError);
  AssertEquals('nothing missing', '', Source.MissingFile);
end;

procedure TTestSourceFiles.TestSetBesidePatternInFolder;
var
  Reason: string;
begin
  FDocument.SourceFiles.Add('patterns/skirt.sloper', StringReplace(Example(PATTERN_FILE), '"' + SET_FILE + '"',
    '"../sizes/' + SET_FILE + '"', []));
  FDocument.SourceFiles.Add('sizes/' + SET_FILE, Example(SET_FILE));
  AssertTrue(Reason, FDocument.OpenText(LayoutText('patterns/skirt.sloper', ''), Reason));
  AssertEquals('found from the pattern''s folder', 'sizes/' + SET_FILE, FDocument.Layout.Sources[0].MeasurementPath);
  AssertEquals('read', '', FDocument.Layout.Sources[0].LoadError);
end;

procedure TTestSourceFiles.TestLayoutsOwnSet;
var
  Reason: string;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, Example(PATTERN_FILE));
  FDocument.SourceFiles.Add('other.slm', Example(SET_FILE));
  AssertTrue(Reason, FDocument.OpenText(LayoutText(PATTERN_FILE, 'other.slm'), Reason));
  AssertEquals('the layout''s, not the pattern''s', 'other.slm', FDocument.Layout.Sources[0].MeasurementPath);
  AssertEquals('read', '', FDocument.Layout.Sources[0].LoadError);
end;

procedure TTestSourceFiles.TestUndoReadsGivenFilesAgain;
var
  Reason: string;
  Source: TPatternSource;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, Example(PATTERN_FILE));
  FDocument.SourceFiles.Add(SET_FILE, Example(SET_FILE));
  AssertTrue(Reason, FDocument.OpenText(LayoutText(PATTERN_FILE, ''), Reason));
  FDocument.BeginChange('Place');
  FDocument.Layout.PlaceNewPieces;
  FDocument.EndChange;
  FDocument.Undo;
  Source := FDocument.Layout.Sources[0];
  AssertEquals('undone', 0, Length(FDocument.Layout.Placements));
  AssertEquals('read again', '', Source.LoadError);
  AssertNotNull('with its pattern', Source.Pattern);
  FDocument.Redo;
  AssertTrue('redone', Length(FDocument.Layout.Placements) > 0);
  AssertEquals('and read', '', FDocument.Layout.Sources[0].LoadError);
end;

procedure TTestSourceFiles.TestNewForGivenPattern;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, Example(PATTERN_FILE));
  FDocument.SourceFiles.Add(SET_FILE, Example(SET_FILE));
  FDocument.NewForPattern(PATTERN_FILE);
  AssertEquals('named after it', 'skirt-darts', FDocument.Layout.Name);
  AssertEquals('read', '', FDocument.Layout.Sources[0].LoadError);
  AssertTrue('every piece placed', Length(FDocument.Layout.Placements) > 0);
  AssertEquals(BlockingText, '', BlockingText);
end;

procedure TTestSourceFiles.TestGivenFilesAreNotWatched;
var
  Reason: string;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, Example(PATTERN_FILE));
  FDocument.SourceFiles.Add(SET_FILE, Example(SET_FILE));
  AssertTrue(Reason, FDocument.OpenText(LayoutText(PATTERN_FILE, ''), Reason));
  // A changed file must read the same twice, so two checks would reload it
  AssertEquals('first check', '', FDocument.CheckSources);
  AssertEquals('second check', '', FDocument.CheckSources);
end;

procedure TTestSourceFiles.TestOpenFromDiskReadsDisk;
var
  Reason, FileName: string;
begin
  FDocument.SourceFiles.Add(PATTERN_FILE, 'not a pattern');
  AssertTrue(Reason, FDocument.OpenText(LayoutText(PATTERN_FILE, ''), Reason));
  FileName := ConcatPaths([GetTempDir(False), 'opensloper-source-files.slayout']);
  AssertTrue(Reason, WriteTextFileAtomic(FileName, LayoutText(ExamplePath(PATTERN_FILE), ''), Reason));
  try
    AssertTrue(Reason, FDocument.Open(FileName, Reason));
    AssertFalse('from disk', FDocument.Layout.Sources[0].InMemory);
    AssertEquals('read', '', FDocument.Layout.Sources[0].LoadError);
  finally
    DeleteFile(FileName);
  end;
end;

initialization
  RegisterTest(TTestSourceFiles);
end.
