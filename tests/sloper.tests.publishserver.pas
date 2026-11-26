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

// The web Publish app's methods, through the web engine's server as the page
// calls them: a layout opened from files given as text.
unit Sloper.Tests.PublishServer;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.API.EditorServer;

type
  TTestPublishServer = class(TOSTestCase)
  private
    FServer: TEditorApiServer;
    FReply: TJSONObject;
    // The layout's saved text, read by FirstPlacement
    FSaved: TJSONObject;
    procedure Call(const Method: string; Params: TJSONObject);
    function Answer: TJSONObject;
    function ErrorCode: integer;
    // A files list with the skirt block example's files of these names
    function Files(const Names: array of string): TJSONArray;
    function Missing: string;
    // The first placement as the layout's saved text has it
    function FirstPlacement: TJSONObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOpenPattern;
    procedure TestMissingSetNamed;
    procedure TestAddFilesReadsAgain;
    procedure TestOpenLayout;
    procedure TestOpenNeedsLayoutOrPattern;
    procedure TestBadFilesRefused;
    procedure TestBadLayoutRefused;
    procedure TestState;
    procedure TestScene;
    procedure TestPieceAt;
    procedure TestPackUndoRedo;
    procedure TestPlaceWaiting;
    procedure TestTurnFlip;
    procedure TestUnplaceToTray;
    procedure TestPlaceCopy;
    procedure TestPieceEditRefused;
    procedure TestSave;
    procedure TestExport;
    procedure TestExportRefused;
    procedure TestNotTools;
  end;

implementation

uses
  base64, Sloper.API.Rpc, Sloper.API.MCP, Sloper.API.Methods, Sloper.API.PublishServer, Sloper.Core.JSON,
  Sloper.API.LayoutServer, Sloper.Output.Layout, Sloper.Output.LayoutDocument;

const
  PATTERN_FILE = 'skirt-darts.sloper';
  SET_FILE = 'skirt.slm';

function ExampleText(const FileName: string): string;
var
  Reason: string;
begin
  if not ReadTextFile(ConcatPaths([ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))), 'docs', 'examples',
    'skirt-block', FileName]), Result, Reason) then
    raise Exception.Create(Reason);
end;

procedure TTestPublishServer.SetUp;
begin
  FServer := TEditorApiServer.Create;
  FReply := nil;
  FSaved := nil;
end;

procedure TTestPublishServer.TearDown;
begin
  FreeAndNil(FSaved);
  FreeAndNil(FReply);
  FreeAndNil(FServer);
end;

procedure TTestPublishServer.Call(const Method: string; Params: TJSONObject);
var
  Request: TJSONObject;
  Err: string;
begin
  FreeAndNil(FReply);
  Request := TJSONObject.Create(['jsonrpc', '2.0', 'id', 1, 'method', Method, 'params', Params]);
  try
    if not ParseJSONObject(FServer.HandleLine(Request.AsJSON), FReply, Err) then
      Fail(Err);
  finally
    FreeAndNil(Request);
  end;
end;

function TTestPublishServer.Answer: TJSONObject;
begin
  if not Assigned(FReply.Find('result')) then
    Fail('Expected a result: ' + FReply.AsJSON);
  Result := FReply.Objects['result'];
end;

function TTestPublishServer.ErrorCode: integer;
begin
  if not Assigned(FReply.Find('error')) then
    Fail('Expected an error: ' + FReply.AsJSON);
  Result := FReply.Objects['error'].Integers['code'];
end;

function TTestPublishServer.Files(const Names: array of string): TJSONArray;
var
  Name: string;
begin
  Result := TJSONArray.Create;
  for Name in Names do
    Result.Add(TJSONObject.Create(['path', Name, 'text', ExampleText(Name)]));
end;

function TTestPublishServer.Missing: string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to Answer.Arrays['missing'].Count - 1 do
    Result := Result + Answer.Arrays['missing'].Strings[Index] + ';';
end;

procedure TTestPublishServer.TestOpenPattern;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  AssertEquals('named after the pattern', 'skirt-darts', Answer.Strings['name']);
  AssertEquals('nothing missing', '', Missing);
  AssertTrue('every piece placed', Answer.Integers['placed'] > 0);
  AssertEquals('none waiting', 0, Answer.Integers['unplaced']);
end;

procedure TTestPublishServer.TestMissingSetNamed;
var
  Problems: string;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE]), 'pattern', PATTERN_FILE]));
  AssertEquals('the pattern''s set', SET_FILE + ';', Missing);
  Problems := Answer.Arrays['problems'].AsJSON;
  AssertTrue(Problems, Pos(SET_FILE, Problems) > 0);
end;

procedure TTestPublishServer.TestAddFilesReadsAgain;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_add_files', TJSONObject.Create(['files', Files([SET_FILE])]));
  AssertEquals('found', '', Missing);
  AssertEquals('its pieces wait', 0, Answer.Integers['placed']);
  AssertTrue('to be placed', Answer.Integers['unplaced'] > 0);
end;

procedure TTestPublishServer.TestOpenLayout;
var
  Layout: TLayout;
  Text: string;
begin
  Layout := TLayout.Create;
  try
    Layout.Name := 'Skirt on A4';
    Layout.AddSource(PATTERN_FILE, '', '');
    Text := Layout.SaveToText;
  finally
    FreeAndNil(Layout);
  end;
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', Text]));
  AssertEquals('its own name', 'Skirt on A4', Answer.Strings['name']);
  AssertEquals('nothing missing', '', Missing);
  AssertTrue('pieces to place', Answer.Integers['unplaced'] > 0);
end;

procedure TTestPublishServer.TestOpenNeedsLayoutOrPattern;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE])]));
  AssertEquals(RPC_INVALID_PARAMS, ErrorCode);
  AssertEquals(rsPublishNeedsSource, FReply.Objects['error'].Strings['message']);
end;

procedure TTestPublishServer.TestBadFilesRefused;
begin
  Call('publish_open', TJSONObject.Create(['pattern', PATTERN_FILE]));
  AssertEquals('no files', RPC_INVALID_PARAMS, ErrorCode);
  Call('publish_open', TJSONObject.Create(['files', TJSONArray.Create([TJSONObject.Create(['path', PATTERN_FILE])]),
    'pattern', PATTERN_FILE]));
  AssertEquals('a file with no text', RPC_INVALID_PARAMS, ErrorCode);
  Call('publish_add_files', TJSONObject.Create(['files', TJSONArray.Create(['a.sloper'])]));
  AssertEquals('a file that is no object', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestPublishServer.TestBadLayoutRefused;
begin
  Call('publish_open', TJSONObject.Create(['files', TJSONArray.Create, 'layout', '{"format": "something else"}']));
  AssertEquals(RPC_REFUSED, ErrorCode);
end;

procedure TTestPublishServer.TestState;
begin
  Call('publish_state', TJSONObject.Create);
  AssertEquals('an empty layout', 0, Answer.Integers['placed']);
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_state', TJSONObject.Create);
  AssertEquals('as open left it', SET_FILE + ';', Missing);
end;

procedure TTestPublishServer.TestScene;
var
  Scene, Piece: TJSONObject;
  Placed: integer;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Placed := Answer.Integers['placed'];
  Call('publish_scene', TJSONObject.Create);
  Scene := Answer;
  AssertTrue('tiled by default', Scene.Booleans['tiled']);
  AssertTrue('with a cover', Scene.Find('cover').JSONType = jtObject);
  AssertTrue('pages', Scene.Arrays['pages'].Count > 0);
  AssertEquals('A1 first', 'A1', Scene.Arrays['pages'].Objects[0].Strings['caption']);
  AssertEquals('every placed piece', Placed, Scene.Arrays['pieces'].Count);
  Piece := Scene.Arrays['pieces'].Objects[0];
  AssertEquals('the first placement', 0, Piece.Integers['placement']);
  AssertTrue('an outline', Piece.Arrays['cutLine'].Count >= 6);
  AssertEquals('as x, y pairs', 0, Piece.Arrays['cutLine'].Count mod 2);
  AssertTrue('labelled', Piece.Find('label').JSONType = jtObject);
  AssertTrue('a new layout''s information block', Scene.Arrays['titleBoxes'].Count > 0);
  AssertTrue('its lines', Scene.Objects['title'].Arrays['lines'].Count > 0);
end;

procedure TTestPublishServer.TestPieceAt;
var
  Piece, Spot: TJSONObject;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_scene', TJSONObject.Create);
  Piece := Answer.Arrays['pieces'].Objects[1];
  Spot := TJSONObject(Piece.Objects['label'].Clone);
  try
    Call('publish_at', Spot.Clone as TJSONObject);
    AssertEquals('the piece under its label', 1, Answer.Integers['placement']);
  finally
    FreeAndNil(Spot);
  end;
  Call('publish_at', TJSONObject.Create(['x', -5000, 'y', -5000]));
  AssertEquals('nothing there', -1, Answer.Integers['placement']);
  Call('publish_at', TJSONObject.Create(['x', 10]));
  AssertEquals('needs both', RPC_INVALID_PARAMS, ErrorCode);
end;

// The skirt's layout text, its pieces waiting in the tray
function WaitingLayout: string;
var
  Layout: TLayout;
begin
  Layout := TLayout.Create;
  try
    Layout.Name := 'Skirt';
    Layout.AddSource(PATTERN_FILE, '', '');
    Result := Layout.SaveToText;
  finally
    FreeAndNil(Layout);
  end;
end;

procedure TTestPublishServer.TestPackUndoRedo;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  AssertFalse('nothing to undo', Answer.Booleans['canUndo']);
  Call('publish_pack', TJSONObject.Create);
  AssertTrue('packed', Answer.Booleans['done']);
  Call('publish_state', TJSONObject.Create);
  AssertTrue('one step', Answer.Booleans['canUndo']);
  AssertEquals('named', rsLayoutChangePack, Answer.Strings['undo']);
  Call('publish_undo', TJSONObject.Create);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('undone', Answer.Booleans['canUndo']);
  AssertTrue('to redo', Answer.Booleans['canRedo']);
  Call('publish_redo', TJSONObject.Create);
  Call('publish_state', TJSONObject.Create);
  AssertTrue('redone', Answer.Booleans['canUndo']);
  Call('publish_redo', TJSONObject.Create);
  AssertEquals('nothing to redo', RPC_REFUSED, ErrorCode);
end;

procedure TTestPublishServer.TestPlaceWaiting;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', WaitingLayout]));
  AssertTrue('waiting', Answer.Integers['unplaced'] > 0);
  Call('publish_place_pieces', TJSONObject.Create);
  AssertTrue('placed some', Answer.Integers['placed'] > 0);
  Call('publish_state', TJSONObject.Create);
  AssertEquals('none waiting', 0, Answer.Integers['unplaced']);
  AssertTrue('changed', Answer.Booleans['modified']);
end;

function TTestPublishServer.FirstPlacement: TJSONObject;
var
  Err: string;
begin
  Call('publish_save', TJSONObject.Create);
  FreeAndNil(FSaved);
  if not ParseJSONObject(Answer.Strings['text'], FSaved, Err) then
    Fail(Err);
  Result := FSaved.Arrays['placements'].Objects[0];
end;

procedure TTestPublishServer.TestTurnFlip;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_turn', TJSONObject.Create(['placement', 0]));
  AssertEquals('the piece', 0, Answer.Integers['placement']);
  Call('publish_state', TJSONObject.Create);
  AssertEquals('named as the desktop', rsLayoutTurnPiece, Answer.Strings['undo']);
  AssertEquals('a quarter turn', 90, FirstPlacement.Integers['rotation']);
  Call('publish_flip', TJSONObject.Create(['placement', 0]));
  Call('publish_state', TJSONObject.Create);
  AssertEquals('flip named', rsLayoutFlipPiece, Answer.Strings['undo']);
  AssertTrue('flipped', FirstPlacement.Booleans['flipped']);
  Call('publish_undo', TJSONObject.Create);
  AssertFalse('flip undone', FirstPlacement.Booleans['flipped']);
  AssertEquals('turn kept', 90, FirstPlacement.Integers['rotation']);
end;

procedure TTestPublishServer.TestUnplaceToTray;
var
  Placed: integer;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Placed := Answer.Integers['placed'];
  AssertEquals('an empty tray', 0, Answer.Arrays['tray'].Count);
  Call('publish_unplace', TJSONObject.Create(['placement', 0]));
  Call('publish_state', TJSONObject.Create);
  AssertEquals('one fewer placed', Placed - 1, Answer.Integers['placed']);
  AssertEquals('in the tray', 1, Answer.Arrays['tray'].Count);
  AssertTrue('captioned', Answer.Arrays['tray'].Objects[0].Strings['caption'] <> '');
  AssertTrue('can go back', Answer.Arrays['tray'].Objects[0].Booleans['canPlace']);
  AssertEquals('named as the desktop', rsLayoutUnplacePiece, Answer.Strings['undo']);
end;

procedure TTestPublishServer.TestPlaceCopy;
var
  Waiting: integer;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', WaitingLayout]));
  Waiting := Answer.Arrays['tray'].Count;
  AssertTrue('waiting', Waiting > 1);
  AssertEquals('as counted', Answer.Integers['unplaced'], Waiting);
  Call('publish_place_copy', TJSONObject.Create(['index', 1]));
  AssertEquals('the first placement', 0, Answer.Integers['placed']);
  Call('publish_state', TJSONObject.Create);
  AssertEquals('one placed', 1, Answer.Integers['placed']);
  AssertEquals('one fewer waiting', Waiting - 1, Answer.Arrays['tray'].Count);
  AssertEquals('named as the desktop', rsLayoutPlaceOne, Answer.Strings['undo']);
end;

procedure TTestPublishServer.TestPieceEditRefused;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_turn', TJSONObject.Create(['placement', 999]));
  AssertEquals('no such piece', RPC_REFUSED, ErrorCode);
  Call('publish_flip', TJSONObject.Create);
  AssertEquals('placement needed', RPC_INVALID_PARAMS, ErrorCode);
  Call('publish_unplace', TJSONObject.Create(['placement', 0.5]));
  AssertEquals('a whole number', RPC_INVALID_PARAMS, ErrorCode);
  Call('publish_place_copy', TJSONObject.Create(['index', 0]));
  AssertEquals('an empty tray', RPC_REFUSED, ErrorCode);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('nothing changed', Answer.Booleans['canUndo']);
end;

procedure TTestPublishServer.TestSave;
var
  Text: string;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  AssertTrue('a new layout is not saved', Answer.Booleans['modified']);
  Call('publish_save', TJSONObject.Create);
  Text := Answer.Strings['text'];
  AssertTrue(Text, Pos('"placements"', Text) > 0);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('saved', Answer.Booleans['modified']);
  // It opens again as it was
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', Text]));
  AssertFalse('as saved', Answer.Booleans['modified']);
  AssertTrue('its pieces placed', Answer.Integers['placed'] > 0);
end;

procedure TTestPublishServer.TestExport;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_export', TJSONObject.Create(['format', 'pdf']));
  AssertEquals('a PDF', '%PDF-', Copy(DecodeStringBase64(Answer.Strings['base64']), 1, 5));
  Call('publish_export', TJSONObject.Create(['format', 'svg']));
  AssertTrue('an SVG', Pos('<svg', DecodeStringBase64(Answer.Strings['base64'])) > 0);
  Call('publish_export', TJSONObject.Create(['format', 'dxf']));
  AssertTrue('a DXF', Pos('SECTION', DecodeStringBase64(Answer.Strings['base64'])) > 0);
  Call('publish_export', TJSONObject.Create(['format', 'machine-dxf']));
  AssertEquals('not on the web yet', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestPublishServer.TestExportRefused;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', WaitingLayout]));
  Call('publish_export', TJSONObject.Create(['format', 'pdf']));
  AssertEquals('nothing placed', RPC_REFUSED, ErrorCode);
end;

procedure TTestPublishServer.TestNotTools;
var
  Tools: TJSONArray;
  Index: integer;
  Method: TApiMethod;
  ToolName: string;
begin
  Tools := McpTools;
  try
    for Index := 0 to Tools.Count - 1 do
    begin
      ToolName := Tools.Objects[Index].Strings['name'];
      AssertFalse(ToolName, ToolName.StartsWith(PUBLISH_PREFIX));
    end;
  finally
    FreeAndNil(Tools);
  end;
  AssertTrue('its own table', Length(PublishMethods) > 0);
  for Method in PublishMethods do
    AssertTrue(Method.Name, Method.Name.StartsWith(PUBLISH_PREFIX));
end;

initialization
  RegisterTest(TTestPublishServer);
end.
