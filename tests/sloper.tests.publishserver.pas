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
    // A placement as the layout's saved text has it
    function SavedPlacement(Index: integer): TJSONObject;
    function FirstPlacement: TJSONObject;
    // Where a placed piece's label is, a point inside it
    function LabelOf(Placement: integer): TJSONObject;
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
    procedure TestPress;
    procedure TestDragOneStep;
    procedure TestDragCancelled;
    procedure TestDragNothingHeld;
    procedure TestDragNote;
    procedure TestDropCopy;
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
  Sloper.API.LayoutServer, Sloper.Output.Layout, Sloper.Output.LayoutDocument, Sloper.Output.Preview,
  Sloper.Core.Geometry;

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

// The caller frees it
function TTestPublishServer.LabelOf(Placement: integer): TJSONObject;
var
  Index: integer;
  Piece: TJSONObject;
begin
  Call('publish_scene', TJSONObject.Create);
  for Index := 0 to Answer.Arrays['pieces'].Count - 1 do
  begin
    Piece := Answer.Arrays['pieces'].Objects[Index];
    if Piece.Integers['placement'] = Placement then
      Exit(TJSONObject(Piece.Objects['label'].Clone));
  end;
  Fail('no piece ' + IntToStr(Placement));
  Result := nil;
end;

procedure TTestPublishServer.TestPress;
var
  Spot: TJSONObject;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Spot := LabelOf(1);
  Call('publish_press', Spot);
  AssertEquals('the piece under its label', 1, Answer.Integers['placement']);
  AssertEquals('no note', -1, Answer.Integers['note']);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('a press changes nothing', Answer.Booleans['canUndo']);
  Call('publish_press', TJSONObject.Create(['x', -5000, 'y', -5000]));
  AssertEquals('nothing there', -1, Answer.Integers['placement']);
  Call('publish_press', TJSONObject.Create(['x', 10]));
  AssertEquals('needs both', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestPublishServer.TestDragOneStep;
var
  Spot: TJSONObject;
  X, Y, StartX, StartY: double;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  StartX := SavedPlacement(1).Floats['x'];
  StartY := SavedPlacement(1).Floats['y'];
  Spot := LabelOf(1);
  X := Spot.Floats['x'];
  Y := Spot.Floats['y'];
  Call('publish_press', Spot);
  Call('publish_drag', TJSONObject.Create(['x', X + 40.2, 'y', Y + 10]));
  AssertTrue('moving', Answer.Booleans['moving']);
  Call('publish_drag', TJSONObject.Create(['x', X + 120.2, 'y', Y + 30.1]));
  Call('publish_release', TJSONObject.Create);
  AssertEquals('followed the pointer, on the grid', RoundToStep(StartX + 120.2), SavedPlacement(1).Floats['x'], 1e-6);
  AssertEquals('down too', RoundToStep(StartY + 30.1), SavedPlacement(1).Floats['y'], 1e-6);
  Call('publish_state', TJSONObject.Create);
  AssertEquals('named', rsPreviewMove, Answer.Strings['undo']);
  Call('publish_undo', TJSONObject.Create);
  AssertEquals('one step back', StartX, SavedPlacement(1).Floats['x'], 1e-9);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('the only step', Answer.Booleans['canUndo']);
end;

procedure TTestPublishServer.TestDragCancelled;
var
  Spot: TJSONObject;
  StartX: double;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  StartX := SavedPlacement(0).Floats['x'];
  Spot := LabelOf(0);
  Call('publish_press', TJSONObject(Spot.Clone));
  Call('publish_drag', TJSONObject.Create(['x', Spot.Floats['x'] + 50, 'y', Spot.Floats['y']]));
  FreeAndNil(Spot);
  Call('publish_cancel', TJSONObject.Create);
  AssertEquals('put back', StartX, SavedPlacement(0).Floats['x'], 1e-9);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('no step', Answer.Booleans['canUndo']);
end;

procedure TTestPublishServer.TestDragNothingHeld;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'pattern', PATTERN_FILE]));
  Call('publish_press', TJSONObject.Create(['x', -5000, 'y', -5000]));
  Call('publish_drag', TJSONObject.Create(['x', 0, 'y', 0]));
  AssertFalse('nothing to move', Answer.Booleans['moving']);
  Call('publish_release', TJSONObject.Create);
  Call('publish_state', TJSONObject.Create);
  AssertFalse('no step', Answer.Booleans['canUndo']);
end;

// A note lies over the pieces, so a press on it holds the note
procedure TTestPublishServer.TestDragNote;
var
  Layout: TLayout;
  Text: string;
  Spread: TRect2;
  Middle: TVec2;
begin
  Layout := TLayout.Create;
  try
    Layout.AddSource(PATTERN_FILE, '', '');
    Layout.AddNote('Cut on the bias', 100, 100, 10);
    Spread := NoteBounds(Layout.Notes[0], Layout.FieldValues('', ''));
    Text := Layout.SaveToText;
  finally
    FreeAndNil(Layout);
  end;
  Middle := Vec2((Spread.MinX + Spread.MaxX) / 2, (Spread.MinY + Spread.MaxY) / 2);
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', Text]));
  Call('publish_press', TJSONObject.Create(['x', Middle.X, 'y', Middle.Y]));
  AssertEquals('the note', 0, Answer.Integers['note']);
  AssertEquals('not a piece', -1, Answer.Integers['placement']);
  Call('publish_drag', TJSONObject.Create(['x', Middle.X + 20, 'y', Middle.Y]));
  Call('publish_release', TJSONObject.Create);
  Call('publish_state', TJSONObject.Create);
  AssertEquals('named', rsPreviewMoveNote, Answer.Strings['undo']);
  AssertEquals('moved across', 120, Answer.Arrays['notes'].Objects[0].Floats['x'], 1e-6);
end;

procedure TTestPublishServer.TestDropCopy;
var
  Waiting: integer;
begin
  Call('publish_open', TJSONObject.Create(['files', Files([PATTERN_FILE, SET_FILE]), 'layout', WaitingLayout]));
  Waiting := Answer.Arrays['tray'].Count;
  Call('publish_drop_copy', TJSONObject.Create(['index', 0, 'x', 300, 'y', 400]));
  AssertEquals('the first placement', 0, Answer.Integers['placed']);
  Call('publish_state', TJSONObject.Create);
  AssertEquals('one fewer waiting', Waiting - 1, Answer.Arrays['tray'].Count);
  AssertEquals('named as the desktop', rsLayoutPlaceOne, Answer.Strings['undo']);
  Call('publish_drop_copy', TJSONObject.Create(['index', 99, 'x', 0, 'y', 0]));
  AssertEquals('no such copy', RPC_REFUSED, ErrorCode);
  Call('publish_drop_copy', TJSONObject.Create(['index', 0]));
  AssertEquals('needs a point', RPC_INVALID_PARAMS, ErrorCode);
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

function TTestPublishServer.SavedPlacement(Index: integer): TJSONObject;
var
  Err: string;
begin
  Call('publish_save', TJSONObject.Create);
  FreeAndNil(FSaved);
  if not ParseJSONObject(Answer.Strings['text'], FSaved, Err) then
    Fail(Err);
  Result := FSaved.Arrays['placements'].Objects[Index];
end;

function TTestPublishServer.FirstPlacement: TJSONObject;
begin
  Result := SavedPlacement(0);
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
