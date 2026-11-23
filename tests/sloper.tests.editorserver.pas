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
    function Selected: integer;
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
    procedure TestLineTool;
    procedure TestLineTooShortIgnored;
    procedure TestCurveToolCarriesOn;
    procedure TestShapeTools;
    // A region with a piece already selects it
    procedure TestPieceTool;
    // A click on a notch removes it; on a seam line adds one
    procedure TestNotchTool;
    // Pieces' grainlines and notches, and markers, are in the scene
    procedure TestSceneMarks;
    // Contextual labels: the selection with what it reads and what reads it
    procedure TestLabelKeys;
    // Picking a seam's sides edge by edge, then making it as one step
    procedure TestSeamTool;
    procedure TestSeamInScene;
    // Notes as the canvas draws them, fields filled in
    procedure TestNotesInScene;
    // A note lies over whatever is under it
    procedure TestNoteHitFirst;
    procedure TestTextTool;
    // A callout's tip must be on something; its text goes where the second click is
    procedure TestCalloutTool;
    procedure TestMissingParamRefused;
    // Claude is not offered the editor's methods as tools
    procedure TestNotOfferedAsTools;
    // The Automation API's methods still answer
    procedure TestApiMethodsStillServed;
    procedure TestComplete;
    // The caret and the word's place count characters, not UTF-8 bytes
    procedure TestCompleteCountsCharacters;
    procedure TestCompleteForObject;
    procedure TestListObjects;
    procedure TestListVariables;
    procedure TestListMeasurements;
    procedure TestSuggest;
    procedure TestSuggestRefused;
    procedure TestTables;
    // What changed since last asked, as the desktop document tells its panels
    procedure TestChanges;
    procedure TestChangesAfterUndo;
    procedure TestChangesOnOpen;
    // A drag is one undo step, with the pattern worked out on every move
    procedure TestDragPoint;
    procedure TestDragCancel;
    procedure TestDragOneField;
    procedure TestDragNote;
    // While a drag is open, other changes wait
    procedure TestDragBlocksChanges;
    procedure TestDragRefusals;
    // The selected curves' handles, and the one under a place
    procedure TestHandles;
    procedure TestDragHandle;
    // A handle set by a formula is drawn but not dragged
    procedure TestHandleFormulaRefused;
    // A callout's tip snaps as it moves, changing nothing until it is dropped
    procedure TestDragCalloutTip;
    procedure TestCalloutTipRefusals;
    procedure TestBounds;
    // A list's click, Ctrl+click and Shift+click
    procedure TestListClick;
  private
    // A callout from B, its text at (150, -40); its ID
    function AddCallout: integer;
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

// The first ID the last tool click selected
function TTestEditorServer.Selected: integer;
begin
  if Answer.Nulls['select'] or (Answer.Arrays['select'].Count = 0) then
    Fail('Nothing selected: ' + FReply.AsJSON);
  Result := Answer.Arrays['select'].Integers[0];
end;

procedure TTestEditorServer.TestAddPointOnEdge;
var
  Id: integer;
begin
  AddSquare;
  Call('editor_tool_click', '{"tool": "point", "x": 40, "y": 0.5, "radius": 2}');
  AssertTrue('made', Answer.Booleans['done']);
  Id := Selected;
  Call('get_object', '{"id": ' + IntToStr(Id) + '}');
  AssertNear('on the edge', 0, Answer.Floats['y'], 0.1);
  AssertEquals('a point along the edge', 'alongEdgePoint', Answer.Strings['type']);
  Call('editor_changes');
  AssertEquals('its step', 'Add point', Answer.Strings['undo']);
  Call('undo');
  Call('get_object', '{"id": ' + IntToStr(Id) + '}');
  AssertEquals('undone in one step', RPC_REFUSED, ErrorCode);
end;

procedure TTestEditorServer.TestAddPointOnExistingPoint;
var
  IdD: integer;
begin
  AddSquare;
  IdD := IdOf('D');
  Call('editor_tool_click', '{"tool": "point", "x": 0.5, "y": 99.5, "radius": 2}');
  AssertFalse('no change', Answer.Booleans['done']);
  AssertEquals('D selected', IdD, Selected);
  Call('editor_scene');
  AssertEquals('no point added', 4, Answer.Arrays['points'].Count);
  // The last step is still the piece
  Call('undo');
  Call('editor_scene');
  AssertEquals('undo took the piece', 0, Answer.Arrays['pieces'].Count);
end;

procedure TTestEditorServer.TestLineTool;
var
  Line: integer;
begin
  Call('editor_tool_click', '{"tool": "line", "x": 0, "y": 0, "radius": 2}');
  AssertTrue('a first click', Answer.Booleans['started']);
  AssertFalse('no change yet', Answer.Booleans['done']);
  Call('editor_scene');
  AssertEquals('no point yet', 0, Answer.Arrays['points'].Count);
  Call('editor_tool_click', '{"tool": "line", "x": 100, "y": 0, "radius": 2, "start": {"x": 0, "y": 0, "radius": 2}}');
  AssertTrue('made', Answer.Booleans['done']);
  Line := Selected;
  AssertNear('the next starts at its end', 100, Answer.Objects['end'].Floats['x'], TOLERANCE);
  Call('get_object', '{"id": ' + IntToStr(Line) + '}');
  AssertEquals('a line', 'line', Answer.Strings['type']);
  AssertEquals('outline by default', 'outline', Answer.Strings['role']);
  AssertNear('its length', 100, Answer.Floats['length'], TOLERANCE);
  Call('editor_changes');
  AssertEquals('one step with its points', 'Add line', Answer.Strings['undo']);
  // Carrying on from the end, which is now a point
  Call('editor_tool_click', '{"tool": "line", "x": 100, "y": 50, "radius": 2, "start": {"x": 100, "y": 0, "radius": 2}, ' +
    '"role": "construction"}');
  Call('editor_scene');
  AssertEquals('three points, the end shared', 3, Answer.Arrays['points'].Count);
  // In drawing order, construction lines under the rest
  AssertEquals('the role given', 'construction', Answer.Arrays['edges'].Objects[0].Strings['role']);
  Call('undo');
  Call('undo');
  Call('editor_scene');
  AssertEquals('each line one step', 0, Answer.Arrays['points'].Count);
end;

procedure TTestEditorServer.TestLineTooShortIgnored;
begin
  Call('editor_tool_click', '{"tool": "line", "x": 10, "y": 10, "radius": 2, "start": {"x": 10, "y": 10.01, "radius": 2}}');
  AssertFalse('nothing', Answer.Booleans['done']);
  AssertEquals('and nothing said', '', Answer.Strings['message']);
end;

procedure TTestEditorServer.TestCurveToolCarriesOn;
var
  Curve: integer;
begin
  Call('editor_tool_click', '{"tool": "curve", "x": 100, "y": 0, "radius": 2, "start": {"x": 0, "y": 0, "radius": 2}}');
  Curve := Answer.Integers['curve'];
  Call('editor_tool_click', '{"tool": "curve", "x": 200, "y": 50, "radius": 2, "start": {"x": 100, "y": 0, "radius": 2}, ' +
    '"extend": ' + IntToStr(Curve) + '}');
  AssertTrue('carried on', Answer.Booleans['done']);
  AssertEquals('the same path', Curve, Answer.Integers['curve']);
  Call('editor_scene');
  AssertEquals('one edge', 1, Answer.Arrays['edges'].Count);
  Call('editor_changes');
  AssertEquals('its step', 'Carry curve on', Answer.Strings['undo']);
end;

procedure TTestEditorServer.TestShapeTools;
var
  Shape: integer;
begin
  Call('editor_tool_click', '{"tool": "circle", "x": 50, "y": 50, "radius": 2}');
  AssertTrue('a first click', Answer.Booleans['started']);
  AssertTrue('asks for the rim', Answer.Strings['message'] <> '');
  Call('editor_tool_snap', '{"tool": "circle", "x": 80, "y": 50, "radius": 2, "start": {"x": 50, "y": 50, "radius": 2}}');
  AssertTrue('the radius while choosing', Pos('30', Answer.Strings['description']) > 0);
  AssertNear('where it started', 50, Answer.Objects['start'].Floats['x'], TOLERANCE);
  Call('editor_tool_click', '{"tool": "circle", "x": 80, "y": 50, "radius": 2, "start": {"x": 50, "y": 50, "radius": 2}}');
  Shape := Selected;
  Call('get_object', '{"id": ' + IntToStr(Shape) + '}');
  AssertEquals('a circle', 'circle', Answer.Strings['type']);
  Call('editor_tool_click', '{"tool": "rectangle", "x": 300, "y": 200, "radius": 2, "start": {"x": 200, "y": 150, "radius": 2}}');
  AssertTrue('made', Answer.Booleans['done']);
  AssertEquals('four edges selected', 4, Answer.Arrays['select'].Count);
end;

procedure TTestEditorServer.TestPieceTool;
var
  Flap: integer;
begin
  AddSquare;
  Flap := IdOf('Flap');
  Call('editor_tool_click', '{"tool": "piece", "x": 50, "y": 50, "radius": 2}');
  AssertFalse('there already', Answer.Booleans['done']);
  AssertTrue('says so', Pos('Flap', Answer.Strings['message']) > 0);
  AssertEquals('and selects it', Flap, Selected);
  Call('undo');
  Call('editor_tool_click', '{"tool": "piece", "x": 50, "y": 50, "radius": 2}');
  AssertTrue('made again', Answer.Booleans['done']);
  Call('editor_tool_click', '{"tool": "piece", "x": 500, "y": 500, "radius": 2}');
  AssertFalse('no outline there', Answer.Booleans['done']);
  AssertTrue('says why', Answer.Strings['message'] <> '');
end;

procedure TTestEditorServer.TestNotchTool;
begin
  AddSquare;
  Call('editor_tool_click', '{"tool": "notch", "x": 50, "y": 0, "radius": 2}');
  AssertTrue('added', Answer.Booleans['done']);
  Call('editor_scene');
  AssertEquals('drawn: one segment', 4, Answer.Arrays['pieces'].Objects[0].Arrays['notches'].Count);
  Call('editor_changes');
  AssertEquals('its step', 'Add notch', Answer.Strings['undo']);
  Call('editor_tool_click', '{"tool": "notch", "x": 50, "y": 0.5, "radius": 2}');
  AssertTrue('removed', Answer.Booleans['done']);
  Call('editor_changes');
  AssertEquals('its step', 'Remove notch', Answer.Strings['undo']);
  Call('editor_tool_click', '{"tool": "notch", "x": 50, "y": 50, "radius": 2}');
  AssertFalse('no seam line there', Answer.Booleans['done']);
  AssertTrue('says so', Answer.Strings['message'] <> '');
end;

procedure TTestEditorServer.TestSceneMarks;
begin
  AddSquare;
  Call('set_marker', '{"name": "A", "marker": "hole", "size": 6}');
  Answer;
  Call('editor_scene');
  AssertTrue('the grainline drawn', Answer.Arrays['pieces'].Objects[0].Arrays['marks'].Count >= 4);
  AssertEquals('one marker', 1, Answer.Arrays['markers'].Count);
  AssertTrue('its strokes', Answer.Arrays['markers'].Objects[0].Arrays['strokes'].Count >= 8);
end;

procedure TTestEditorServer.TestLabelKeys;
var
  IdA, IdB, Flap: integer;
  Keys: string;
begin
  AddSquare;
  IdA := IdOf('A');
  IdB := IdOf('B');
  Flap := IdOf('Flap');
  Call('editor_label_keys', '{"mode": "none", "selection": [' + IntToStr(IdA) + ']}');
  AssertEquals('none', 0, Answer.Arrays['objects'].Count);
  Call('editor_label_keys', '{"selection": [' + IntToStr(IdA) + ']}');
  Keys := Answer.Arrays['objects'].AsJSON;
  AssertTrue('the selection', Pos(IntToStr(IdA), Keys) > 0);
  AssertTrue('not what is unrelated', Pos('[' + IntToStr(IdB) + ',', Keys + ',') = 0);
  Call('editor_label_keys', '{"mode": "all"}');
  AssertEquals('every point, edge and piece', 9, Answer.Arrays['objects'].Count);
  Call('editor_label_keys', '{"hover": "Flap"}');
  AssertEquals('the hovered piece', '[' + IntToStr(Flap) + ']', Answer.Arrays['objects'].AsJSON);
  Call('editor_label_keys', '{"selection": [999]}');
  AssertEquals('an unknown ID', RPC_REFUSED, ErrorCode);
end;

procedure TTestEditorServer.TestSeamTool;
var
  SideA, SideB: string;
begin
  AddSquare;
  Call('editor_seam_pick', '{"x": 50, "y": 0, "radius": 2, "sideA": [], "sideB": []}');
  AssertTrue('picked', Answer.Booleans['picked']);
  AssertEquals('on side A', 1, Answer.Arrays['sideA'].Count);
  AssertTrue('the progress', Pos('Side A', Answer.Strings['message']) > 0);
  AssertEquals('its line to draw', 1, Answer.Objects['lines'].Arrays['sideA'].Count);
  SideA := Answer.Arrays['sideA'].AsJSON;
  Call('editor_seam_pick', '{"sideA": ' + SideA + ', "sideB": [], "onB": true}');
  AssertTrue('Tab: side B', Pos('Side B', Answer.Strings['message']) > 0);
  Call('editor_seam_pick', '{"x": 50, "y": 100, "radius": 2, "sideA": ' + SideA + ', "sideB": [], "onB": true}');
  SideB := Answer.Arrays['sideB'].AsJSON;
  AssertEquals('on side B', 1, Answer.Arrays['sideB'].Count);
  Call('editor_seam_pick', '{"x": 50, "y": 100, "radius": 2, "sideA": ' + SideA + ', "sideB": ' + SideB + ', "onB": true}');
  AssertEquals('a second click takes it off', 0, Answer.Arrays['sideB'].Count);
  Call('editor_seam_pick', '{"x": 500, "y": 500, "radius": 2, "sideA": ' + SideA + ', "sideB": []}');
  AssertFalse('nothing there', Answer.Booleans['picked']);
  AssertEquals('the side kept', 1, Answer.Arrays['sideA'].Count);
  Call('editor_seam_make', '{"sideA": ' + SideA + ', "sideB": []}');
  AssertFalse('both sides needed', Answer.Booleans['done']);
  Call('editor_seam_make', '{"sideA": ' + SideA + ', "sideB": ' + SideB + '}');
  AssertTrue('made', Answer.Booleans['done']);
  Call('editor_changes');
  AssertEquals('one step', 'Add seam', Answer.Strings['undo']);
end;

procedure TTestEditorServer.TestSeamInScene;
var
  Piece: TJSONObject;
begin
  AddSquare;
  Call('editor_seam_pick', '{"x": 50, "y": 0, "radius": 2, "sideA": [], "sideB": []}');
  Call('editor_seam_make', '{"sideA": ' + Answer.Arrays['sideA'].AsJSON + ', "sideB": [{"piece": "Flap", "edge": ' +
    IntToStr(IdOf('Line_C_D')) + '}]}');
  Call('editor_scene');
  AssertEquals('the seam', 1, Answer.Arrays['seams'].Count);
  AssertEquals('side A', 1, Answer.Arrays['seams'].Objects[0].Arrays['sideA'].Count);
  AssertEquals('a chevron on each side, x, y and angle', 3, Answer.Arrays['seams'].Objects[0].Arrays['chevronsB'].Count);
  Piece := Answer.Arrays['pieces'].Objects[0];
  AssertTrue('the piece''s label', Pos('Flap', Piece.Strings['caption']) > 0);
  AssertNear('its middle', 50, Piece.Arrays['middle'].Floats[0], 1);
  AssertEquals('a chevron per edge', 12, Piece.Arrays['chevrons'].Count);
end;

procedure TTestEditorServer.TestNotesInScene;
var
  Note: TJSONObject;
begin
  Call('add_note', '{"text": "Cut 2\n{pattern.name}", "x": 10, "y": 20, "size": 12, "align": "centre"}');
  Answer;
  Call('editor_scene', '{"fileName": "skirt.sloper"}');
  AssertEquals('one note', 1, Answer.Arrays['notes'].Count);
  Note := Answer.Arrays['notes'].Objects[0];
  AssertEquals('two lines', 2, Note.Arrays['lines'].Count);
  AssertEquals('the field filled in', 'skirt', Note.Arrays['lines'].Strings[1]);
  AssertNear('size', 12, Note.Floats['size'], TOLERANCE);
  AssertTrue('a line is taller than its points', Note.Floats['lineHeight'] > 12 * 25.4 / 72);
  AssertEquals('align', 'centre', Note.Strings['align']);
  AssertNear('its text from its top left', 10, Note.Arrays['box'].Floats[0], TOLERANCE);
  AssertNear('down', 20, Note.Arrays['box'].Floats[1], TOLERANCE);
  AssertEquals('a free note has no leader', 0, Note.Arrays['leaderStrokes'].Count);
  Call('editor_scene');
  AssertEquals('no file, the field as typed', '{pattern.name}', Answer.Arrays['notes'].Objects[0].Arrays['lines'].Strings[1]);
end;

procedure TTestEditorServer.TestNoteHitFirst;
var
  Note: integer;
begin
  AddSquare;
  Call('add_note', '{"text": "Over the line", "x": 40, "y": -1}');
  Note := Answer.Integers['id'];
  Call('editor_objects_at', '{"x": 42, "y": 0, "pointRadius": 2, "edgeRadius": 2}');
  AssertEquals('the note first', Note, Answer.Arrays['objects'].Integers[0]);
  AssertTrue('then the edge under it', Answer.Arrays['objects'].Count > 1);
end;

procedure TTestEditorServer.TestTextTool;
var
  Note: integer;
begin
  AddSquare;
  Call('editor_tool_snap', '{"tool": "text", "x": 100.5, "y": 0.5, "radius": 2}');
  AssertTrue('hung from the point', Pos('B', Answer.Strings['description']) > 0);
  Call('editor_tool_click', '{"tool": "text", "x": 100.5, "y": 0.5, "radius": 2}');
  AssertTrue('made', Answer.Booleans['done']);
  Note := Selected;
  Call('get_object', '{"id": ' + IntToStr(Note) + '}');
  AssertEquals('a note', 'note', Answer.Strings['type']);
  AssertEquals('saying Text', 'Text', Answer.Strings['text']);
  Call('editor_changes');
  AssertEquals('its step', 'Add note', Answer.Strings['undo']);
end;

procedure TTestEditorServer.TestCalloutTool;
var
  Note: TJSONObject;
begin
  AddSquare;
  Call('editor_tool_click', '{"tool": "callout", "x": 300, "y": 300, "radius": 2}');
  AssertFalse('nothing to point at', Answer.Booleans['started']);
  AssertTrue('says so', Answer.Strings['message'] <> '');
  Call('editor_tool_click', '{"tool": "callout", "x": 100.5, "y": 0.5, "radius": 2}');
  AssertTrue('the tip on B', Answer.Booleans['started']);
  Call('editor_tool_snap', '{"tool": "callout", "x": 150, "y": -40, "radius": 2, "start": {"x": 100.5, "y": 0.5, ' +
    '"radius": 2}}');
  AssertTrue('asks where the text goes', Pos('text goes', Answer.Strings['description']) > 0);
  Call('editor_tool_click', '{"tool": "callout", "x": 150, "y": -40, "radius": 2, "start": {"x": 100.5, "y": 0.5, ' +
    '"radius": 2}}');
  AssertTrue('made', Answer.Booleans['done']);
  Call('editor_changes');
  AssertEquals('its step', 'Add callout', Answer.Strings['undo']);
  Call('editor_scene');
  Note := Answer.Arrays['notes'].Objects[0];
  AssertEquals('an arrow', 'arrow', Note.Strings['leader']);
  AssertTrue('its leader drawn', Note.Arrays['leaderStrokes'].Count >= 4);
  AssertNear('pointing at B', 100, Note.Arrays['anchorAt'].Floats[0], TOLERANCE);
  AssertNear('its text where clicked', 150, Note.Arrays['box'].Floats[0], 0.1);
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

procedure TTestEditorServer.TestComplete;
var
  Items: TJSONArray;
begin
  Call('add_variable', '{"name": "width", "formula": "100"}');
  Call('editor_complete', '{"text": "wi", "caret": 2}');
  AssertEquals('from', 0, Answer.Integers['from']);
  AssertEquals('upto', 2, Answer.Integers['upto']);
  Items := Answer.Arrays['items'];
  AssertTrue('offered', Items.Count > 0);
  AssertEquals('the variable', 'width', Items.Objects[0].Strings['name']);
  Call('editor_complete', '{"text": "", "caret": 0}');
  AssertEquals('nothing unasked', 0, Answer.Arrays['items'].Count);
  Call('editor_complete', '{"text": "", "caret": 0, "explicit": true}');
  AssertTrue('everything when asked', Answer.Arrays['items'].Count > 0);
end;

procedure TTestEditorServer.TestCompleteCountsCharacters;
begin
  Call('add_variable', '{"name": "width", "formula": "100"}');
  Call('editor_complete', '{"text": "2×wi", "caret": 4}');
  AssertEquals('from, after the ×', 2, Answer.Integers['from']);
  AssertEquals('upto', 4, Answer.Integers['upto']);
  AssertEquals('the variable', 'width', Answer.Arrays['items'].Objects[0].Strings['name']);
end;

procedure TTestEditorServer.TestCompleteForObject;
var
  Items: TJSONArray;
  Index: integer;
begin
  AddSquare;
  Call('editor_complete', '{"name": "A", "text": "A", "caret": 1}');
  Items := Answer.Arrays['items'];
  for Index := 0 to Items.Count - 1 do
    AssertFalse('a formula cannot read its own object', Items.Objects[Index].Strings['name'] = 'A');
  Call('editor_complete', '{"name": "Nothing", "text": "A", "caret": 1}');
  AssertEquals('unknown target', RPC_REFUSED, ErrorCode);
  Call('editor_complete', '{"text": "A", "caret": 1.5}');
  AssertEquals('caret a whole number', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestEditorServer.TestListObjects;
var
  Rows: TJSONArray;
begin
  AddSquare;
  Call('editor_list_objects');
  Rows := Answer.Arrays['rows'];
  AssertEquals('every object', 9, Rows.Count);
  AssertEquals('first', 'A', Rows.Objects[0].Strings['name']);
  AssertEquals('state', 'valid', Rows.Objects[0].Strings['state']);
  AssertTrue('operation', Rows.Objects[0].Strings['operation'] <> '');
  Call('editor_list_objects', '{"filter": "points"}');
  AssertEquals('points', 4, Answer.Arrays['rows'].Count);
  Call('editor_list_objects', '{"filter": "pieces", "search": "fla"}');
  AssertEquals('found by name', 1, Answer.Arrays['rows'].Count);
  Call('editor_list_objects', '{"filter": "curves"}');
  AssertEquals('unknown filter', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestEditorServer.TestListVariables;
var
  Rows: TJSONArray;
begin
  Call('add_variable', '{"name": "ease", "formula": "5 * 2", "description": "Some ease"}');
  Call('add_variable', '{"name": "width", "formula": "100"}');
  Call('editor_list_variables', '{"search": "some"}');
  Rows := Answer.Arrays['rows'];
  AssertEquals('found by description', 1, Rows.Count);
  AssertEquals('name', 'ease', Rows.Objects[0].Strings['name']);
  AssertEquals('formula', '5 * 2', Rows.Objects[0].Strings['formula']);
  AssertTrue('value', Pos('10', Rows.Objects[0].Strings['value']) > 0);
end;

procedure TTestEditorServer.TestListMeasurements;
var
  Path: string;
  Rows: TJSONArray;
begin
  Path := ConcatPaths([ExtractFileDir(ExpandFileName(ParamStr(0))), 'patterns', 'skirt-pieces.sloper']);
  Call('open', '{"path": "' + StringToJSONString(Path) + '"}');
  Answer;
  Call('editor_list_measurements', '{"search": "waist"}');
  Rows := Answer.Arrays['rows'];
  AssertTrue('found', Rows.Count > 0);
  AssertTrue('by key or description', Pos('waist', LowerCase(Rows.Objects[0].Strings['key'] + Rows.Objects[0].Strings['description'])) > 0);
  AssertFalse('in the file', Rows.Objects[0].Booleans['missing']);
  AssertTrue('with its value', Rows.Objects[0].Strings['value'] <> '');
end;

procedure TTestEditorServer.TestSuggest;
var
  Items: TJSONArray;
  Index: integer;
  Found: boolean;
begin
  Call('add_variable', '{"name": "width", "formula": "100"}');
  AddSquare;
  Call('editor_suggest', '{"name": "B", "field": "x", "value": 100.3}');
  AssertEquals('kind', 'length', Answer.Strings['kind']);
  AssertTrue('tolerance', Answer.Strings['tolerance'] <> '');
  Items := Answer.Arrays['items'];
  Found := False;
  for Index := 0 to Items.Count - 1 do
    if Items.Objects[Index].Strings['text'] = '#width' then
    begin
      Found := True;
      AssertNear('value', 100, Items.Objects[Index].Floats['value'], TOLERANCE);
      AssertNear('delta', -0.3, Items.Objects[Index].Floats['delta'], TOLERANCE);
    end;
  AssertTrue('the variable is suggested', Found);
  AssertFalse('nearest', Answer.Nulls['nearest']);
end;

procedure TTestEditorServer.TestSuggestRefused;
begin
  AddSquare;
  Call('editor_suggest', '{"name": "B", "field": "colour"}');
  AssertEquals('no such field', RPC_REFUSED, ErrorCode);
  Call('editor_suggest', '{"name": "B"}');
  AssertEquals('no field', RPC_INVALID_PARAMS, ErrorCode);
end;

procedure TTestEditorServer.TestTables;
var
  Tools, Commands, Shortcuts: TJSONArray;
  Index: integer;
  Found: boolean;
begin
  Call('editor_tables');
  Tools := Answer.Arrays['tools'];
  AssertEquals('every tool', 12, Tools.Count);
  AssertEquals('first', 'select', Tools.Objects[0].Strings['name']);
  AssertEquals('point tool', 'point', Tools.Objects[2].Strings['name']);
  AssertEquals('its caption', 'Point', Tools.Objects[2].Strings['caption']);
  AssertTrue('its hint', Tools.Objects[2].Strings['hint'] <> '');
  AssertEquals('its icon', 'point', Tools.Objects[2].Strings['icon']);
  AssertTrue('its keys', Tools.Objects[2].Strings['keys'] <> '');
  Commands := Answer.Arrays['commands'];
  AssertTrue('commands', Commands.Count > 0);
  AssertTrue('a command has a place', Commands.Objects[0].Strings['place'] <> '');
  Shortcuts := Answer.Arrays['shortcuts'];
  Found := False;
  for Index := 0 to Shortcuts.Count - 1 do
    if Shortcuts.Objects[Index].Strings['command'] = 'undo' then
    begin
      Found := True;
      AssertEquals('undo is a command', 'command', Shortcuts.Objects[Index].Strings['kind']);
      AssertEquals('in the edit group', 'edit', Shortcuts.Objects[Index].Strings['group']);
      AssertEquals('its keys', 'Mod+Z', Shortcuts.Objects[Index].Strings['keys']);
    end;
  AssertTrue('undo listed', Found);
  AssertEquals('roles', 'outline', Answer.Arrays['roles'].Objects[1].Strings['name']);
  AssertEquals('outline in ink', '', Answer.Arrays['roles'].Objects[1].Strings['color']);
  AssertEquals('solid', 0, Answer.Arrays['roles'].Objects[1].Arrays['dashes'].Count);
  AssertEquals('stitch', 'stitch', Answer.Arrays['roles'].Objects[3].Strings['name']);
  AssertEquals('dashed', '[1, 1]', Answer.Arrays['roles'].Objects[3].Arrays['dashes'].AsJSON);
end;

// The changes editor_changes names, joined by spaces
function ChangeNames(Answer: TJSONObject): string;
var
  Index: integer;
begin
  Result := '';
  for Index := 0 to Answer.Arrays['changes'].Count - 1 do
    Result := Trim(Result + ' ' + Answer.Arrays['changes'].Strings[Index]);
end;

procedure TTestEditorServer.TestChanges;
begin
  Call('editor_changes');
  AssertEquals('nothing yet', '', ChangeNames(Answer));
  AssertFalse('nothing to undo', Answer.Booleans['canUndo']);
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('editor_changes');
  AssertEquals('an edit', 'pattern history file', ChangeNames(Answer));
  AssertTrue('can undo', Answer.Booleans['canUndo']);
  AssertTrue('its name', Answer.Strings['undo'] <> '');
  AssertFalse('nothing to redo', Answer.Booleans['canRedo']);
  AssertTrue('modified', Answer.Booleans['modified']);
  Call('editor_changes');
  AssertEquals('told once', '', ChangeNames(Answer));
  Call('editor_scene');
  Call('editor_snap', '{"x": 1, "y": 1, "radius": 2}');
  Call('editor_changes');
  AssertEquals('reading changes nothing', '', ChangeNames(Answer));
  Call('add_point', '{"type": "freePoint", "name": "B", "x": 10, "y": 0}');
  Call('add_point', '{"type": "freePoint", "name": "C", "x": 20, "y": 0}');
  Call('editor_changes');
  AssertEquals('gathered', 'pattern history', ChangeNames(Answer));
end;

procedure TTestEditorServer.TestChangesAfterUndo;
begin
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('editor_changes');
  Call('undo');
  Call('editor_changes');
  AssertTrue('new objects', Pos('objectsReplaced', ChangeNames(Answer)) > 0);
  AssertTrue('history', Pos('history', ChangeNames(Answer)) > 0);
  AssertTrue('can redo', Answer.Booleans['canRedo']);
  AssertFalse('not modified', Answer.Booleans['modified']);
end;

procedure TTestEditorServer.TestChangesOnOpen;
var
  Generation: integer;
begin
  Call('editor_changes');
  Generation := Answer.Integers['generation'];
  Call('add_point', '{"type": "freePoint", "name": "A", "x": 0, "y": 0}');
  Call('save', '{"text": true}');
  Call('open', '{"text": "' + StringToJSONString(Answer.Strings['text']) + '"}');
  Call('editor_changes');
  AssertEquals('another pattern', Generation + 1, Answer.Integers['generation']);
  AssertEquals('everything', 'pattern objectsReplaced measurements history file', ChangeNames(Answer));
  AssertFalse('no history', Answer.Booleans['canUndo']);
end;

procedure TTestEditorServer.TestDragPoint;
begin
  AddSquare;
  Call('editor_changes');
  Call('editor_drag_begin', '{"name": "C"}');
  AssertNear('starts where it is', 100, Answer.Floats['x'], TOLERANCE);
  Call('editor_drag_to', '{"x": 120, "y": 110}');
  AssertTrue('moved', Answer.Booleans['moved']);
  AssertNear('there', 120, Answer.Floats['x'], TOLERANCE);
  Call('editor_drag_to', '{"x": 130, "y": 140}');
  Call('editor_changes');
  AssertEquals('worked out while dragging', 'pattern', ChangeNames(Answer));
  Call('editor_scene');
  AssertNear('the scene follows', 140, Answer.Arrays['points'].Objects[2].Floats['y'], TOLERANCE);
  Call('editor_drag_end');
  AssertTrue('changed', Answer.Booleans['changed']);
  Call('editor_changes');
  AssertEquals('one step', 'Move point', Answer.Strings['undo']);
  Call('undo');
  Call('get_object', '{"name": "C"}');
  AssertNear('undone at once', 100, Answer.Floats['x'], TOLERANCE);
  Call('editor_changes');
  AssertTrue('the piece next', Answer.Strings['undo'] <> 'Move point');
end;

procedure TTestEditorServer.TestDragCancel;
begin
  AddSquare;
  Call('editor_drag_begin', '{"name": "C"}');
  Call('editor_drag_to', '{"x": 150, "y": 150}');
  Call('editor_drag_cancel');
  AssertFalse('nothing', Answer.Booleans['changed']);
  Call('get_object', '{"name": "C"}');
  AssertNear('back', 100, Answer.Floats['x'], TOLERANCE);
  Call('editor_drag_begin', '{"name": "C"}');
  Call('editor_drag_end');
  AssertFalse('ended where it began', Answer.Booleans['changed']);
end;

procedure TTestEditorServer.TestDragOneField;
begin
  AddSquare;
  Call('editor_drag_begin', '{"name": "C", "field": "x"}');
  Call('editor_drag_to', '{"x": 130, "y": 160}');
  AssertNear('across', 130, Answer.Floats['x'], TOLERANCE);
  AssertNear('not down', 100, Answer.Floats['y'], TOLERANCE);
  Call('editor_drag_end');
  Call('editor_drag_begin', '{"name": "C", "field": "colour"}');
  AssertEquals('no such field', RPC_REFUSED, ErrorCode);
end;

procedure TTestEditorServer.TestDragNote;
begin
  Call('add_note', '{"text": "Cut 2", "x": 10, "y": 20}');
  Answer;
  Call('editor_drag_begin', '{"name": "' + Answer.Strings['name'] + '"}');
  AssertNear('top left', 10, Answer.Floats['x'], TOLERANCE);
  Call('editor_drag_to', '{"x": 40, "y": 50}');
  AssertNear('moved', 40, Answer.Floats['x'], TOLERANCE);
  Call('editor_drag_end');
  Call('editor_changes');
  AssertEquals('its step', 'Move note', Answer.Strings['undo']);
end;

procedure TTestEditorServer.TestDragBlocksChanges;
begin
  AddSquare;
  Call('editor_drag_begin', '{"name": "C"}');
  Call('add_point', '{"type": "freePoint", "name": "E", "x": 5, "y": 5}');
  AssertEquals('an API change', RPC_REFUSED, ErrorCode);
  Call('editor_tool_click', '{"tool": "point", "x": 300, "y": 300, "radius": 2}');
  AssertEquals('an editor change', RPC_REFUSED, ErrorCode);
  Call('undo');
  AssertEquals('undo', RPC_REFUSED, ErrorCode);
  Call('editor_drag_begin', '{"name": "B"}');
  AssertEquals('a second drag', RPC_REFUSED, ErrorCode);
  Call('editor_scene');
  Answer;
  Call('editor_drag_end');
  Call('add_point', '{"type": "freePoint", "name": "E", "x": 5, "y": 5}');
  Answer;
end;

procedure TTestEditorServer.TestDragRefusals;
begin
  AddSquare;
  Call('editor_drag_to', '{"x": 1, "y": 1}');
  AssertEquals('no drag', RPC_REFUSED, ErrorCode);
  Call('editor_drag_end');
  AssertEquals('none to end', RPC_REFUSED, ErrorCode);
  Call('editor_drag_begin', '{"name": "Flap"}');
  AssertEquals('a piece', RPC_REFUSED, ErrorCode);
  Call('set_locked', '{"name": "C", "locked": true}');
  Call('editor_drag_begin', '{"name": "C"}');
  AssertEquals('locked', RPC_REFUSED, ErrorCode);
  // No change was left open
  Call('add_point', '{"type": "freePoint", "name": "E", "x": 5, "y": 5}');
  Answer;
end;

procedure TTestEditorServer.TestHandles;
var
  Handles: TJSONArray;
  Curve: integer;
begin
  AddSquare;
  Call('add_edge', '{"type": "curve", "name": "Arch", "start": "A", "end": "B", "angle1": 270, "length1": 30, ' +
    '"angle2": 270, "length2": 30}');
  Curve := IdOf('Arch');
  Call('editor_handles', '{"selection": ["A"]}');
  AssertEquals('no curve selected', 0, Answer.Arrays['handles'].Count);
  Call('editor_handles', '{"selection": ["Arch"]}');
  Handles := Answer.Arrays['handles'];
  AssertEquals('two', 2, Handles.Count);
  AssertEquals('its curve', Curve, Handles.Objects[0].Integers['edge']);
  AssertEquals('named by its length', 'length1', Handles.Objects[0].Strings['field']);
  AssertNear('starts at the curve''s start', 0, Handles.Objects[0].Floats['anchorY'], TOLERANCE);
  AssertNear('ends below it', 30, Handles.Objects[0].Floats['y'], TOLERANCE);
  AssertTrue('draggable', Handles.Objects[0].Booleans['draggable']);
  Call('editor_objects_at', '{"x": 100, "y": 29, "pointRadius": 2, "edgeRadius": 2, "selection": ["Arch"]}');
  AssertEquals('the second handle', 'length2', Answer.Objects['handle'].Strings['field']);
  Call('editor_objects_at', '{"x": 100, "y": 29, "pointRadius": 2, "edgeRadius": 2, "selection": []}');
  AssertTrue('not while unselected', Answer.Nulls['handle']);
  Call('editor_objects_at', '{"x": 100, "y": 29, "pointRadius": 2, "edgeRadius": 2}');
  AssertNull('only asked with a selection', Answer.Find('handle'));
end;

procedure TTestEditorServer.TestDragHandle;
begin
  AddSquare;
  Call('add_edge', '{"type": "curve", "name": "Arch", "start": "A", "end": "B", "angle1": 270, "length1": 30, ' +
    '"angle2": 270, "length2": 30}');
  Call('editor_drag_begin', '{"name": "Arch", "handle": "length1"}');
  AssertNear('starts at the handle', 30, Answer.Floats['y'], TOLERANCE);
  Call('editor_drag_to', '{"x": 40, "y": 0}');
  AssertTrue('moved', Answer.Booleans['moved']);
  AssertNear('across', 40, Answer.Floats['x'], TOLERANCE);
  AssertNear('level', 0, Answer.Floats['y'], TOLERANCE);
  Call('editor_drag_end');
  Call('get_object', '{"name": "Arch"}');
  AssertEquals('angle', '0', Answer.Objects['formulas'].Strings['angle1']);
  AssertEquals('length', '40', Answer.Objects['formulas'].Strings['length1']);
  Call('editor_changes');
  AssertEquals('its step', 'Move curve handle', Answer.Strings['undo']);
  Call('editor_drag_begin', '{"name": "Arch", "handle": "angle1"}');
  AssertEquals('not a handle', RPC_REFUSED, ErrorCode);
  Call('editor_drag_begin', '{"name": "Line_A_B", "handle": "length1"}');
  AssertEquals('a line has none', RPC_REFUSED, ErrorCode);
end;

procedure TTestEditorServer.TestHandleFormulaRefused;
begin
  AddSquare;
  Call('add_edge', '{"type": "curve", "name": "Arch", "start": "A", "end": "B", "angle1": 270, "length1": "15 * 2", ' +
    '"angle2": 270, "length2": 30}');
  Call('editor_handles', '{"selection": ["Arch"]}');
  AssertFalse('set by a formula', Answer.Arrays['handles'].Objects[0].Booleans['draggable']);
  AssertTrue('the other is not', Answer.Arrays['handles'].Objects[1].Booleans['draggable']);
  Call('editor_drag_begin', '{"name": "Arch", "handle": "length1"}');
  AssertEquals('refused', RPC_REFUSED, ErrorCode);
  Call('add_point', '{"type": "freePoint", "name": "E", "x": 5, "y": 5}');
  Answer;
end;

function TTestEditorServer.AddCallout: integer;
begin
  Call('editor_tool_click', '{"tool": "callout", "x": 100, "y": 0, "radius": 2}');
  Call('editor_tool_click', '{"tool": "callout", "x": 150, "y": -40, "radius": 2, "start": {"x": 100, "y": 0, ' +
    '"radius": 2}}');
  Result := Answer.Arrays['select'].Integers[0];
end;

procedure TTestEditorServer.TestDragCalloutTip;
var
  Callout: integer;
  Note: TJSONObject;
begin
  AddSquare;
  Callout := AddCallout;
  Call('editor_objects_at', '{"x": 100.5, "y": 0.5, "pointRadius": 2, "edgeRadius": 2, "selection": [' +
    IntToStr(Callout) + ']}');
  AssertEquals('its tip', Callout, Answer.Integers['tip']);
  Call('editor_objects_at', '{"x": 100.5, "y": 0.5, "pointRadius": 2, "edgeRadius": 2, "selection": []}');
  AssertTrue('not while unselected', Answer.Nulls['tip']);
  Call('editor_changes');
  Call('editor_drag_begin', '{"id": ' + IntToStr(Callout) + ', "tip": true}');
  AssertNear('starts at B', 100, Answer.Floats['x'], TOLERANCE);
  Call('editor_drag_to', '{"x": 0.5, "y": 0.5, "radius": 2}');
  AssertEquals('snaps to A', 'point', Answer.Strings['kind']);
  AssertNear('there', 0, Answer.Floats['x'], TOLERANCE);
  AssertTrue('says what it points at', Pos('A', Answer.Strings['message']) > 0);
  AssertTrue('its leader to draw', Answer.Arrays['leaderStrokes'].Count >= 4);
  Call('editor_changes');
  AssertEquals('nothing changed yet', '', ChangeNames(Answer));
  Call('editor_drag_end');
  AssertTrue('changed', Answer.Booleans['changed']);
  Call('editor_changes');
  AssertEquals('its step', 'Move callout tip', Answer.Strings['undo']);
  Call('editor_scene');
  Note := Answer.Arrays['notes'].Objects[0];
  AssertNear('pointing at A', 0, Note.Arrays['anchorAt'].Floats[0], TOLERANCE);
  AssertNear('its text stays', 150, Note.Arrays['box'].Floats[0], 0.1);
  Call('editor_drag_begin', '{"id": ' + IntToStr(Callout) + ', "tip": true}');
  Call('editor_drag_to', '{"x": 100.5, "y": 99.5, "radius": 2}');
  Call('editor_drag_cancel');
  AssertFalse('cancelled', Answer.Booleans['changed']);
  Call('editor_drag_begin', '{"id": ' + IntToStr(Callout) + ', "tip": true}');
  Call('editor_drag_end');
  AssertFalse('never moved', Answer.Booleans['changed']);
end;

procedure TTestEditorServer.TestCalloutTipRefusals;
var
  Callout: integer;
begin
  AddSquare;
  Callout := AddCallout;
  Call('editor_drag_begin', '{"id": ' + IntToStr(Callout) + ', "tip": true}');
  Call('editor_drag_to', '{"x": 300, "y": 300, "radius": 2}');
  AssertEquals('free', 'free', Answer.Strings['kind']);
  Call('editor_drag_end');
  AssertEquals('a tip on nothing', RPC_REFUSED, ErrorCode);
  // The drop left no change open
  Call('add_point', '{"type": "freePoint", "name": "E", "x": 5, "y": 5}');
  Answer;
  Call('editor_drag_begin', '{"name": "A", "tip": true}');
  AssertEquals('a point has no tip', RPC_REFUSED, ErrorCode);
  Call('set_locked', '{"id": ' + IntToStr(Callout) + ', "locked": true}');
  Call('editor_drag_begin', '{"id": ' + IntToStr(Callout) + ', "tip": true}');
  AssertEquals('locked', RPC_REFUSED, ErrorCode);
end;

procedure TTestEditorServer.TestBounds;
var
  Bounds: TJSONArray;
begin
  AddSquare;
  Call('editor_bounds', '{"ids": ["A", "C"]}');
  Bounds := Answer.Arrays['bounds'];
  AssertNear('left', 0, Bounds.Floats[0], TOLERANCE);
  AssertNear('bottom', 100, Bounds.Floats[3], TOLERANCE);
  Call('editor_bounds', '{"ids": []}');
  AssertTrue('nothing', Answer.Nulls['bounds']);
end;

procedure TTestEditorServer.TestListClick;
const
  Visible = '"visible": ["1", "2", "3", "chest"]';
begin
  Call('editor_list_click', '{' + Visible + ', "selected": ["1"], "anchor": "1", "clicked": "3"}');
  AssertEquals('a click', '[3]', Answer.Arrays['selection'].AsJSON);
  Call('editor_list_click', '{' + Visible + ', "selected": ["1"], "anchor": "1", "clicked": "3", "toggle": true}');
  AssertEquals('added', '[1, 3]', Answer.Arrays['selection'].AsJSON);
  Call('editor_list_click', '{' + Visible + ', "selected": ["2"], "anchor": "2", "clicked": "chest", "extend": true}');
  AssertEquals('a range, keys as text', '[2, 3, "chest"]', Answer.Arrays['selection'].AsJSON);
  Call('editor_list_click', '{' + Visible + ', "selected": []}');
  AssertEquals('no row', RPC_INVALID_PARAMS, ErrorCode);
end;

initialization
  RegisterTest(TTestEditorServer);

end.
