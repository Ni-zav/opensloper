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

// The publish and drape apps' tools for the Claude tab: methods on the open
// layout and drape, on the example patterns.
unit Sloper.Tests.AppTools;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.API.Methods, Sloper.Output.LayoutDocument,
  Sloper.Document.DrapeDocument, Sloper.API.LayoutServer, Sloper.API.DrapeServer;

type
  TTestLayoutTools = class(TOSTestCase)
  private
    FDocument: TLayoutDocument;
    FServer: TLayoutApiServer;
    FAnswer: TJSONData;
    // The reply, kept until the next call or the end of the test
    function Call(const Method: string; const ParamsText: string = '{}'): TJSONObject;
    // The refusal's message; fails when the call is not refused
    function Refusal(const Method, ParamsText: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryMethodAnswers;
    procedure TestState;
    procedure TestMovePieceAndUndo;
    procedure TestBadPlacementsRefused;
    procedure TestOutputAndPack;
    procedure TestNotesAndTitle;
    procedure TestRender;
    procedure TestWaitsForTheUser;
  end;

  TTestDrapeTools = class(TOSTestCase)
  private
    FDocument: TDrapeDocument;
    FServer: TDrapeApiServer;
    FAnswer: TJSONData;
    function Call(const Method: string; const ParamsText: string = '{}'): TJSONObject;
    function Refusal(const Method, ParamsText: string): string;
    function Position(Answer: TJSONObject): TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryMethodAnswers;
    procedure TestState;
    procedure TestRoundTheBody;
    procedure TestFlipAndTurn;
    procedure TestAlignToSeam;
    procedure TestUnplaceGuessAndUndo;
    procedure TestPlaceByNumbers;
    procedure TestRender;
  end;

implementation

uses
  Math, Sloper.API.Server, Sloper.API.Rpc, Sloper.API.MCP, Sloper.Core.Geometry3;

const
  CHANGE_PREFIX = 'Claude: ';

function ExamplePath(const Folder, FileName: string): string;
begin
  Result := ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs', 'examples', Folder, FileName]);
end;

function ParseParams(const Text: string): TJSONObject;
begin
  Result := TJSONObject(GetJSON(Text));
end;

{ TTestLayoutTools }

procedure TTestLayoutTools.SetUp;
begin
  FDocument := TLayoutDocument.Create;
  FDocument.NewForPattern(ExamplePath('tote-bag', 'tote-bag.sloper'));
  FServer := TLayoutApiServer.Create(FDocument);
  FServer.ChangePrefix := CHANGE_PREFIX;
end;

procedure TTestLayoutTools.TearDown;
begin
  FreeAndNil(FAnswer);
  FreeAndNil(FServer);
  FreeAndNil(FDocument);
end;

function TTestLayoutTools.Call(const Method: string; const ParamsText: string): TJSONObject;
var
  Params: TJSONObject;
begin
  FreeAndNil(FAnswer);
  Params := ParseParams(ParamsText);
  try
    FAnswer := FServer.CallMethod(Method, Params);
  finally
    FreeAndNil(Params);
  end;
  Result := TJSONObject(FAnswer);
end;

function TTestLayoutTools.Refusal(const Method, ParamsText: string): string;
begin
  Result := '';
  try
    Call(Method, ParamsText);
    Fail(Method + ' was not refused');
  except
    on Failure: EApiError do
      Result := Failure.Message;
  end;
end;

// Each method in the table is one the server runs: it may refuse missing
// parameters, but never says there is no such method
procedure TTestLayoutTools.TestEveryMethodAnswers;
var
  Method: TApiMethod;
  Tools: TJSONArray;
begin
  for Method in LayoutMethods do
  try
    Call(Method.Name);
  except
    on Failure: EApiError do
      AssertTrue(Method.Name + ': ' + Failure.Message, Failure.Code <> RPC_METHOD_NOT_FOUND);
  end;
  Tools := McpToolsFor(LayoutMethods);
  try
    AssertEquals('a tool each', Length(LayoutMethods), Tools.Count);
  finally
    FreeAndNil(Tools);
  end;
end;

procedure TTestLayoutTools.TestState;
var
  Answer: TJSONObject;
begin
  Answer := Call('layout_state');
  AssertEquals('tote-bag.slayout', Answer.Get('file', ''));
  AssertEquals('one pattern', 1, Answer.Arrays['sources'].Count);
  AssertEquals('tote-bag.sloper', Answer.Arrays['sources'].Objects[0].Get('pattern', ''));
  AssertTrue('pieces placed', Answer.Get('placed', 0) > 0);
  AssertEquals('tiled', Answer.Objects['output'].Get('kind', ''));
  Answer := Call('list_pieces');
  AssertTrue('listed', Answer.Arrays['placed'].Count > 0);
  AssertEquals('by index', 0, Answer.Arrays['placed'].Objects[0].Get('index', -1));
end;

procedure TTestLayoutTools.TestMovePieceAndUndo;
var
  Answer: TJSONObject;
begin
  Answer := Call('set_placement', '{"index": 0, "x": 500, "y": 40, "rotation": 90, "flipped": true}');
  AssertEquals(500, Answer.Get('x', 0.0), 1e-9);
  AssertEquals(90, Answer.Get('rotation', 0));
  AssertTrue(Answer.Get('flipped', False));
  AssertEquals('one undo step, Claude''s', CHANGE_PREFIX + rsLayoutChangeMove, FDocument.UndoDescription);
  Answer := Call('undo');
  AssertEquals(CHANGE_PREFIX + rsLayoutChangeMove, Answer.Get('description', ''));
  AssertFalse('back as it was', FDocument.Layout.Placements[0].Flipped);
  Call('redo');
  AssertTrue('again', FDocument.Layout.Placements[0].Flipped);
end;

procedure TTestLayoutTools.TestBadPlacementsRefused;
begin
  AssertEquals(rsLayoutBadTurn, Refusal('set_placement', '{"index": 0, "rotation": 45}'));
  AssertEquals(Format(rsLayoutNoPiece, [99]), Refusal('set_placement', '{"index": 99}'));
  AssertTrue('a whole number', Refusal('remove_piece', '{"index": 0.5}') <> '');
  AssertFalse('nothing changed', FDocument.CanUndo);
end;

procedure TTestLayoutTools.TestOutputAndPack;
var
  Answer: TJSONObject;
begin
  Answer := Call('set_output', '{"kind": "material", "materialWidth": 1500, "materialLength": 0}');
  AssertEquals('material', Answer.Get('kind', ''));
  AssertEquals(1500, Answer.Get('materialWidth', 0.0), 1e-9);
  AssertTrue('an unknown kind', Refusal('set_output', '{"kind": "fabric"}') <> '');
  AssertEquals(Format(rsLayoutUnknownPaper, ['B9']), Refusal('set_output', '{"paper": "B9"}'));
  Answer := Call('pack');
  AssertTrue(Answer.Get('reason', ''), Answer.Get('done', False));
  AssertTrue('packed', Answer.Get('count', 0) > 0);
  Answer := Call('remove_piece', '{"index": 0}');
  AssertEquals('one waits', 1, Answer.Get('unplaced', 0));
  Answer := Call('place_pieces');
  AssertEquals('placed again', 1, Answer.Get('placed', 0));
end;

procedure TTestLayoutTools.TestNotesAndTitle;
var
  Answer: TJSONObject;
begin
  Answer := Call('add_note', '{"text": "Cut 2 in lining", "x": 10, "y": 20}');
  AssertEquals(Length(FDocument.Layout.Notes) - 1, Answer.Get('index', -1));
  AssertEquals('Cut 2 in lining', FDocument.Layout.Notes[High(FDocument.Layout.Notes)].Text);
  Answer := Call('set_title_block', '{"corner": "topRight", "fields": ["pattern.name", "date"]}');
  AssertEquals('topRight', Answer.Get('corner', ''));
  AssertEquals(2, Answer.Arrays['fields'].Count);
  AssertTrue('an unknown field', Refusal('set_title_block', '{"fields": ["client"]}') <> '');
  Answer := Call('remove_note', Format('{"index": %d}', [High(FDocument.Layout.Notes)]));
  AssertEquals(Format(rsLayoutNoNote, [99]), Refusal('remove_note', '{"index": 99}'));
end;

procedure TTestLayoutTools.TestRender;
var
  Answer: TJSONObject;
begin
  Answer := Call('render', '{"width": 400}');
  AssertEquals('png', Answer.Get('format', ''));
  AssertTrue('an image', Length(Answer.Get('png', '')) > 100);
end;

// A change of Claude's never lands in the middle of the user's drag
procedure TTestLayoutTools.TestWaitsForTheUser;
begin
  FDocument.BeginChange('Drag');
  try
    AssertEquals(rsLayoutBusy, Refusal('set_placement', '{"index": 0, "x": 1}'));
    Call('layout_state');
  finally
    FDocument.CancelChange;
  end;
end;

{ TTestDrapeTools }

procedure TTestDrapeTools.SetUp;
begin
  FDocument := TDrapeDocument.Create;
  // Every piece placed by a guess
  FDocument.NewForPattern(ExamplePath('bodice-block', 'bodice-block.sloper'));
  FServer := TDrapeApiServer.Create(FDocument);
  FServer.ChangePrefix := CHANGE_PREFIX;
end;

procedure TTestDrapeTools.TearDown;
begin
  FreeAndNil(FAnswer);
  FreeAndNil(FServer);
  FreeAndNil(FDocument);
end;

function TTestDrapeTools.Call(const Method: string; const ParamsText: string): TJSONObject;
var
  Params: TJSONObject;
begin
  FreeAndNil(FAnswer);
  Params := ParseParams(ParamsText);
  try
    FAnswer := FServer.CallMethod(Method, Params);
  finally
    FreeAndNil(Params);
  end;
  Result := TJSONObject(FAnswer);
end;

function TTestDrapeTools.Refusal(const Method, ParamsText: string): string;
begin
  Result := '';
  try
    Call(Method, ParamsText);
    Fail(Method + ' was not refused');
  except
    on Failure: EApiError do
      Result := Failure.Message;
  end;
end;

function TTestDrapeTools.Position(Answer: TJSONObject): TJSONObject;
begin
  Result := Answer.Objects['position'];
end;

procedure TTestDrapeTools.TestEveryMethodAnswers;
var
  Method: TApiMethod;
  Tools: TJSONArray;
begin
  for Method in DrapeMethods do
  try
    Call(Method.Name);
  except
    on Failure: EApiError do
      AssertTrue(Method.Name + ': ' + Failure.Message, Failure.Code <> RPC_METHOD_NOT_FOUND);
  end;
  Tools := McpToolsFor(DrapeMethods);
  try
    AssertEquals('a tool each', Length(DrapeMethods), Tools.Count);
  finally
    FreeAndNil(Tools);
  end;
end;

procedure TTestDrapeTools.TestState;
var
  Answer: TJSONObject;
begin
  Answer := Call('drape_state');
  AssertEquals('bodice-block.sdrape', Answer.Get('file', ''));
  AssertEquals('figure', Answer.Objects['body'].Get('kind', ''));
  AssertEquals('the back and front', 2, Answer.Get('placed', 0));
  Answer := Call('list_pieces');
  AssertEquals(2, Answer.Arrays['placed'].Count);
  AssertTrue('captioned', Pos('bodice-block', Answer.Arrays['placed'].Objects[0].Get('caption', '')) > 0);
  AssertNear('facing out of the screen', -1, Answer.Arrays['placed'].Objects[0].Objects['facing'].Get('y', 0.0), 1e-6);
end;

procedure TTestDrapeTools.TestRoundTheBody;
var
  Before, After: TJSONObject;
  X, Y: double;
begin
  Before := Call('list_pieces').Arrays['placed'].Objects[0];
  X := Before.Objects['position'].Get('x', 0.0);
  Y := Before.Objects['position'].Get('y', 0.0);
  After := Call('round_body', '{"index": 0, "angle": 90}');
  AssertNear('the same distance from the centre line', Hypot(X, Y), Hypot(Position(After).Get('x', 0.0),
    Position(After).Get('y', 0.0)), 1e-6);
  AssertNear('facing the body''s left now', 1, After.Objects['facing'].Get('x', 0.0), 1e-6);
  AssertEquals(CHANGE_PREFIX + rsDrapeChangeRound, FDocument.UndoDescription);
end;

procedure TTestDrapeTools.TestFlipAndTurn;
var
  Answer: TJSONObject;
begin
  Answer := Call('flip_piece', '{"index": 0}');
  AssertNear('facing in', 1, Answer.Objects['facing'].Get('y', 0.0), 1e-6);
  Answer := Call('turn_piece', '{"index": 0, "axis": "z", "angle": 180}');
  AssertNear('out again', -1, Answer.Objects['facing'].Get('y', 0.0), 1e-6);
  AssertTrue('an axis it knows', Refusal('turn_piece', '{"index": 0, "axis": "w", "angle": 10}') <> '');
end;

procedure TTestDrapeTools.TestAlignToSeam;
var
  Seams: TJSONArray;
  Name: string;
begin
  Seams := Call('list_seams', '{"index": 0}').Arrays['seams'];
  AssertTrue('sewn to the other', Seams.Count > 0);
  Name := Seams.Objects[0].Get('name', '');
  Call('align_to_seam', Format('{"index": 0, "seam": "%s"}', [Name]));
  AssertEquals(CHANGE_PREFIX + rsDrapeChangeAlign, FDocument.UndoDescription);
  AssertEquals(Format(rsDrapeNoSeam, ['Hem']), Refusal('align_to_seam', '{"index": 0, "seam": "Hem"}'));
end;

procedure TTestDrapeTools.TestUnplaceGuessAndUndo;
var
  Answer: TJSONObject;
begin
  Answer := Call('unplace_piece', '{"index": 1}');
  AssertEquals(1, Answer.Get('unplaced', 0));
  Answer := Call('guess_placements');
  AssertEquals(1, Answer.Get('placed', 0));
  Call('undo');
  Call('undo');
  AssertEquals('both back', 2, Length(FDocument.Drape.Items));
  AssertEquals(Format(rsDrapeNoItem, [7]), Refusal('flip_piece', '{"index": 7}'));
  AssertEquals(rsDrapeBadGap, Refusal('set_gap', '{"gap": -1}'));
  AssertNear('the gap', 30, Call('set_gap', '{"gap": 30}').Get('gap', 0.0), 1e-9);
end;

procedure TTestDrapeTools.TestPlaceByNumbers;
var
  Piece: TJSONObject;
  Answer: TJSONObject;
begin
  Piece := Call('list_pieces').Arrays['placed'].Objects[1].Clone as TJSONObject;
  try
    Answer := Call('place_piece', Format('{"source": %d, "piece": %d, "x": 0, "y": 250, "z": 1200, "turnZ": 180}',
      [Piece.Get('source', 0), Piece.Get('piece', 0)]));
    AssertNear('placed behind', 250, Position(Answer).Get('y', 0.0), 1e-9);
    AssertNear('facing the back', 1, Answer.Objects['facing'].Get('y', 0.0), 1e-6);
    AssertEquals(Format(rsDrapeNoSuchCopy, [1, 2]), Refusal('place_piece', Format('{"source": %d, "piece": %d, "copy": 2, ' +
      '"x": 0, "y": 0, "z": 0}', [Piece.Get('source', 0), Piece.Get('piece', 0)])));
  finally
    FreeAndNil(Piece);
  end;
end;

procedure TTestDrapeTools.TestRender;
var
  Answer: TJSONObject;
begin
  Answer := Call('render', '{"view": "left", "width": 300}');
  AssertEquals('left', Answer.Get('view', ''));
  AssertTrue('an image', Length(Answer.Get('png', '')) > 100);
end;

initialization
  RegisterTest(TTestLayoutTools);
  RegisterTest(TTestDrapeTools);
end.
