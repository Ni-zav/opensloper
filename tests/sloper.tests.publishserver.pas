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
    procedure Call(const Method: string; Params: TJSONObject);
    function Answer: TJSONObject;
    function ErrorCode: integer;
    // A files list with the skirt block example's files of these names
    function Files(const Names: array of string): TJSONArray;
    function Missing: string;
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
    procedure TestNotTools;
  end;

implementation

uses
  Sloper.API.Rpc, Sloper.API.MCP, Sloper.API.Methods, Sloper.API.PublishServer, Sloper.Core.JSON, Sloper.Output.Layout;

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
end;

procedure TTestPublishServer.TearDown;
begin
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
