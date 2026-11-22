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

// The methods a canvas editor needs besides the Automation API: what to draw,
// what lies under the cursor, and what a click would snap to. They are named
// editor_ and served with the API by the web engine and opensloper-cli serve,
// but are not offered to Claude as tools, for whom a mouse position means
// nothing. Positions are in mm, as the API's. No LCL dependency.
unit Sloper.API.EditorServer;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.API.Methods, Sloper.API.Server, Sloper.Editor.Snap;

type
  TEditorApiServer = class(TApiServer)
  private
    // The snap for the call's place, radius and anchor
    function CallSnap(Params: TJSONObject): TSnap;
    function DoScene(Params: TJSONObject): TJSONData;
    function DoSnap(Params: TJSONObject): TJSONData;
    function DoObjectsAt(Params: TJSONObject): TJSONData;
    function DoObjectsInBox(Params: TJSONObject): TJSONData;
    function DoAddPoint(Params: TJSONObject): TJSONData;
    function DoComplete(Params: TJSONObject): TJSONData;
    function DoListObjects(Params: TJSONObject): TJSONData;
    function DoListVariables(Params: TJSONObject): TJSONData;
    function DoListMeasurements(Params: TJSONObject): TJSONData;
    function DoSuggest(Params: TJSONObject): TJSONData;
  protected
    function DispatchMethod(const Method: string; Params: TJSONObject): TJSONData; override;
  end;

// The editor's methods, documented as the API's are
function EditorMethods: TApiMethodArray;

resourcestring
  rsEditorScene = 'What the canvas shows, in drawing order: pieces, then edges, then points. Hidden objects and ' +
    'objects never computed are left out; failing ones are at their last good result.';
  rsEditorTolerance = 'How far a curve''s polyline may stray from it, in mm; default 0.1';
  rsEditorSceneReturns = '`isolated`, the piece shown alone or null; `pieces`, each with `id`, `name`, `state`, ' +
    '`locked`, `dimmed`, `fillColor`, `fillStyle` and its `cutLine`; `edges`, each with `id`, `name`, `role`, ' +
    '`state`, `locked`, `dimmed`, `copyOf`, its `line`, and `slot` and `normal` when it lies on another edge; `points`, ' +
    'each with `id`, `name`, `state`, `locked`, `dimmed`, `copyOf`, `x` and `y`. Lines are flat lists x, y, x, y, in ' +
    'mm; `copyOf` is the transform an object is a copy from, or null.';
  rsEditorSnap = 'What a click at a place would make or pick: an existing point, a crossing of two edges, a place on ' +
    'an edge, a spot level with or square to a point, or a free point.';
  rsEditorX = 'Across, in mm';
  rsEditorY = 'Down, in mm';
  rsEditorRadius = 'How far round the place to look, in mm: a few pixels at the zoom shown';
  rsEditorAnchor = 'The point a line being drawn starts from, by ID or name: lining up with it comes first';
  rsEditorSnapReturns = '`kind` (free, point, crossing, edge, horizontal or vertical), where the point goes (`x`, `y`), ' +
    '`description` in words, and `objects`, the IDs of what it works from';
  rsEditorObjectsAt = 'Everything under a place, in the order a click picks it: points nearest first, then edges ' +
    'nearest first, then pieces smallest first.';
  rsEditorPointRadius = 'How near a point must be, in mm';
  rsEditorEdgeRadius = 'How near an edge must be, in mm';
  rsEditorObjectsReturns = '`objects`, their IDs';
  rsEditorObjectsInBox = 'The points, edges and pieces lying wholly inside a box, in pattern order; a repeat counts as ' +
    'its points.';
  rsEditorMinX = 'The box''s left, in mm';
  rsEditorMinY = 'Its top, in mm';
  rsEditorMaxX = 'Its right, in mm';
  rsEditorMaxY = 'Its bottom, in mm';
  rsEditorAddPoint = 'Adds the point a click at a place would make, as editor_snap describes it, with an automatic ' +
    'name, as one undo step. A click on an existing point makes nothing and gives that point.';
  rsEditorAddPointReturns = 'The point, as `get_object` gives it, and `existing`, true when it was there already';
  rsEditorComplete = 'What to offer while a formula is typed: objects, variables, measurements and functions matching ' +
    'the word at the caret; @, # and a dot after an object narrow the list.';
  rsEditorCompleteTarget = 'The object or variable whose formula it is, by ID or name; left out for a new one';
  rsEditorCompleteText = 'The formula as typed, with names';
  rsEditorCaret = 'Where the caret is, in characters from 0';
  rsEditorExplicit = 'The user asked for the list, so an empty word offers everything';
  rsEditorCompleteReturns = '`from` and `upto`, the characters of the word an item replaces, and `items`, each with ' +
    '`name`, `insert` (the text that replaces the word) and `detail`';
  rsEditorListObjects = 'The rows of the Objects tab: the objects passing the filter whose name, operation or formulas ' +
    'contain the search, in pattern order.';
  rsEditorFilter = 'Which objects; all by default';
  rsEditorSearch = 'Text to look for, ignoring case; empty for all';
  rsEditorListObjectsReturns = '`rows`, each with `id`, `name`, `operation`, `value`, `formulas`, `state` and ' +
    '`stateText`';
  rsEditorListVariables = 'The rows of the Variables tab: the variables whose name, formula or description contain the ' +
    'search.';
  rsEditorListVariablesReturns = '`rows`, each with `id`, `name`, `formula`, `value`, `description`, `state` and ' +
    '`stateText`';
  rsEditorListMeasurements = 'The rows of the Measurements tab: the measurement file''s measurements whose key or ' +
    'description contain the search, then those the pattern uses that the file lacks.';
  rsEditorListMeasurementsReturns = '`rows`, each with `key`, `value`, `description` and `missing`';
  rsEditorSuggest = 'Formulas that give about the value of an object''s field, from its measurements, variables and ' +
    'the objects it may read, best first.';
  rsEditorSuggestTarget = 'The object, by ID or name';
  rsEditorField = 'The field, such as length or angle';
  rsEditorSuggestValue = 'The value to match, in mm, degrees or a ratio, as while dragging; the field''s own value ' +
    'when left out';
  rsEditorSuggestReturns = '`kind` (length, angle or ratio), `tolerance` in words, `items` within it, each with ' +
    '`text`, `value`, `valueText`, `delta` and `deltaText`, and `nearest`, the closest of all, or null';
  rsEditorCannotSuggest = 'No formula can be suggested for the %s of %s';
  rsEditorTables = 'The design app''s tables the editor reads instead of copying: its canvas tools, its commands with ' +
    'their icons and menus, and its keys and mouse actions.';
  rsEditorTablesReturns = '`tools`, each with `name`, `caption`, `hint`, `icon` and `keys`; `commands`, each with ' +
    '`name`, `icon`, `place`, `menu`, `keys` and `description`; `shortcuts`, each with `command`, `keys`, `kind`, ' +
    '`group` and `description`. Keys are written as Mod+Shift+S, Mod being Ctrl, or Cmd on macOS.';

implementation

uses
  TypInfo, Sloper.API.Rpc, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Transform, Sloper.Core.PatternCheck, Sloper.Core.Materials,
  Sloper.Core.Shortcuts, Sloper.Core.IconSet, Sloper.Editor.Scene, Sloper.Editor.Completion, Sloper.Editor.ObjectList,
  Sloper.Editor.Suggestion, Sloper.Editor.Tools;

const
  // How finely curves are flattened when the call does not say, in mm
  DEFAULT_TOLERANCE = 0.1;
  // The finest flattening asked for, in mm, so a curve cannot become millions of points
  MIN_TOLERANCE = 0.001;
  SNAP_KIND_NAMES: array[TSnapKind] of string = ('free', 'point', 'crossing', 'edge', 'horizontal', 'vertical');
  OBJECT_FILTER_NAMES: array[TObjectFilter] of string = ('all', 'points', 'edges', 'pieces', 'notes', 'problems');
  SUGGESTION_KIND_NAMES: array[TSuggestionKind] of string = ('none', 'length', 'angle', 'ratio');
  ICON_PLACE_NAMES: array[TIconPlace] of string = ('toolbar', 'tools', 'sideTabs', 'menu', 'properties');
  SHORTCUT_KIND_NAMES: array[TShortcutKind] of string = ('command', 'fixed', 'mouse');

var
  Built: TApiMethodArray = nil;

function EditorMethods: TApiMethodArray;
begin
  if Length(Built) = 0 then
  begin
    AddApiMethod(Built, 'editor_scene', rsEditorScene, rsEditorSceneReturns, True);
    AddApiParam(Built, 'tolerance', apNumber, False, rsEditorTolerance);
    AddApiMethod(Built, 'editor_snap', rsEditorSnap, rsEditorSnapReturns, True);
    AddApiParam(Built, 'x', apNumber, True, rsEditorX);
    AddApiParam(Built, 'y', apNumber, True, rsEditorY);
    AddApiParam(Built, 'radius', apNumber, True, rsEditorRadius);
    AddApiParam(Built, 'anchor', apReference, False, rsEditorAnchor);
    AddApiMethod(Built, 'editor_objects_at', rsEditorObjectsAt, rsEditorObjectsReturns, True);
    AddApiParam(Built, 'x', apNumber, True, rsEditorX);
    AddApiParam(Built, 'y', apNumber, True, rsEditorY);
    AddApiParam(Built, 'pointRadius', apNumber, True, rsEditorPointRadius);
    AddApiParam(Built, 'edgeRadius', apNumber, True, rsEditorEdgeRadius);
    AddApiMethod(Built, 'editor_objects_in_box', rsEditorObjectsInBox, rsEditorObjectsReturns, True);
    AddApiParam(Built, 'minX', apNumber, True, rsEditorMinX);
    AddApiParam(Built, 'minY', apNumber, True, rsEditorMinY);
    AddApiParam(Built, 'maxX', apNumber, True, rsEditorMaxX);
    AddApiParam(Built, 'maxY', apNumber, True, rsEditorMaxY);
    AddApiMethod(Built, 'editor_add_point', rsEditorAddPoint, rsEditorAddPointReturns);
    AddApiParam(Built, 'x', apNumber, True, rsEditorX);
    AddApiParam(Built, 'y', apNumber, True, rsEditorY);
    AddApiParam(Built, 'radius', apNumber, True, rsEditorRadius);
    AddApiParam(Built, 'anchor', apReference, False, rsEditorAnchor);
    AddApiMethod(Built, 'editor_complete', rsEditorComplete, rsEditorCompleteReturns, True);
    AddApiParam(Built, 'id', apTarget, False, rsEditorCompleteTarget);
    AddApiParam(Built, 'text', apText, True, rsEditorCompleteText);
    AddApiParam(Built, 'caret', apWhole, True, rsEditorCaret);
    AddApiParam(Built, 'explicit', apFlag, False, rsEditorExplicit);
    AddApiMethod(Built, 'editor_list_objects', rsEditorListObjects, rsEditorListObjectsReturns, True);
    AddApiParam(Built, 'filter', apChoice, False, rsEditorFilter, string.Join(', ', OBJECT_FILTER_NAMES));
    AddApiParam(Built, 'search', apText, False, rsEditorSearch);
    AddApiMethod(Built, 'editor_list_variables', rsEditorListVariables, rsEditorListVariablesReturns, True);
    AddApiParam(Built, 'search', apText, False, rsEditorSearch);
    AddApiMethod(Built, 'editor_list_measurements', rsEditorListMeasurements, rsEditorListMeasurementsReturns, True);
    AddApiParam(Built, 'search', apText, False, rsEditorSearch);
    AddApiMethod(Built, 'editor_suggest', rsEditorSuggest, rsEditorSuggestReturns, True);
    AddApiParam(Built, 'id', apTarget, True, rsEditorSuggestTarget);
    AddApiParam(Built, 'field', apText, True, rsEditorField);
    AddApiParam(Built, 'value', apNumber, False, rsEditorSuggestValue);
    AddApiMethod(Built, 'editor_tables', rsEditorTables, rsEditorTablesReturns, True);
  end;
  Result := Built;
end;

function RequireNumber(Params: TJSONObject; const AName: string): double;
begin
  Result := 0;
  if not OptionalNumber(Params, AName, Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
end;

function RequireWhole(Params: TJSONObject; const AName: string): integer;
var
  Value: double;
begin
  Value := RequireNumber(Params, AName);
  if (Frac(Value) <> 0) or (Value < 0) or (Value > MaxInt) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
  Result := Trunc(Value);
end;

// An object's ID as the API gives it: a number, or the key of a repeat's point
// that has no ID yet
function KeyToJSON(const Key: string): TJSONData;
var
  Id: integer;
begin
  if TryStrToInt(Key, Id) then
    Result := TJSONIntegerNumber.Create(Id)
  else
    Result := TJSONString.Create(Key);
end;

function KeysToJSON(const Keys: array of string): TJSONArray;
var
  Key: string;
begin
  Result := TJSONArray.Create;
  for Key in Keys do
    Result.Add(KeyToJSON(Key));
end;

function LineToJSON(const Line: TVec2Array): TJSONArray;
var
  Point: TVec2;
begin
  Result := TJSONArray.Create;
  for Point in Line do
  begin
    Result.Add(ReportFloat(Point.X));
    Result.Add(ReportFloat(Point.Y));
  end;
end;

// What every object in the scene has
function SceneObject(Pattern: TPattern; DraftObject: TDraftObject): TJSONObject;
var
  CopyKey: string;
begin
  Result := TJSONObject.Create;
  Result.Add('id', KeyToJSON(DraftObject.Key));
  Result.Add('name', DraftObject.DisplayName);
  Result.Add('state', StateName(DraftObject.State));
  Result.Add('locked', Pattern.IsLocked(DraftObject));
  Result.Add('dimmed', Pattern.IsDimmed(DraftObject));
  if not (DraftObject is TPieceObject) then
  begin
    CopyKey := CopyTransformKey(DraftObject);
    if CopyKey = '' then
      Result.Add('copyOf', TJSONNull.Create)
    else
      Result.Add('copyOf', KeyToJSON(CopyKey));
  end;
end;

function TEditorApiServer.DoScene(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  Tolerance: double;
  Scene, Item: TJSONObject;
  List: TJSONArray;
  Piece: TPieceObject;
  DraftObject: TDraftObject;
  Edge: TEdgeObject;
  Point: TPointObject;
  Slots: TEdgeSlotArray;
  Slot: TEdgeSlot;
begin
  Pattern := Document.Pattern;
  Tolerance := DEFAULT_TOLERANCE;
  OptionalNumber(Params, 'tolerance', Tolerance);
  if Tolerance < MIN_TOLERANCE then
    Tolerance := MIN_TOLERANCE;
  Scene := TJSONObject.Create;
  try
    if Assigned(Pattern.IsolatedPiece) then
      Scene.Add('isolated', KeyToJSON(Pattern.IsolatedPiece.Key))
    else
      Scene.Add('isolated', TJSONNull.Create);

    List := TJSONArray.Create;
    Scene.Add('pieces', List);
    for Piece in Pattern.PiecesInDrawOrder do
      if Piece.HasResult and not Pattern.IsHidden(Piece) and (Length(Piece.CutLine) > 0) then
      begin
        Item := SceneObject(Pattern, Piece);
        Item.Add('fillColor', Piece.FillColor);
        Item.Add('fillStyle', PIECE_FILL_NAMES[Ord(Piece.FillStyle)]);
        Item.Add('cutLine', LineToJSON(Piece.CutLine));
        List.Add(Item);
      end;

    Slots := CoincidentEdges(Pattern);
    List := TJSONArray.Create;
    Scene.Add('edges', List);
    for DraftObject in EdgesInDrawOrder(ShownObjects(Pattern)) do
    begin
      if not DraftObject.HasResult then
        Continue;
      Edge := TEdgeObject(DraftObject);
      Item := SceneObject(Pattern, Edge);
      Item.Add('role', EDGE_ROLE_NAMES[Edge.Role]);
      Item.Add('line', LineToJSON(EdgePolyline(Edge, Tolerance)));
      for Slot in Slots do
        if Slot.Key = Edge.Key then
        begin
          Item.Add('slot', ReportFloat(Slot.Slot));
          Item.Add('normal', LineToJSON([Slot.Normal]));
        end;
      List.Add(Item);
    end;

    List := TJSONArray.Create;
    Scene.Add('points', List);
    for Point in ShownPoints(Pattern) do
      if Point.HasResult then
      begin
        Item := SceneObject(Pattern, Point);
        Item.Add('x', ReportFloat(Point.Position.X));
        Item.Add('y', ReportFloat(Point.Position.Y));
        List.Add(Item);
      end;
    Result := Scene;
  except
    FreeAndNil(Scene);
    raise;
  end;
end;

function TEditorApiServer.CallSnap(Params: TJSONObject): TSnap;
var
  At: TVec2;
  Radius: double;
  AnchorKey: string;
begin
  At := Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y'));
  Radius := RequireNumber(Params, 'radius');
  AnchorKey := '';
  if Assigned(Params.Find('anchor')) then
    AnchorKey := Reference(Params, 'anchor', False);
  Result := FindSnap(Document.Pattern, At, Radius, AnchorKey);
end;

function TEditorApiServer.DoSnap(Params: TJSONObject): TJSONData;
var
  Snap: TSnap;
  Answer: TJSONObject;
begin
  Snap := CallSnap(Params);
  Answer := TJSONObject.Create;
  Answer.Add('kind', SNAP_KIND_NAMES[Snap.Kind]);
  Answer.Add('x', ReportFloat(Snap.Position.X));
  Answer.Add('y', ReportFloat(Snap.Position.Y));
  Answer.Add('description', SnapDescription(Document.Pattern, Snap));
  Answer.Add('objects', KeysToJSON(SnapObjectKeys(Snap)));
  Result := Answer;
end;

function TEditorApiServer.DoObjectsAt(Params: TJSONObject): TJSONData;
var
  At: TVec2;
  PointRadius, EdgeRadius: double;
begin
  At := Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y'));
  PointRadius := RequireNumber(Params, 'pointRadius');
  EdgeRadius := RequireNumber(Params, 'edgeRadius');
  Result := TJSONObject.Create(['objects', KeysToJSON(ObjectsAt(Document.Pattern, At, PointRadius, EdgeRadius))]);
end;

function TEditorApiServer.DoObjectsInBox(Params: TJSONObject): TJSONData;
var
  Box: TRect2;
begin
  Box.MinX := RequireNumber(Params, 'minX');
  Box.MinY := RequireNumber(Params, 'minY');
  Box.MaxX := RequireNumber(Params, 'maxX');
  Box.MaxY := RequireNumber(Params, 'maxY');
  Result := TJSONObject.Create(['objects', KeysToJSON(ObjectsInBox(Document.Pattern, Box))]);
end;

function TEditorApiServer.DoAddPoint(Params: TJSONObject): TJSONData;
var
  Snap: TSnap;
  Key: string;
  Answer: TJSONObject;
  Existing: boolean;
begin
  Snap := CallSnap(Params);
  Existing := Snap.Kind = snPoint;
  if Existing then
    Answer := NodeToJSON(Document, Document.Pattern.FindNode(Snap.PointKey))
  else
  begin
    BeginChange(rsToolAddPoint);
    Key := PointFromSnap(Document.Pattern, Snap);
    if Key = '' then
      RefuseChange;
    EndChange;
    Answer := NodeToJSON(Document, Document.Pattern.FindNode(Key));
  end;
  Answer.Add('existing', Existing);
  Result := Answer;
end;

function TEditorApiServer.DoComplete(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  Text: string;
  Caret: integer;
  Completion: TCompletion;
  Item: TCompletionItem;
  Items: TJSONArray;
begin
  Node := nil;
  if Assigned(Params.Find('id')) or Assigned(Params.Find('name')) then
    Node := FindTarget(Params);
  Text := RequireString(Params, 'text');
  Caret := RequireWhole(Params, 'caret');
  Completion := FormulaCompletion(Document.Pattern, Node, Text, CaretBytes(Text, Caret), BooleanParam(Params, 'explicit'));
  Items := TJSONArray.Create;
  for Item in Completion.Items do
    Items.Add(TJSONObject.Create(['name', Item.Name, 'insert', Item.Insert, 'detail', Item.Detail]));
  Result := TJSONObject.Create(['from', CaretChars(Text, Completion.From), 'upto', CaretChars(Text, Completion.Upto),
    'items', Items]);
end;

function TEditorApiServer.DoListObjects(Params: TJSONObject): TJSONData;
var
  Filter: TObjectFilter;
  Row: TObjectRow;
  Rows: TJSONArray;
begin
  Filter := TObjectFilter(ChoiceParam(Params, 'filter', OBJECT_FILTER_NAMES));
  Rows := TJSONArray.Create;
  for Row in ObjectRows(Document.Pattern, Filter, OptionalString(Params, 'search')) do
    Rows.Add(TJSONObject.Create(['id', KeyToJSON(Row.Key), 'name', Row.Name, 'operation', Row.Operation, 'value', Row.Value,
      'formulas', Row.Formulas, 'state', StateName(Row.State), 'stateText', Row.StateText]));
  Result := TJSONObject.Create(['rows', Rows]);
end;

function TEditorApiServer.DoListVariables(Params: TJSONObject): TJSONData;
var
  Row: TVariableRow;
  Rows: TJSONArray;
begin
  Rows := TJSONArray.Create;
  for Row in VariableRows(Document.Pattern, OptionalString(Params, 'search')) do
    Rows.Add(TJSONObject.Create(['id', KeyToJSON(Row.Key), 'name', Row.Name, 'formula', Row.Formula, 'value', Row.Value,
      'description', Row.Description, 'state', StateName(Row.State), 'stateText', Row.StateText]));
  Result := TJSONObject.Create(['rows', Rows]);
end;

function TEditorApiServer.DoListMeasurements(Params: TJSONObject): TJSONData;
var
  Row: TMeasurementRow;
  Rows: TJSONArray;
begin
  CheckMeasurementsShared;
  Rows := TJSONArray.Create;
  for Row in MeasurementRows(Document.Pattern, Document.Measurements, OptionalString(Params, 'search')) do
    Rows.Add(TJSONObject.Create(['key', Row.Key, 'value', Row.Value, 'description', Row.Description, 'missing', Row.Missing]));
  Result := TJSONObject.Create(['rows', Rows]);
end;

function SuggestionToJSON(const Suggestion: TSuggestion; Kind: TSuggestionKind; Pattern: TPattern): TJSONObject;
begin
  Result := TJSONObject.Create(['text', Suggestion.Text, 'value', ReportFloat(Suggestion.Value), 'valueText',
    SuggestionValueText(Suggestion.Value, Kind, Pattern.Units), 'delta', ReportFloat(Suggestion.Delta), 'deltaText',
    SuggestionDeltaText(Suggestion.Delta, Kind, Pattern.Units)]);
end;

function TEditorApiServer.DoSuggest(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  Node: TEvalNode;
  FieldName: string;
  Target: double;
  Source: TSuggestionSource;
  Found: TSuggestions;
  Suggestion: TSuggestion;
  Items: TJSONArray;
  Answer: TJSONObject;
begin
  Pattern := Document.Pattern;
  Node := FindTarget(Params);
  FieldName := RequireString(Params, 'field');
  if not CanSuggest(Pattern, Node, FieldName) then
    raise EApiError.Create(RPC_REFUSED, Format(rsEditorCannotSuggest, [FieldName, Node.DisplayName]));
  if not OptionalNumber(Params, 'value', Target) then
    SuggestionTarget(Pattern, Node, FieldName, Target);
  Source := TSuggestionSource.Create(Pattern, Node, FieldName);
  try
    Found := Source.Match(Target);
    Answer := TJSONObject.Create;
    Answer.Add('kind', SUGGESTION_KIND_NAMES[Source.Kind]);
    Answer.Add('tolerance', SuggestionToleranceText(Source.Kind, Pattern.Units));
    Items := TJSONArray.Create;
    Answer.Add('items', Items);
    for Suggestion in Found.Items do
      Items.Add(SuggestionToJSON(Suggestion, Source.Kind, Pattern));
    if Found.HasNearest then
      Answer.Add('nearest', SuggestionToJSON(Found.Nearest, Source.Kind, Pattern))
    else
      Answer.Add('nearest', TJSONNull.Create);
    Result := Answer;
  finally
    FreeAndNil(Source);
  end;
end;

// An enumeration's value as the API names it: without its prefix, starting
// in lower case, as kcToolPoint gives toolPoint
function EnumName(Info: PTypeInfo; Value, PrefixLength: integer): string;
begin
  Result := Copy(GetEnumName(Info, Value), PrefixLength + 1, MaxInt);
  if Result <> '' then
    Result[1] := LowerCase(Result[1]);
end;

function ToolsToJSON: TJSONArray;
var
  Tool: TCanvasTool;
  Info: TCanvasToolInfo;
begin
  Result := TJSONArray.Create;
  for Tool := Low(TCanvasTool) to High(TCanvasTool) do
  begin
    Info := CanvasToolInfo(Tool);
    Result.Add(TJSONObject.Create(['name', CANVAS_TOOL_NAMES[Tool], 'caption', Info.Caption, 'hint', Info.Hint, 'icon',
      APP_ICON_NAMES[Info.Icon], 'keys', ShortcutInfo(Info.Command).Keys]));
  end;
end;

function CommandsToJSON: TJSONArray;
var
  Command: TIconCommand;
begin
  Result := TJSONArray.Create;
  for Command in IconCommands do
    if Command.App = saDesign then
      Result.Add(TJSONObject.Create(['name', Command.Name, 'icon', APP_ICON_NAMES[Command.Icon], 'place',
        ICON_PLACE_NAMES[Command.Place], 'menu', Command.Menu, 'keys', Command.Keys, 'description', Command.Description]));
end;

function ShortcutsToJSON: TJSONArray;
const
  // kc and sg
  PREFIX_LENGTH = 2;
var
  Command: TKeyCommand;
  Info: TShortcutInfo;
begin
  Result := TJSONArray.Create;
  for Command := Low(TKeyCommand) to High(TKeyCommand) do
  begin
    Info := ShortcutInfo(Command);
    if saDesign in Info.Apps then
      Result.Add(TJSONObject.Create(['command', EnumName(TypeInfo(TKeyCommand), Ord(Command), PREFIX_LENGTH), 'keys', Info.Keys,
        'kind', SHORTCUT_KIND_NAMES[Info.Kind], 'group', EnumName(TypeInfo(TShortcutGroup), Ord(Info.Group), PREFIX_LENGTH),
        'description', Info.Description]));
  end;
end;

function TEditorApiServer.DispatchMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'editor_scene': Result := DoScene(Params);
    'editor_snap': Result := DoSnap(Params);
    'editor_objects_at': Result := DoObjectsAt(Params);
    'editor_objects_in_box': Result := DoObjectsInBox(Params);
    'editor_add_point': Result := DoAddPoint(Params);
    'editor_complete': Result := DoComplete(Params);
    'editor_list_objects': Result := DoListObjects(Params);
    'editor_list_variables': Result := DoListVariables(Params);
    'editor_list_measurements': Result := DoListMeasurements(Params);
    'editor_suggest': Result := DoSuggest(Params);
    'editor_tables': Result := TJSONObject.Create(['tools', ToolsToJSON, 'commands', CommandsToJSON, 'shortcuts', ShortcutsToJSON]);
    else
      Result := inherited DispatchMethod(Method, Params);
  end;
end;

end.
