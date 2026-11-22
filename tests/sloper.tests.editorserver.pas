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

// Tests of the editor_ methods the web editor calls: the scene, snapping,
// picking and adding a point from a click.
unit Sloper.Tests.EditorServer;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, fpjson, Sloper.Tests.TestCase, Sloper.API.EditorServer, Sloper.API.Rpc;

type
  TTestEditorServer = class(TOSTestCase)
  private
    FServer: TEditorApiServer;
    FReply: TJSONObject;
    procedure Call(const Method: string; const Params: string = '{}');
    function Answer: TJSONObject;
    function ErrorCode: integer;
    // The ID of the object with this name
    function IdOf(const AName: string): integer;
    // A square of four points, A to D, 100 mm a side, with outline edges, made a piece
    procedure AddSquare;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestScene;
    procedure TestSceneOfEmptyPattern;
    procedure TestSnapToPoint;
    procedure TestSnapToEdge;
    procedure TestSnapFree;
    procedure TestObjectsAt;
    procedure TestObjectsInBox;
    procedure TestAddPointOnEdge;
    // A click on a point picks it and changes nothing
    procedure TestAddPointOnExistingPoint;
    procedure TestMissingParamRefused;
    // Claude is not offered the editor's methods as tools
    procedure TestNotOfferedAsTools;
    // The Automation API's methods still answer
    procedure TestApiMethodsStillServed;
  end;

implementation

uses
  Sloper.Core.JSON, Sloper.API.Mcp;

const
  TOLERANCE = 1e-6;

procedure TTestEditorServer.SetUp;
begin
  FServer := TEditorApiServer.Create;
  FReply := nil;
end;

procedure TTestEditorServer.TearDown;
begin
  FreeAndNil(FReply);
  FreeAndNil(FServer);
end;

procedure TTestEditorServer.Call(const Method, Params: string);
var
  Err: string;
begin
  FreeAndNil(FReply);
  if not ParseJSONObject(FServer.HandleLine('{"jsonrpc": "2.0", "id": 1, "method": "' + Method + '", "params": ' +
    Params + '}'), FReply, Err) then
    Fail(Err);
end;

function TTestEditorServer.Answer: TJSONObject;
begin
  if not Assigned(FReply.Find('result')) then
    Fail('Expected a result: ' + FReply.AsJSON);
  Result := TJSONObject(FReply.Find('result'));
end;

function TTestEditorServer.ErrorCode: integer;
begin
  if not Assigned(FReply.Find('error')) then
    Fail('Expected an error: ' + FReply.AsJSON);
  Result := TJSONObject(FReply.Find('error')).Get('code', 0);
end;

function TTestEditorServer.IdOf(const AName: string): integer;
begin
  Call('get_object', '{"name": "' + AName + '"}');
  Result := Answer.Get('id', 0);
end;

procedure TTestEditorServer.AddSquare;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "B", "x": 100, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "C", "x": 100, "y": 100}');
  Call('add_point', '{"type": "freePoint", "name": "D", "x": 0, "y": 100}');
  Call('add_edge', '{"type": "line", "start": "A", "end": "B", "role": "outline"}');
  Call('add_edge', '{"type": "line", "start": "B", "end": "C", "role": "outline"}');
  Call('add_edge', '{"type": "line", "start": "C", "end": "D", "role": "outline"}');
  Call('add_edge', '{"type": "line", "start": "D", "end": "A", "role": "outline"}');
  Call('create_piece', '{"x": 50, "y": 50, "name": "Flap"}');
  Answer;
end;

procedure TTestEditorServer.TestScene;
var
  Points, Edges, Pieces, Line: TJSONArray;
  Point, Edge: TJSONObject;
  IdC: integer;
begin
  AddSquare;
  IdC := IdOf('C');
  Call('editor_scene');
  Points := Answer.Arrays['points'];
  Edges := Answer.Arrays['edges'];
  Pieces := Answer.Arrays['pieces'];
  AssertEquals('points', 4, Points.Count);
  AssertEquals('edges', 4, Edges.Count);
  AssertEquals('pieces', 1, Pieces.Count);
  AssertTrue('nothing isolated', Answer.Nulls['isolated']);

  Point := Points.Objects[2];
  AssertEquals('point name', 'C', Point.Strings['name']);
  AssertEquals('point id', IdC, Point.Integers['id']);
  AssertNear('point x', 100, Point.Floats['x'], TOLERANCE);
  AssertNear('point y', 100, Point.Floats['y'], TOLERANCE);
  AssertEquals('point state', 'valid', Point.Strings['state']);
  AssertFalse('point locked', Point.Booleans['locked']);
  AssertTrue('not a copy', Point.Nulls['copyOf']);

  Edge := Edges.Objects[0];
  AssertEquals('edge role', 'outline', Edge.Strings['role']);
  Line := Edge.Arrays['line'];
  AssertEquals('a line is its two ends, x and y', 4, Line.Count);
  AssertNear('starts at A', 0, Line.Floats[0], TOLERANCE);
  AssertNear('ends at B', 100, Line.Floats[2], TOLERANCE);
  AssertFalse('no other edge on it', Assigned(Edge.Find('slot')));

  AssertEquals('piece name', 'Flap', Pieces.Objects[0].Strings['name']);
  AssertTrue('cut line round the square', Pieces.Objects[0].Arrays['cutLine'].Count >= 8);
  AssertTrue('piece fill', Pieces.Objects[0].Strings['fillStyle'] <> '');
end;

procedure TTestEditorServer.TestSceneOfEmptyPattern;
begin
  Call('editor_scene');
  AssertEquals('no points', 0, Answer.Arrays['points'].Count);
  AssertEquals('no edges', 0, Answer.Arrays['edges'].Count);
  AssertEquals('no pieces', 0, Answer.Arrays['pieces'].Count);
end;

procedure TTestEditorServer.TestSnapToPoint;
var
  IdB: integer;
begin
  AddSquare;
  IdB := IdOf('B');
  Call('editor_snap', '{"x": 100.5, "y": 0.5, "radius": 2}');
  AssertEquals('kind', 'point', Answer.Strings['kind']);
  AssertNear('at B', 100, Answer.Floats['x'], TOLERANCE);
  AssertEquals('works from B', IdB, Answer.Arrays['objects'].Integers[0]);
  AssertTrue('described', Pos('B', Answer.Strings['description']) > 0);
end;

procedure TTestEditorServer.TestSnapToEdge;
begin
  AddSquare;
  Call('editor_snap', '{"x": 50, "y": 1, "radius": 2}');
  AssertEquals('kind', 'edge', Answer.Strings['kind']);
  AssertNear('on the edge', 0, Answer.Floats['y'], 0.1);
  AssertEquals('one edge', 1, Answer.Arrays['objects'].Count);
end;

procedure TTestEditorServer.TestSnapFree;
begin
  AddSquare;
  Call('editor_snap', '{"x": 300, "y": 250, "radius": 2}');
  AssertEquals('kind', 'free', Answer.Strings['kind']);
  AssertNear('where clicked', 300, Answer.Floats['x'], TOLERANCE);
  AssertNear('where clicked down', 250, Answer.Floats['y'], TOLERANCE);
end;

procedure TTestEditorServer.TestObjectsAt;
var
  Objects: TJSONArray;
  IdB, IdFlap: integer;
begin
  AddSquare;
  IdB := IdOf('B');
  IdFlap := IdOf('Flap');
  Call('editor_objects_at', '{"x": 99.5, "y": 0, "pointRadius": 2, "edgeRadius": 2}');
  Objects := Answer.Arrays['objects'];
  AssertTrue('point, edges and piece', Objects.Count >= 3);
  AssertEquals('the point first', IdB, Objects.Integers[0]);
  Call('editor_objects_at', '{"x": 50, "y": 50, "pointRadius": 2, "edgeRadius": 2}');
  AssertEquals('inside, only the piece', 1, Answer.Arrays['objects'].Count);
  AssertEquals('the piece', IdFlap, Answer.Arrays['objects'].Integers[0]);
end;

procedure TTestEditorServer.TestObjectsInBox;
begin
  AddSquare;
  Call('editor_objects_in_box', '{"minX": -1, "minY": -1, "maxX": 101, "maxY": 1}');
  // A and B, and the edge between them
  AssertEquals('top side', 3, Answer.Arrays['objects'].Count);
  Call('editor_objects_in_box', '{"minX": -1, "minY": -1, "maxX": 101, "maxY": 101}');
  AssertEquals('all but the piece, whose allowance lies outside', 8, Answer.Arrays['objects'].Count);
  Call('editor_objects_in_box', '{"minX": -100, "minY": -100, "maxX": 200, "maxY": 200}');
  AssertEquals('everything', 9, Answer.Arrays['objects'].Count);
end;

procedure TTestEditorServer.TestAddPointOnEdge;
var
  Id: integer;
begin
  AddSquare;
  Call('editor_add_point', '{"x": 40, "y": 0.5, "radius": 2}');
  AssertFalse('made', Answer.Booleans['existing']);
  AssertNear('on the edge', 0, Answer.Floats['y'], 0.1);
  Id := Answer.Integers['id'];
  AssertEquals('a point along the edge', 'alongEdgePoint', Answer.Strings['type']);
  Call('undo');
  Call('get_object', '{"id": ' + IntToStr(Id) + '}');
  AssertEquals('undone in one step', RPC_REFUSED, ErrorCode);
end;

procedure TTestEditorServer.TestAddPointOnExistingPoint;
begin
  AddSquare;
  Call('editor_add_point', '{"x": 0.5, "y": 99.5, "radius": 2}');
  AssertTrue('existing', Answer.Booleans['existing']);
  AssertEquals('D', 'D', Answer.Strings['name']);
  Call('editor_scene');
  AssertEquals('no point added', 4, Answer.Arrays['points'].Count);
  // The last step is still the piece
  Call('undo');
  Call('editor_scene');
  AssertEquals('undo took the piece', 0, Answer.Arrays['pieces'].Count);
end;

procedure TTestEditorServer.TestMissingParamRefused;
begin
  Call('editor_snap', '{"x": 1, "radius": 2}');
  AssertEquals('no y', RPC_INVALID_PARAMS, ErrorCode);
  Call('editor_objects_in_box', '{"minX": 0, "minY": 0, "maxX": 1}');
  AssertEquals('no maxY', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestEditorServer.TestNotOfferedAsTools;
var
  Tools: TJSONArray;
  Index: integer;
  ToolName: string;
begin
  Tools := McpTools;
  try
    for Index := 0 to Tools.Count - 1 do
    begin
      ToolName := Tools.Objects[Index].Strings['name'];
      AssertFalse(ToolName, ToolName.StartsWith('editor_'));
    end;
  finally
    FreeAndNil(Tools);
  end;
  AssertTrue('the editor has its own table', Length(EditorMethods) > 0);
end;

procedure TTestEditorServer.TestApiMethodsStillServed;
begin
  AddSquare;
  Call('list_objects');
  Answer;
  Call('no_such_method');
  AssertEquals('unknown', RPC_METHOD_NOT_FOUND, ErrorCode);
end;

initialization
  RegisterTest(TTestEditorServer);

end.
