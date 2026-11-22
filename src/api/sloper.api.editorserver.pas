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
  rsEditorAddPointChange = 'Add point';

implementation

uses
  Sloper.API.Rpc, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Transform,
  Sloper.Core.PatternCheck, Sloper.Core.Materials, Sloper.Editor.Scene;

const
  // How finely curves are flattened when the call does not say, in mm
  DEFAULT_TOLERANCE = 0.1;
  // The finest flattening asked for, in mm, so a curve cannot become millions of points
  MIN_TOLERANCE = 0.001;
  SNAP_KIND_NAMES: array[TSnapKind] of string = ('free', 'point', 'crossing', 'edge', 'horizontal', 'vertical');

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
  end;
  Result := Built;
end;

function RequireNumber(Params: TJSONObject; const AName: string): double;
begin
  Result := 0;
  if not OptionalNumber(Params, AName, Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
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
    BeginChange(rsEditorAddPointChange);
    Key := PointFromSnap(Document.Pattern, Snap);
    if Key = '' then
      RefuseChange;
    EndChange;
    Answer := NodeToJSON(Document, Document.Pattern.FindNode(Key));
  end;
  Answer.Add('existing', Existing);
  Result := Answer;
end;

function TEditorApiServer.DispatchMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'editor_scene': Result := DoScene(Params);
    'editor_snap': Result := DoSnap(Params);
    'editor_objects_at': Result := DoObjectsAt(Params);
    'editor_objects_in_box': Result := DoObjectsInBox(Params);
    'editor_add_point': Result := DoAddPoint(Params);
    else
      Result := inherited DispatchMethod(Method, Params);
  end;
end;

end.
