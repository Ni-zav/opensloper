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
  SysUtils, fpjson, Sloper.API.Methods, Sloper.API.Server, Sloper.Document.PatternDocument, Sloper.Core.TextFields,
  Sloper.Core.Geometry, Sloper.Core.Evaluator, Sloper.Editor.Snap, Sloper.Core.Drag, Sloper.Editor.PanelEdits,
  Sloper.Editor.SuggestionGrade, Sloper.Core.Garment;

type
  TEditorApiServer = class(TApiServer)
  private
    FPending: TPendingMeasurements;
    // The measurement file the pending edits are for
    FPendingPath: string;
    // What the document has said changed since editor_changes last answered
    FChanges: TDocumentChanges;
    FSaveRevision: integer;
    // The point, note or curve being dragged, and the one field a point's drag
    // changes, or '' for all it can; '' when no drag is open
    FDragKey, FDragField: string;
    // For a curve, the length field of the handle being dragged
    FDragHandle: string;
    // A callout's tip is being dragged: it changes nothing until dropped,
    // where it last snapped (FTipSnap, for a move to FTipClick), if it moved
    FDragTip, FTipMoved: boolean;
    FTipSnap: TSnap;
    FTipClick: TVec2;
    // The values at each size of the field whose suggestions were last asked
    // for, kept while it stays the same and the pattern does not change, or
    // changes only by a drag, as making it copies the pattern for every size
    FGrade: TGradeCheck;
    FGradeKey, FGradeField: string;
    // Keeps the Garment tab's pieces, so only those that changed are built again
    FGarment: TGarmentBuilder;
    // The Garment tab's scene: as the canvas shows the pieces, of the call's material
    function GarmentScene(Params: TJSONObject): TGarmentScene;
    function DoGarment(Params: TJSONObject): TJSONData;
    function DoGarmentMarks(Params: TJSONObject): TJSONData;
    function DoProblems: TJSONData;
    // The grade check for the object's field, made again when out of date
    function GradeFor(Node: TEvalNode; const FieldName: string): TGradeCheck;
    function DoTipTo(Params: TJSONObject): TJSONData;
    function DoTipEnd(Cancel: boolean): TJSONData;
    procedure RequireDrag;
    // The handle of the curve being dragged
    function DraggedHandle: TCurveHandle;
    // Where the dragged object is: a point's place, a note's top left or a handle's end
    function DragPosition: TJSONObject;
    function DoDragBegin(Params: TJSONObject): TJSONData;
    function DoDragTo(Params: TJSONObject): TJSONData;
    function DoDragEnd(Cancel: boolean): TJSONData;
    procedure DocumentChanged(ADocument: TPatternDocument; Changes: TDocumentChanges);
    function DoChanges: TJSONData;
    function DoSnapshot: TJSONData;
    function DoSaveComplete(Params: TJSONObject): TJSONData;
    function DoMarkUnsaved: TJSONData;
    // The snap for the call's place, radius and anchor
    function CallSnap(Params: TJSONObject): TSnap;
    function FieldValuesFor(Params: TJSONObject): TFieldValues;
    function DoScene(Params: TJSONObject): TJSONData;
    function DoSnap(Params: TJSONObject): TJSONData;
    function DoObjectsAt(Params: TJSONObject): TJSONData;
    function DoObjectsInBox(Params: TJSONObject): TJSONData;
    function DoHandles(Params: TJSONObject): TJSONData;
    function DoBounds(Params: TJSONObject): TJSONData;
    function DoVariableAdd: TJSONData;
    function DoVariableDelete(Params: TJSONObject): TJSONData;
    function DoVariableSet(Params: TJSONObject): TJSONData;
    function DoProperties(Params: TJSONObject): TJSONData;
    function DoPropertySet(Params: TJSONObject): TJSONData;
    // The snap of a place given as a group of x, y and radius
    function SnapOf(Group: TJSONObject; const AnchorKey: string): TSnap;
    function DoToolSnap(Params: TJSONObject): TJSONData;
    function DoToolClick(Params: TJSONObject): TJSONData;
    function KeysParam(Params: TJSONObject; const AName: string): TStringArray;
    function DoLabelKeys(Params: TJSONObject): TJSONData;
    function DoSeamPick(Params: TJSONObject): TJSONData;
    function DoSeamMake(Params: TJSONObject): TJSONData;
    function DoDelete(Params: TJSONObject): TJSONData;
    function DoConvertPoint(Params: TJSONObject): TJSONData;
    function DoCopy(Params: TJSONObject; Cut: boolean): TJSONData;
    function DoPaste(Params: TJSONObject): TJSONData;
    function DoVariableImport(Params: TJSONObject): TJSONData;
    function DoComplete(Params: TJSONObject): TJSONData;
    function DoListObjects(Params: TJSONObject): TJSONData;
    function DoListVariables(Params: TJSONObject): TJSONData;
    function DoListMeasurements(Params: TJSONObject): TJSONData;
    // The Measurements tab's unsaved edits, dropped when another set is used
    function Pending: TPendingMeasurements;
    procedure CheckNotTesting;
    procedure CheckNothingPending;
    function DoMeasurementAdd: TJSONData;
    function DoMeasurementSet(Params: TJSONObject): TJSONData;
    function DoMeasurementsSave(Params: TJSONObject): TJSONData;
    function DoMeasurementsRevert: TJSONData;
    function DoMeasurementSize(Params: TJSONObject): TJSONData;
    function DoMeasurementScale(Params: TJSONObject): TJSONData;
    function DoSuggest(Params: TJSONObject): TJSONData;
    function DoSuggestPreview(Params: TJSONObject): TJSONData;
    function DoNotePreview(Params: TJSONObject): TJSONData;
    function DoExportDraft(Params: TJSONObject): TJSONData;
    function DoPrint(Params: TJSONObject): TJSONData;
    function DoMaterials: TJSONData;
    function DoMaterial(Params: TJSONObject): TJSONData;
    function DoMaterialSet(Params: TJSONObject): TJSONData;
    function DoMaterialAdd: TJSONData;
    function DoMaterialDelete(Params: TJSONObject): TJSONData;
    function DoFeatures(Params: TJSONObject): TJSONData;
    function DoFeatureApply(Params: TJSONObject): TJSONData;
  protected
    function DispatchMethod(const Method: string; Params: TJSONObject): TJSONData; override;
  public
    procedure AfterConstruction; override;
    destructor Destroy; override;
  end;

// The editor's methods, documented as the API's are
function EditorMethods: TApiMethodArray;

resourcestring
  rsEditorScene = 'What the canvas shows, in drawing order: pieces, then edges, then points. Hidden objects and ' +
    'objects never computed are left out; failing ones are at their last good result.';
  rsEditorTolerance = 'How far a curve''s polyline may stray from it, in mm; default 0.1';
  rsEditorSceneReturns = '`unit`, the pattern''s unit (mm, cm or in), which the rulers and grid count in; ' +
    '`isolated`, the piece shown alone or null; `pieces`, each with `id`, `name`, `state`, ' +
    '`locked`, `dimmed`, `fillColor`, `fillStyle`, its `cutLine`, `marks` (grainline, fold and marking strokes) and ' +
    '`notches`, each a flat list of segments x1, y1, x2, y2, its label''s `caption`, its `middle` (x, y) and its ' +
    '`chevrons` (x, y and angle for each); `notes` (left out while annotations are hidden), each with `print`, ' +
    '`lines` with fields filled in, `size` in points, `lineHeight` in mm, `align`, `boxed`, `font`, `bold`, ' +
    '`italic`, `box` and `frame` (minX, minY, maxX, maxY), `anchorAt` (x, y), `leader` and `leaderStrokes` ' +
    '(segments), and for a stamp `stamp`, its paths, each with `d` (path data in mm where it is drawn), `fill` and ' +
    '`stroke` (#rrggbb or none), `strokeWidth` (mm) and `evenOdd`; `seams`, each with its sides'' edges as `sideA` and `sideB` (a polyline ' +
    'each) and their `chevronsA` and `chevronsB`; `markers`, each with the `id` of its point or edge and ' +
    'its `strokes`, as marks are; `edges`, each with `id`, `name`, `role`, ' +
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
  rsEditorObjectsAt = 'Everything under a place, in the order a click picks it: notes, the one drawn on top first, ' +
    'then points nearest first, then edges nearest first, then pieces smallest first.';
  rsEditorPointRadius = 'How near a point must be, in mm';
  rsEditorEdgeRadius = 'How near an edge must be, in mm';
  rsEditorObjectsReturns = '`objects`, their IDs; with a selection, `tip`, the selected callout whose tip is there, ' +
    'or null, and `handle`, the handle of a selected curve there (`edge` and `field`, its length field), or null';
  rsEditorObjectsSelection = 'The selected objects'' IDs, whose callouts'' tips and curves'' handles lie over ' +
    'everything else';
  rsEditorVariableAdd = 'Adds a variable as the Variables tab''s Add does: the next free name, with formula 0, as one ' +
    'undo step.';
  rsEditorVariableAddReturns = '`id`, the new variable''s';
  rsEditorVariableDelete = 'Deletes a variable as the Variables tab does, as one undo step; refused while something ' +
    'reads it.';
  rsEditorVariableTarget = 'The variable, by ID or name';
  rsEditorVariableDeleteReturns = '`done`, true';
  rsEditorVariableSet = 'Commits a cell of the Variables tab as one undo step: its name, its formula as typed with ' +
    'names, or its description.';
  rsEditorVariableColumn = 'The cell''s column';
  rsEditorVariableText = 'What the cell holds';
  rsEditorVariableSetReturns = '`done`, false when refused, with the `reason` and `errorPos`, where in a formula the ' +
    'problem is, in characters from 1 (0 for none)';
  rsEditorProperties = 'What the Properties tab shows for a selection: one object''s rows in order, or what the ' +
    'selection is when it is not one object. A repeat''s first point shows the repeat.';
  rsEditorPropertiesSelection = 'The selected objects, by ID, name, or key as the scene gives a repeat''s points';
  rsEditorPropertiesReturns = '`id`, the object shown, or null; `title`, what to show instead when none is; ' +
    '`locked`, its rows are read-only apart from `locked`; `rows`, each with `id`, `kind` (text, name, formula, ' +
    'choice, check, button, problem, number, longText, font or color), `caption` and `text` (a check''s box caption, ' +
    'a color row''s own colour or ""), a formula row''s `field` and `suggest`, true when editor_suggest can suggest ' +
    'formulas for it, a choice row''s `choices` and `choice` (its index, ' +
    'or -1), a font row''s `choices` (the default font''s caption) and a color row''s (following the material, its ' +
    'own), a color row''s `color` as drawn, a check row''s `checked`, a number row''s `value`, `min`, `max`, `step` ' +
    'and `decimals`, `enabled` false when it cannot be changed now, and a `hint` when it has one';
  rsEditorPropertyTarget = 'The object, by ID or name';
  rsEditorPropertySet = 'Commits a row of the Properties tab as one undo step: the name or a formula as typed with ' +
    'names, a long text, font or colour (`text`), a number (`number`), or a choice, check or button (`value`). ' +
    'What the row already holds makes no step.';
  rsEditorPropertyRow = 'The row''s `id`, as editor_properties gives it';
  rsEditorPropertyField = 'A formula row''s field, in place of `row`';
  rsEditorPropertyText = 'What the name, formula, long text, font or colour field holds';
  rsEditorPropertyValue = 'A choice''s index, 1 or 0 for a check; a button ignores it';
  rsEditorPropertyNumber = 'A number row''s value';
  rsEditorPropertyFrom = 'With `row` grain, the grainline between two points: the first point''s index in the ' +
    'grainFrom row''s choices, with `to`';
  rsEditorPropertyTo = 'The second point''s index in the grainTo row''s choices';
  rsEditorPropertySetReturns = '`done`, false when refused, with the `reason` and, for a formula, `errorPos`, where ' +
    'the problem is, in characters from 1 (0 for none)';
  rsEditorBounds = 'The box round objects, as the canvas shows or zooms to a selection';
  rsEditorBoundsTargets = 'The objects'' IDs';
  rsEditorBoundsReturns = '`bounds`, minX, minY, maxX and maxY in mm, or null when none of them has a place';
  rsEditorListClick = 'The selection after a click on a row of a list: a click selects the row, Ctrl or Cmd adds or ' +
    'removes it, Shift selects from the anchor to it in list order.';
  rsEditorListVisible = 'The keys of the rows listed, in list order: object IDs, or measurement keys';
  rsEditorListSelected = 'The keys of the selected rows';
  rsEditorListAnchor = 'The row the last plain or toggling click chose, from which Shift selects';
  rsEditorListClicked = 'The clicked row''s key';
  rsEditorListToggle = 'Ctrl or Cmd was held';
  rsEditorListExtend = 'Shift was held';
  rsEditorListClickReturns = '`selection`, the keys selected, in list order for a range';
  rsEditorHandles = 'The handles of the selected curves, to draw and drag: the end of each tangent line, set by an ' +
    'angle and a length.';
  rsEditorHandlesReturns = '`handles`, each with `edge`, `field` (its length field, which names it for a drag), ' +
    '`anchorX` and `anchorY`, where it starts on the curve, `x` and `y`, its end, and `draggable`, false when a ' +
    'formula or a lock sets it';
  rsEditorObjectsInBox = 'The points, edges and pieces lying wholly inside a box, in pattern order; a repeat counts as ' +
    'its points.';
  rsEditorMinX = 'The box''s left, in mm';
  rsEditorMinY = 'Its top, in mm';
  rsEditorMaxX = 'Its right, in mm';
  rsEditorMaxY = 'Its bottom, in mm';
  rsEditorToolSnap = 'Where a click of a canvas tool would snap, and what the status bar says: the snap''s ' +
    'description, or for a circle or rectangle after its first click the size it would have.';
  rsEditorTool = 'The tool, as editor_tables names it';
  rsEditorStart = 'The tool''s first click, for line, curve, circle and rectangle: a group of `x`, `y` and `radius` ' +
    'as the click gave them. A line or curve lines up with its start first, once that is a point.';
  rsEditorToolSnapReturns = 'As editor_snap gives it, with `start`, where the first click snapped (`kind`, `x`, `y`), ' +
    'and `startObjects`, what it works from, when given';
  rsEditorToolClick = 'Does what a click of a canvas tool does, as one undo step: point adds the point it snaps to; ' +
    'line and curve take a first click, then make the edge with its points, carrying on from its end; circle and ' +
    'rectangle take a first click, then make the shape; piece makes a piece of the closed outline round the place; ' +
    'notch removes the notches there, or adds one where a piece''s seam line passes; text adds a note hung from what ' +
    'it snaps to; callout takes what its tip points at, then where its text goes.';
  rsEditorExtend = 'For the curve tool, the curve or curve path to carry on through the click as one path, as ' +
    'Shift+click does';
  rsEditorRole = 'The role of the edges a line, curve, circle or rectangle makes; outline by default';
  rsEditorToolClickReturns = '`done`, true when it made a change; `started`, true when the click was a first click to ' +
    'keep as `start`; `select`, the IDs to select, or null to leave the selection; `message` for the status bar; ' +
    'for line and curve, `end`, where the next one starts (`x`, `y`), and for a curve `curve`, the edge to carry on';
  rsEditorBusy = 'Finish the drag first';
  rsEditorFileName = 'The pattern file''s name, for the {pattern.name} field in notes; by default the file it was opened from';
  rsEditorNoteMargin = 'How near a note''s text must be, in mm; 0 by default';
  rsEditorLabelKeys = 'Which objects the canvas labels: in contextual mode the hovered object, the selection with ' +
    'what it reads and what reads it, the objects a tool is working with and those the formula suggestions in view ' +
    'read; every point, edge and piece in all; none in none.';
  rsEditorLabelMode = 'contextual, all or none';
  rsEditorSelection = 'The selected objects'' IDs';
  rsEditorHover = 'The hovered object''s ID';
  rsEditorSuggestObjects = 'The IDs of the objects the formula suggestions in view read, as editor_suggest gives them';
  rsEditorToolObjects = 'The IDs of the objects the tool is working with, as editor_tool_snap gives them';
  rsEditorLabelKeysReturns = '`objects`, their IDs in pattern order';
  rsEditorSeamPick = 'The Seam tool''s click: the piece''s edge at the place goes on the side being picked, or comes ' +
    'off it. Without a place, only says how the sides compare, as after Tab.';
  rsEditorSideA = 'Side A as picked so far, each with `piece` and `edge`';
  rsEditorSideB = 'Side B as picked so far';
  rsEditorOnB = 'Picking side B';
  rsEditorSeamPickReturns = '`picked`, false when there was no edge there; `sideA` and `sideB` as they now are; ' +
    '`lines`, each side''s edges as flat lists x, y, x, y to draw; `message`, the progress or why nothing was picked';
  rsEditorSeamMake = 'Makes the seam between the sides picked, as one undo step.';
  rsEditorSeamMakeReturns = 'As editor_tool_click gives it';
  rsEditorDelete = 'Deletes the selected objects, as the Delete key on the canvas, as one undo step; refused, changing ' +
    'nothing, while another object uses one of them.';
  rsEditorDeleteReturns = '`done`, true when they were deleted; `message`, why not; `select`, the selection ' +
    'afterwards, or null to leave it';
  rsEditorDeleteSelection = 'The selected objects, by ID, or by name for a repeat''s point';
  rsEditorConvertPoint = 'Changes how the first selected point is placed, from the other selected points and edges in ' +
    'the order they were selected, as Tools > Points > Change To, as one undo step. It keeps its ID, name and users.';
  rsEditorConvertPointReturns = '`done`, true when it changed; `message`, what changed, how far the point moved and ' +
    'whether its formulas became numbers, or why not; `select`, the selection afterwards, or null to leave it';
  rsEditorConvertPointSelection = 'The point, then what it is placed from, by ID';
  rsEditorConvertPointType = 'What it becomes, as editor_tables pointTypes names it';
  rsEditorCopy = 'Copies the selected points and edges, as Edit > Copy: the fragment to put on the clipboard, which ' +
    'editor_paste takes. Changes nothing.';
  rsEditorCopyReturns = '`done`, true when something was copied; `text`, the fragment, empty when nothing could be ' +
    'copied; `names`, the copied objects'' names for the plain text clipboard; `message`, what was copied, or why ' +
    'not; `select`, null';
  rsEditorCut = 'Copies the selected points and edges and deletes them, as Edit > Cut, as one undo step; refused, ' +
    'changing nothing, when anything selected cannot be copied or another object uses it.';
  rsEditorCutReturns = 'As editor_copy gives it, with `select` the selection afterwards when they were cut';
  rsEditorPaste = 'Pastes a fragment copied by editor_copy or editor_cut, or by the Automation API''s copy_objects, ' +
    'as Edit > Paste, as one undo step: copies of its objects, renamed where their names are taken.';
  rsEditorPasteReturns = '`done`, true when it was pasted; `message`, what was pasted, or why not; `select`, the ' +
    'pasted objects';
  rsEditorFragment = 'The fragment''s text, as the clipboard holds it';
  rsEditorVariableImport = 'Imports the variables of another pattern file, as the Variables tab''s Import...: one undo ' +
    'step, keeping those whose names this pattern has; refused when the files are in different units.';
  rsEditorVariableImportReturns = '`done`, false when the file cannot be imported; `message`, what was imported and ' +
    'kept, or why not; `warning`, true when a variable was kept with another formula or nothing was imported; ' +
    '`added`, the IDs of the variables added';
  rsEditorImportText = 'The other pattern file''s contents';
  rsEditorImportFileName = 'Its name, for the message';
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
  rsEditorListMeasurementsReturns = '`rows`, each with `key`, `value`, `description`, `missing`, `pending` (an unsaved ' +
    'edit) and `isNew` (made by editor_measurement_add, so its key can be changed); `file`, the measurement file as ' +
    'the pattern records it, or empty; `sizes`, a size table''s sizes, and `size`, the one used; `testPercent`, the ' +
    'test size; and `pendingCount`, how many edits are unsaved';
  rsEditorMeasurementAdd = 'Adds an unsaved measurement to the Measurements tab, as its Add does: the first free key ' +
    'of measurement, measurement2 and so on, with no value yet.';
  rsEditorMeasurementAddReturns = '`key`, the new row''s';
  rsEditorMeasurementSet = 'Commits a cell of the Measurements tab as an unsaved edit, kept until ' +
    'editor_measurements_save writes them all or editor_measurements_revert drops them. Only a new row''s key can ' +
    'change.';
  rsEditorMeasurementKey = 'The row''s key';
  rsEditorMeasurementColumn = 'The cell''s column';
  rsEditorMeasurementText = 'What the cell holds: a value in mm, with a point for decimals';
  rsEditorMeasurementSetReturns = '`done`, false when refused, with the `reason`; `key`, the row''s key afterwards';
  rsEditorMeasurementsSave = 'Makes the unsaved edits to the measurement set and gives the file''s new contents back ' +
    'to be saved; nothing is written. With no set, a new one is made, which the pattern records.';
  rsEditorMeasurementsFile = 'Where the pattern records a new set, relative to the pattern''s folder with /, when it ' +
    'has none';
  rsEditorMeasurementsSaveReturns = '`done`, false when refused, with the `reason`; `text`, the set''s file, ' +
    '`file`, as the pattern records it, and `message`, what was saved, in words';
  rsEditorMeasurementsRevert = 'Drops the Measurements tab''s unsaved edits.';
  rsEditorMeasurementsRevertReturns = '`done`, true';
  rsEditorMeasurementSize = 'Uses another size of a size table; refused while edits are unsaved.';
  rsEditorMeasurementSizeName = 'The size, as the table names it';
  rsEditorMeasurementSizeReturns = '`size`, the one used';
  rsEditorMeasurementScale = 'Tries the pattern with every measurement larger or smaller; nothing is saved. Refused ' +
    'while edits are unsaved.';
  rsEditorMeasurementPercent = 'How much larger, in percent, from -20 to 20; 0 is as measured';
  rsEditorMeasurementScaleReturns = '`testPercent`, as set';
  rsEditorNewMeasurementsFile = 'Name the new measurement file with `file`';
  rsEditorPendingMeasurements = 'Save or revert the measurement edits first';
  rsEditorSuggest = 'Formulas that give about the value of an object''s field, from its measurements, variables and ' +
    'the objects it may read, best first.';
  rsEditorSuggestTarget = 'The object, by ID or name';
  rsEditorField = 'The field, such as length or angle';
  rsEditorSuggestValue = 'The value to match, in mm, degrees or a ratio, as while dragging; the field''s own value ' +
    'when left out';
  rsEditorSuggestReturns = '`kind` (length, angle or ratio), `tolerance` in words, `items` within it, each with ' +
    '`text`, `value`, `valueText`, `delta`, `deltaText` and `objects`, the IDs of the objects it reads, and `nearest`, the closest of all, or null; with a size ' +
    'table, `sizes`, its first and last sizes, and on each item `range`, its values at them, and `sizeValues`, its ' +
    'value at every size, in words';
  rsEditorSuggestPreview = 'What a suggestion would make of the object: where the point would go, and the object ' +
    'at the smallest and largest sizes of the table.';
  rsEditorSuggestText = 'The suggested formula';
  rsEditorExportDraft = 'The draft as SVG, as the canvas shows it: its labels, fills, hidden roles, annotations and ' +
    'pieces, for Export Draft SVG.';
  rsEditorExportLabels = 'The objects the canvas labels, as editor_label_keys gives them';
  rsEditorExportNoFills = 'Pieces left unfilled';
  rsEditorExportDraftReturns = '`text`, the SVG file''s contents';
  rsEditorPrint = 'A PDF to print the pattern from, as the publish app''s tiled print of a new layout with every ' +
    'piece placed: pages with their row and column captions and overlaps, and a cover with the test square and ' +
    'the page map. Unsaved edits are included; nothing is saved.';
  rsEditorPrintPaper = 'The paper';
  rsEditorPrintReturns = '`done`; with it, `pdf`, the file''s bytes in Base64, and `warnings`, what the layout would ' +
    'warn of in the publish app; without it, the `reason`';
  // A pattern never saved, in the PDF's title and the layout's name
  rsEditorPrintUnnamed = 'pattern';
  rsEditorMaterials = 'The Materials tab''s list: each material''s row, the cut list they make, and the fills and ' +
    'fabrics a material can have, in words.';
  rsEditorGarment = 'The Garment tab: the pieces as sewn, darts closed and folds opened, shaded as on the desktop, ' +
    'as the canvas shows them (hidden pieces left out, an isolated one alone).';
  rsEditorGarmentMaterial = 'Only the pieces cut from this material, by name; all when empty, left out or not a material''s';
  rsEditorGarmentReturns = '`svg`, the drawing in mm; `bounds`, the box round the pieces in mm, `left`, `top`, ' +
    '`right` and `bottom`, or null with none; `pieces`, in drawing order, each with `id`, `name` and `outline`, its ' +
    'seam line as a flat list of x and y in the drawing''s mm; `notes`, what was left out; `materials`, the names ' +
    'to choose from; and `material`, the one shown, empty for all';
  rsEditorProblems = 'The Problems tab: every problem the pattern has, in words, with what it is about, as the ' +
    'status bar counts them.';
  rsEditorProblemsReturns = '`problems`, each with `text` and `kind`: object (with its `id`, on the canvas or a seam), ' +
    'variable (its `id`), measurement (its `key`) or none; and `blocked`, how many objects fail only because ' +
    'others do, which are counted rather than listed';
  rsEditorGarmentMarks = 'What the Garment tab marks for a selection: selected pieces are outlined, and a selected ' +
    'seam marked on both its sides, with the stitch line of a dart it closes.';
  rsEditorGarmentSelection = 'The canvas''s selection, by ID';
  rsEditorGarmentMarksReturns = '`pieces`, the IDs of the selected pieces shown, and `lines`, the seams'' lines as ' +
    'flat lists of x and y in the drawing''s mm';
  rsEditorMaterialsReturns = '`rows`, each with `name`, `color` (#RRGGBB), `fill` (tint or hatch), `fillCaption`, ' +
    '`allowance` and `size` in words, and `hatchAngle` in degrees; `cutList`; `unit`, the pattern''s; `fills` and ' +
    '`fabrics`, each choice''s `name` and `caption`';
  rsEditorMaterial = 'One material''s fields as the Materials dialog edits them.';
  rsEditorMaterialIndex = 'The material, by its place in the list from 0';
  rsEditorMaterialReturns = '`name`, `color`, `fill`, `allowance`, `width` and `length` (in the pattern''s unit, empty ' +
    'for none), `allowTurns` (true or false) and `fabric` (its name, empty for none), as text; `canDelete`, false for ' +
    'the last material';
  rsEditorMaterialSet = 'Changes one field of a material as one undo step; a refusal is an answer with the reason.';
  rsEditorMaterialField = 'The field';
  rsEditorMaterialText = 'Its new value, as editor_material gives it';
  rsEditorMaterialSetReturns = '`done`, and the `reason` when refused';
  rsEditorMaterialAdd = 'Adds a material with the next free name and colour, as one undo step.';
  rsEditorMaterialAddReturns = '`index`, its place in the list';
  rsEditorMaterialDelete = 'Deletes a material no piece is cut from, as one undo step; the last one stays.';
  rsEditorMaterialDeleteReturns = '`done`, and the `reason` when refused';
  rsEditorFeatures = 'The Features tab''s form for a feature: what it goes along for the selection, its fields with ' +
    'their captions, choices and values, whether they apply now, and whether Apply can add it. Without `values` the ' +
    'fields start at the pattern''s own; with `changed`, the values that follow a change to that field (another ' +
    'style starts at its own widths, a hem''s topstitching follows its depth).';
  rsEditorFeature = 'The feature';
  rsEditorFeatureSelection = 'The canvas''s selection, by ID or name';
  rsEditorFeatureValues = 'The fields'' values so far: a choice''s index, 1 or 0 for a box, else what is typed';
  rsEditorFeatureValueId = 'The field';
  rsEditorFeatureValueText = 'Its value';
  rsEditorFeatureChanged = 'The field just changed, whose values follow';
  rsEditorFeaturePrevious = 'What the changed field held before';
  rsEditorFeaturesReturns = '`features`, every feature''s `name` and `caption`; `header`, what it goes along or what to ' +
    'select; `note`, what Apply adds; `canApply`; `values`, each field''s `id` and `text`, to send back; `fields`, ' +
    'each with `id`, `kind` (text, choice, check or combo, a choice that may be typed), `caption` (beside a check), ' +
    '`text`, `choices` and `enabled`';
  rsEditorFeatureApply = 'Applies a feature from the Features tab''s values, as one undo step.';
  rsEditorFeatureApplyReturns = '`done`, and `message`, what was added or why nothing was';
  rsEditorNotePreview = 'A note as editor_scene draws it, with its text as typed and not yet committed, as the ' +
    'canvas shows it while the text is typed in the Properties tab; nothing changes.';
  rsEditorNotePreviewTarget = 'The note, by ID or name';
  rsEditorNotePreviewText = 'The text as typed, with names, and draft values in [ ] worked out';
  rsEditorNotePreviewReturns = '`note`, as one of editor_scene''s `notes`';
  rsEditorSuggestItemValue = 'Its value, as editor_suggest gives it';
  rsEditorSuggestPreviewReturns = '`position`, where the point would go (`x`, `y`), or null when the field does ' +
    'not place a point; `ghosts`, one for the first size and one for the last, each with `lines` (polylines, flat ' +
    'lists x, y, x, y, in mm) and `point` (x, y) or null; empty without a size table';
  rsEditorCannotSuggest = 'No formula can be suggested for the %s of %s';
  rsEditorChanges = 'What changed since this was last asked, as the desktop document tells its panels, with what ' +
    'undo and redo would do and whether the pattern is modified. The editor asks after each call that may change ' +
    'something, and updates what the changes name.';
  rsEditorSnapshot = 'The pattern''s work in progress, for the web editor to keep in the browser so a closed tab ' +
    'loses nothing: the pattern file''s contents, without counting them saved, and the measurement set given as ' +
    'text. Refused while a drag is open.';
  rsEditorSnapshotReturns = '`text`, the pattern file''s contents; `measurementsText`, the set''s file as given ' +
    'with `use_measurements` and changed since, or null when the set is read from disk or there is none; ' +
    '`measurementsFile`, where the pattern records the set; `modified`; `generation`, as in editor_changes; ' +
    '`revision`, to confirm a successful write';
  rsEditorSaveComplete = 'Counts a snapshot as saved after the browser has written it, if the pattern is still ' +
    'at that revision and no edit is in progress.';
  rsEditorSaveCompleteRevision = 'The revision returned by editor_snapshot';
  rsEditorSaveCompleteReturns = '`modified`, whether the current pattern still has unsaved changes';
  rsEditorMarkUnsaved = 'Counts the pattern as not saved, as after its work in progress is opened again; not an ' +
    'undo step.';
  rsEditorMarkUnsavedReturns = '`modified`, true';
  rsEditorChangesReturns = '`changes`, any of pattern (definitions or results), objectsReplaced (every object is new, ' +
    'as after undo or open), measurements (another set), history, file and view; `generation`, which grows when ' +
    'another pattern is opened; `canUndo`, `canRedo`, `undo` and `redo`, the steps'' names; `modified`';
  rsEditorDragBegin = 'Starts dragging a point, a note, a curve''s handle or a callout''s tip, as one undo step: editor_drag_to moves it, editor_drag_end ' +
    'keeps the step and editor_drag_cancel puts everything back. Other changes are refused until it ends.';
  rsEditorDragTarget = 'The point, note or curve, by ID or name';
  rsEditorDragHandle = 'For a curve, the handle to drag, by its length field as editor_handles gives it';
  rsEditorDragTip = 'For a callout, drag its tip: each move snaps and changes nothing, and editor_drag_end hangs ' +
    'the callout from where it last snapped';
  rsEditorDragRadius = 'For a callout''s tip, how far round the place to snap, in mm';
  rsEditorDragField = 'For a point, the one field to change, as while formula suggestions are open on it; by default ' +
    'every field a drag sets';
  rsEditorDragBeginReturns = '`x` and `y`, where the point, the note''s top left or the handle''s end is now, in mm; ' +
    'for a point dragged by one field, `guide`, the path it keeps to: `kind` line (through `x1`, `y1` and `x2`, ' +
    '`y2`) or circle (`cx`, `cy`, `radius`), or null for a place along an edge';
  rsEditorDragTo = 'Moves the object being dragged as near the place as its operation allows; a point along an edge ' +
    'stays on the edge.';
  rsEditorDragX = 'Where the point, the note''s top left, the handle''s end or the tip goes across, in mm';
  rsEditorDragY = 'Where it goes down, in mm';
  rsEditorDragToReturns = '`x` and `y`, where it now is, and `moved`, false with the `reason` when it could not move; ' +
    'for a callout''s tip, where it snapped, with the snap''s `kind`, the `message` saying what it would point at and ' +
    'the `leaderStrokes` to draw to it';
  rsEditorDragEnd = 'Ends the drag, keeping what it did as one undo step.';
  rsEditorDragEndReturns = '`changed`, false when it ended where it began, which makes no step';
  rsEditorDragCancel = 'Ends the drag, putting the object back where it was.';
  rsEditorDragCancelReturns = '`changed`, false';
  rsEditorNotDraggable = '%s is not a point or a note';
  rsEditorNoHandle = '%s has no handle %s';
  rsEditorNotCallout = '%s is not a callout';
  rsEditorNotNote = '%s is not a note';
  rsEditorNoDrag = 'No drag is open: call editor_drag_begin first';
  rsEditorDragOpen = 'A drag is already open';
  rsEditorTables = 'The design app''s tables the editor reads instead of copying: its canvas tools, its commands with ' +
    'their icons and menus, and its keys and mouse actions.';
  rsEditorTablesReturns = '`tools`, each with `name`, `caption`, `hint`, `icon` and `keys`; `commands`, each with ' +
    '`name`, `icon`, `place`, `menu`, `keys` and `description`; `shortcuts`, each with `command`, `keys`, `kind`, ' +
    '`group` and `description`. Keys are written as Mod+Shift+S, Mod being Ctrl, or Cmd on macOS. `roles`, each edge ' +
    'role with its `name`, `caption`, `color` (empty for outline and construction, drawn in ink) and `dashes`, dash and gap ' +
    'lengths in mm, empty for a solid line. `pointTypes`, what a point can be changed to with editor_convert_point, ' +
    'each with its `name`, `caption` and `hint`, what to select.';

implementation

uses
  TypInfo, Math, StrUtils, Sloper.API.Rpc, Sloper.Core.EvalTypes, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Transform, Sloper.Core.PatternCheck, Sloper.Core.Materials,
  Sloper.Core.Shortcuts, Sloper.Core.IconSet, Sloper.Editor.Scene, Sloper.Editor.Completion, Sloper.Editor.ObjectList,
  Sloper.Editor.Suggestion, Sloper.Editor.Tools, Sloper.Editor.SelectionEdits, Sloper.Editor.ToolEdits, Sloper.Editor.PropertyText,
  Sloper.Core.Note, Sloper.Core.Stamp, Sloper.Core.Seam, Sloper.Core.Settings, Sloper.Core.Measurements, Sloper.Editor.PropertyRows,
  Sloper.Editor.FeatureForms, Sloper.Editor.MaterialList, Sloper.Core.Units, base64, Sloper.Core.PatternSources, Sloper.Core.Fragment, Sloper.Core.VariableImport,
  Sloper.Output.DraftSVG, Sloper.Output.Layout, Sloper.Output.LayoutPDF, Sloper.Core.TypeChange, Sloper.Output.GarmentSVG,
  Sloper.Editor.Garment, Sloper.Core.Variables;

const
  // How finely curves are flattened when the call does not say, in mm
  DEFAULT_TOLERANCE = 0.1;
  // The finest flattening asked for, in mm, so a curve cannot become millions of points
  MIN_TOLERANCE = 0.001;
  // The tools whose clicks snap, and every tool editor_tool_click takes
  SNAP_TOOL_NAMES: array[0..6] of string = ('point', 'line', 'curve', 'circle', 'rectangle', 'text', 'callout');
  CLICK_TOOL_NAMES: array[0..8] of string = ('point', 'line', 'curve', 'circle', 'rectangle', 'piece', 'notch', 'text', 'callout');
  SNAP_KIND_NAMES: array[TSnapKind] of string = ('free', 'point', 'crossing', 'edge', 'horizontal', 'vertical');
  // The Variables tab's columns that can be edited, as TVariableColumn without the value
  VARIABLE_COLUMN_NAMES: array[0..2] of string = ('name', 'formula', 'description');
  VARIABLE_COLUMNS: array[0..2] of TVariableColumn = (vcName, vcFormula, vcDescription);
  MEASUREMENT_COLUMN_NAMES: array[TMeasurementColumn] of string = ('key', 'value', 'description');
  // The test size's reach, in percent either way, as the desktop's slider
  MAX_TEST_PERCENT = 20;
  OBJECT_FILTER_NAMES: array[TObjectFilter] of string = ('all', 'points', 'edges', 'pieces', 'notes', 'problems');
  // As TMaterialField
  MATERIAL_FIELD_NAMES: array[TMaterialField] of string = ('name', 'color', 'fill', 'allowance', 'width', 'length',
    'allowTurns', 'fabric');
  SUGGESTION_KIND_NAMES: array[TSuggestionKind] of string = ('none', 'length', 'angle', 'ratio');
  ICON_PLACE_NAMES: array[TIconPlace] of string = ('toolbar', 'tools', 'sideTabs', 'menu', 'properties');
  SHORTCUT_KIND_NAMES: array[TShortcutKind] of string = ('command', 'fixed', 'mouse');
  DOCUMENT_CHANGE_NAMES: array[TDocumentChange] of string = ('pattern', 'objectsReplaced', 'measurements', 'history', 'file',
    'view');

var
  Built: TApiMethodArray = nil;

function EditorMethods: TApiMethodArray;
begin
  if Length(Built) = 0 then
  begin
    AddApiMethod(Built, 'editor_scene', rsEditorScene, rsEditorSceneReturns, True);
    AddApiParam(Built, 'tolerance', apNumber, False, rsEditorTolerance);
    AddApiParam(Built, 'fileName', apText, False, rsEditorFileName);
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
    AddApiParam(Built, 'noteMargin', apNumber, False, rsEditorNoteMargin);
    AddApiParam(Built, 'fileName', apText, False, rsEditorFileName);
    AddApiParam(Built, 'selection', apReferences, False, rsEditorObjectsSelection);
    AddApiMethod(Built, 'editor_objects_in_box', rsEditorObjectsInBox, rsEditorObjectsReturns, True);
    AddApiParam(Built, 'minX', apNumber, True, rsEditorMinX);
    AddApiParam(Built, 'minY', apNumber, True, rsEditorMinY);
    AddApiParam(Built, 'maxX', apNumber, True, rsEditorMaxX);
    AddApiParam(Built, 'maxY', apNumber, True, rsEditorMaxY);
    AddApiMethod(Built, 'editor_variable_add', rsEditorVariableAdd, rsEditorVariableAddReturns);
    AddApiMethod(Built, 'editor_variable_delete', rsEditorVariableDelete, rsEditorVariableDeleteReturns);
    AddApiParam(Built, 'id', apTarget, True, rsEditorVariableTarget);
    AddApiMethod(Built, 'editor_variable_set', rsEditorVariableSet, rsEditorVariableSetReturns);
    AddApiParam(Built, 'id', apTarget, True, rsEditorVariableTarget);
    AddApiParam(Built, 'column', apChoice, True, rsEditorVariableColumn, string.Join(', ', VARIABLE_COLUMN_NAMES));
    AddApiParam(Built, 'text', apText, True, rsEditorVariableText);
    AddApiMethod(Built, 'editor_properties', rsEditorProperties, rsEditorPropertiesReturns, True);
    AddApiParam(Built, 'selection', apTexts, True, rsEditorPropertiesSelection);
    AddApiMethod(Built, 'editor_property_set', rsEditorPropertySet, rsEditorPropertySetReturns);
    AddApiParam(Built, 'id', apTarget, True, rsEditorPropertyTarget);
    AddApiParam(Built, 'row', apText, False, rsEditorPropertyRow);
    AddApiParam(Built, 'field', apText, False, rsEditorPropertyField);
    AddApiParam(Built, 'text', apText, False, rsEditorPropertyText);
    AddApiParam(Built, 'value', apWhole, False, rsEditorPropertyValue);
    AddApiParam(Built, 'number', apNumber, False, rsEditorPropertyNumber);
    AddApiParam(Built, 'from', apWhole, False, rsEditorPropertyFrom);
    AddApiParam(Built, 'to', apWhole, False, rsEditorPropertyTo);
    AddApiMethod(Built, 'editor_bounds', rsEditorBounds, rsEditorBoundsReturns, True);
    AddApiParam(Built, 'ids', apReferences, True, rsEditorBoundsTargets);
    AddApiMethod(Built, 'editor_list_click', rsEditorListClick, rsEditorListClickReturns, True);
    AddApiParam(Built, 'visible', apTexts, True, rsEditorListVisible);
    AddApiParam(Built, 'selected', apTexts, True, rsEditorListSelected);
    AddApiParam(Built, 'anchor', apText, False, rsEditorListAnchor);
    AddApiParam(Built, 'clicked', apText, True, rsEditorListClicked);
    AddApiParam(Built, 'toggle', apFlag, False, rsEditorListToggle);
    AddApiParam(Built, 'extend', apFlag, False, rsEditorListExtend);
    AddApiMethod(Built, 'editor_handles', rsEditorHandles, rsEditorHandlesReturns, True);
    AddApiParam(Built, 'selection', apReferences, True, rsEditorSelection);
    AddApiMethod(Built, 'editor_tool_snap', rsEditorToolSnap, rsEditorToolSnapReturns, True);
    AddApiParam(Built, 'tool', apChoice, True, rsEditorTool, string.Join(', ', SNAP_TOOL_NAMES));
    AddApiParam(Built, 'x', apNumber, True, rsEditorX);
    AddApiParam(Built, 'y', apNumber, True, rsEditorY);
    AddApiParam(Built, 'radius', apNumber, True, rsEditorRadius);
    AddApiParam(Built, 'start', apGroup, False, rsEditorStart);
    AddApiMethod(Built, 'editor_tool_click', rsEditorToolClick, rsEditorToolClickReturns);
    AddApiParam(Built, 'tool', apChoice, True, rsEditorTool, string.Join(', ', CLICK_TOOL_NAMES));
    AddApiParam(Built, 'x', apNumber, True, rsEditorX);
    AddApiParam(Built, 'y', apNumber, True, rsEditorY);
    AddApiParam(Built, 'radius', apNumber, True, rsEditorRadius);
    AddApiParam(Built, 'start', apGroup, False, rsEditorStart);
    AddApiParam(Built, 'extend', apReference, False, rsEditorExtend);
    AddApiParam(Built, 'role', apChoice, False, rsEditorRole, string.Join(', ', EDGE_ROLE_NAMES));
    AddApiMethod(Built, 'editor_label_keys', rsEditorLabelKeys, rsEditorLabelKeysReturns, True);
    AddApiParam(Built, 'mode', apChoice, False, rsEditorLabelMode, string.Join(', ', LABEL_MODE_NAMES));
    AddApiParam(Built, 'selection', apReferences, False, rsEditorSelection);
    AddApiParam(Built, 'hover', apReference, False, rsEditorHover);
    AddApiParam(Built, 'tool', apReferences, False, rsEditorToolObjects);
    AddApiParam(Built, 'suggestions', apReferences, False, rsEditorSuggestObjects);
    AddApiMethod(Built, 'editor_seam_pick', rsEditorSeamPick, rsEditorSeamPickReturns, True);
    AddApiParam(Built, 'x', apNumber, False, rsEditorX);
    AddApiParam(Built, 'y', apNumber, False, rsEditorY);
    AddApiParam(Built, 'radius', apNumber, False, rsEditorRadius);
    AddApiParam(Built, 'sideA', apList, True, rsEditorSideA);
    AddApiParam(Built, 'sideB', apList, True, rsEditorSideB);
    AddApiParam(Built, 'onB', apFlag, False, rsEditorOnB);
    AddApiMethod(Built, 'editor_seam_make', rsEditorSeamMake, rsEditorSeamMakeReturns);
    AddApiParam(Built, 'sideA', apList, True, rsEditorSideA);
    AddApiParam(Built, 'sideB', apList, True, rsEditorSideB);
    AddApiMethod(Built, 'editor_delete', rsEditorDelete, rsEditorDeleteReturns);
    AddApiParam(Built, 'selection', apReferences, True, rsEditorDeleteSelection);
    AddApiMethod(Built, 'editor_convert_point', rsEditorConvertPoint, rsEditorConvertPointReturns);
    AddApiParam(Built, 'selection', apReferences, True, rsEditorConvertPointSelection);
    AddApiParam(Built, 'type', apChoice, True, rsEditorConvertPointType, string.Join(', ', POINT_CONVERSION_TYPES));
    AddApiMethod(Built, 'editor_copy', rsEditorCopy, rsEditorCopyReturns, True);
    AddApiParam(Built, 'selection', apReferences, True, rsEditorDeleteSelection);
    AddApiMethod(Built, 'editor_cut', rsEditorCut, rsEditorCutReturns);
    AddApiParam(Built, 'selection', apReferences, True, rsEditorDeleteSelection);
    AddApiMethod(Built, 'editor_paste', rsEditorPaste, rsEditorPasteReturns);
    AddApiParam(Built, 'text', apText, True, rsEditorFragment);
    AddApiMethod(Built, 'editor_variable_import', rsEditorVariableImport, rsEditorVariableImportReturns);
    AddApiParam(Built, 'text', apText, True, rsEditorImportText);
    AddApiParam(Built, 'fileName', apText, True, rsEditorImportFileName);
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
    AddApiMethod(Built, 'editor_measurement_add', rsEditorMeasurementAdd, rsEditorMeasurementAddReturns);
    AddApiMethod(Built, 'editor_measurement_set', rsEditorMeasurementSet, rsEditorMeasurementSetReturns);
    AddApiParam(Built, 'key', apText, True, rsEditorMeasurementKey);
    AddApiParam(Built, 'column', apChoice, True, rsEditorMeasurementColumn, string.Join(', ', MEASUREMENT_COLUMN_NAMES));
    AddApiParam(Built, 'text', apText, True, rsEditorMeasurementText);
    AddApiMethod(Built, 'editor_measurements_save', rsEditorMeasurementsSave, rsEditorMeasurementsSaveReturns);
    AddApiParam(Built, 'file', apText, False, rsEditorMeasurementsFile);
    AddApiMethod(Built, 'editor_measurements_revert', rsEditorMeasurementsRevert, rsEditorMeasurementsRevertReturns);
    AddApiMethod(Built, 'editor_measurement_size', rsEditorMeasurementSize, rsEditorMeasurementSizeReturns);
    AddApiParam(Built, 'size', apText, True, rsEditorMeasurementSizeName);
    AddApiMethod(Built, 'editor_measurement_scale', rsEditorMeasurementScale, rsEditorMeasurementScaleReturns);
    AddApiParam(Built, 'percent', apWhole, True, rsEditorMeasurementPercent);
    AddApiMethod(Built, 'editor_suggest', rsEditorSuggest, rsEditorSuggestReturns, True);
    AddApiParam(Built, 'id', apTarget, True, rsEditorSuggestTarget);
    AddApiParam(Built, 'field', apText, True, rsEditorField);
    AddApiParam(Built, 'value', apNumber, False, rsEditorSuggestValue);
    AddApiMethod(Built, 'editor_export_draft', rsEditorExportDraft, rsEditorExportDraftReturns, True);
    AddApiParam(Built, 'labels', apTexts, True, rsEditorExportLabels);
    AddApiParam(Built, 'noFills', apFlag, False, rsEditorExportNoFills);
    AddApiParam(Built, 'fileName', apText, False, rsEditorFileName);
    AddApiMethod(Built, 'editor_print', rsEditorPrint, rsEditorPrintReturns, True);
    AddApiParam(Built, 'paper', apChoice, False, rsEditorPrintPaper, 'A4, A3, Letter');
    AddApiParam(Built, 'fileName', apText, False, rsEditorFileName);
    AddApiMethod(Built, 'editor_materials', rsEditorMaterials, rsEditorMaterialsReturns, True);
    AddApiMethod(Built, 'editor_problems', rsEditorProblems, rsEditorProblemsReturns, True);
    AddApiMethod(Built, 'editor_garment', rsEditorGarment, rsEditorGarmentReturns, True);
    AddApiParam(Built, 'material', apText, False, rsEditorGarmentMaterial);
    AddApiMethod(Built, 'editor_garment_marks', rsEditorGarmentMarks, rsEditorGarmentMarksReturns, True);
    AddApiParam(Built, 'selection', apReferences, True, rsEditorGarmentSelection);
    AddApiParam(Built, 'material', apText, False, rsEditorGarmentMaterial);
    AddApiMethod(Built, 'editor_material', rsEditorMaterial, rsEditorMaterialReturns, True);
    AddApiParam(Built, 'index', apWhole, True, rsEditorMaterialIndex);
    AddApiMethod(Built, 'editor_material_set', rsEditorMaterialSet, rsEditorMaterialSetReturns);
    AddApiParam(Built, 'index', apWhole, True, rsEditorMaterialIndex);
    AddApiParam(Built, 'field', apChoice, True, rsEditorMaterialField, string.Join(', ', MATERIAL_FIELD_NAMES));
    AddApiParam(Built, 'text', apText, True, rsEditorMaterialText);
    AddApiMethod(Built, 'editor_material_add', rsEditorMaterialAdd, rsEditorMaterialAddReturns);
    AddApiMethod(Built, 'editor_material_delete', rsEditorMaterialDelete, rsEditorMaterialDeleteReturns);
    AddApiParam(Built, 'index', apWhole, True, rsEditorMaterialIndex);
    AddApiMethod(Built, 'editor_features', rsEditorFeatures, rsEditorFeaturesReturns, True);
    AddApiParam(Built, 'feature', apChoice, True, rsEditorFeature, string.Join(', ', FEATURE_NAMES));
    AddApiParam(Built, 'selection', apTexts, True, rsEditorFeatureSelection);
    AddApiParam(Built, 'values', apList, False, rsEditorFeatureValues);
    AddApiParam(Built, 'values[].id', apText, True, rsEditorFeatureValueId);
    AddApiParam(Built, 'values[].text', apText, True, rsEditorFeatureValueText);
    AddApiParam(Built, 'changed', apText, False, rsEditorFeatureChanged);
    AddApiParam(Built, 'previous', apText, False, rsEditorFeaturePrevious);
    AddApiMethod(Built, 'editor_feature_apply', rsEditorFeatureApply, rsEditorFeatureApplyReturns);
    AddApiParam(Built, 'feature', apChoice, True, rsEditorFeature, string.Join(', ', FEATURE_NAMES));
    AddApiParam(Built, 'selection', apTexts, True, rsEditorFeatureSelection);
    AddApiParam(Built, 'values', apList, True, rsEditorFeatureValues);
    AddApiParam(Built, 'values[].id', apText, True, rsEditorFeatureValueId);
    AddApiParam(Built, 'values[].text', apText, True, rsEditorFeatureValueText);
    AddApiMethod(Built, 'editor_note_preview', rsEditorNotePreview, rsEditorNotePreviewReturns, True);
    AddApiParam(Built, 'id', apTarget, True, rsEditorNotePreviewTarget);
    AddApiParam(Built, 'text', apText, True, rsEditorNotePreviewText);
    AddApiParam(Built, 'fileName', apText, False, rsEditorFileName);
    AddApiMethod(Built, 'editor_suggest_preview', rsEditorSuggestPreview, rsEditorSuggestPreviewReturns, True);
    AddApiParam(Built, 'id', apTarget, True, rsEditorSuggestTarget);
    AddApiParam(Built, 'field', apText, True, rsEditorField);
    AddApiParam(Built, 'text', apText, True, rsEditorSuggestText);
    AddApiParam(Built, 'value', apNumber, True, rsEditorSuggestItemValue);
    AddApiMethod(Built, 'editor_tables', rsEditorTables, rsEditorTablesReturns, True);
    AddApiMethod(Built, 'editor_changes', rsEditorChanges, rsEditorChangesReturns, True);
    AddApiMethod(Built, 'editor_snapshot', rsEditorSnapshot, rsEditorSnapshotReturns, True);
    AddApiMethod(Built, 'editor_save_complete', rsEditorSaveComplete, rsEditorSaveCompleteReturns);
    AddApiParam(Built, 'revision', apNumber, True, rsEditorSaveCompleteRevision);
    AddApiMethod(Built, 'editor_mark_unsaved', rsEditorMarkUnsaved, rsEditorMarkUnsavedReturns);
    AddApiMethod(Built, 'editor_drag_begin', rsEditorDragBegin, rsEditorDragBeginReturns);
    AddApiParam(Built, 'id', apTarget, True, rsEditorDragTarget);
    AddApiParam(Built, 'field', apText, False, rsEditorDragField);
    AddApiParam(Built, 'handle', apText, False, rsEditorDragHandle);
    AddApiParam(Built, 'tip', apFlag, False, rsEditorDragTip);
    AddApiMethod(Built, 'editor_drag_to', rsEditorDragTo, rsEditorDragToReturns);
    AddApiParam(Built, 'x', apNumber, True, rsEditorDragX);
    AddApiParam(Built, 'y', apNumber, True, rsEditorDragY);
    AddApiParam(Built, 'radius', apNumber, False, rsEditorDragRadius);
    AddApiParam(Built, 'fileName', apText, False, rsEditorFileName);
    AddApiMethod(Built, 'editor_drag_end', rsEditorDragEnd, rsEditorDragEndReturns);
    AddApiMethod(Built, 'editor_drag_cancel', rsEditorDragCancel, rsEditorDragCancelReturns);
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

function TextsToJSON(const Texts: array of string): TJSONArray;
var
  Text: string;
begin
  Result := TJSONArray.Create;
  for Text in Texts do
    Result.Add(Text);
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

// Line segments as one flat list: x1, y1, x2, y2 for each
function SegmentsToJSON(const Segments: TLine2Array): TJSONArray;
var
  Segment: TLine2;
begin
  Result := TJSONArray.Create;
  for Segment in Segments do
  begin
    Result.Add(ReportFloat(Segment.P1.X));
    Result.Add(ReportFloat(Segment.P1.Y));
    Result.Add(ReportFloat(Segment.P2.X));
    Result.Add(ReportFloat(Segment.P2.Y));
  end;
end;

// A notch is drawn from where it is cut to its tip
function NotchSegments(Piece: TPieceObject): TLine2Array;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Piece.NotchMarks));
  for Index := 0 to High(Result) do
  begin
    Result[Index].P1 := Piece.NotchMarks[Index].Cut;
    Result[Index].P2 := Piece.NotchMarks[Index].Tip;
  end;
end;

// A marker's strokes at every place it shows
function MarkerSegments(DraftObject: TDraftObject): TLine2Array;
var
  Centre: TVec2;
begin
  Result := nil;
  for Centre in MarkerPositions(DraftObject) do
    Result := Concat(Result, DraftObject.MarkerStrokesAt(Centre));
end;

// Chevrons as one flat list: x, y and the angle it points, for each
function ChevronsToJSON(const Chevrons: TPieceChevronArray): TJSONArray;
var
  Chevron: TPieceChevron;
begin
  Result := TJSONArray.Create;
  for Chevron in Chevrons do
  begin
    Result.Add(ReportFloat(Chevron.Position.X));
    Result.Add(ReportFloat(Chevron.Position.Y));
    Result.Add(ReportFloat(Chevron.Angle));
  end;
end;

// A seam side's edges, each as a polyline
function SideLinesToJSON(Pattern: TPattern; const Side: TSeamSide; Tolerance: double): TJSONArray;
var
  Entry: TSeamEntry;
  Node: TEvalNode;
begin
  Result := TJSONArray.Create;
  for Entry in Side do
  begin
    Node := Pattern.FindNode(Entry.EdgeKey);
    if (Node is TEdgeObject) and Node.HasResult then
      Result.Add(LineToJSON(EdgePolyline(TEdgeObject(Node), Tolerance)));
  end;
end;

// A rectangle as [minX, minY, maxX, maxY]
function RectToJSON(const Rect: TRect2): TJSONArray;
begin
  Result := TJSONArray.Create([ReportFloat(Rect.MinX), ReportFloat(Rect.MinY), ReportFloat(Rect.MaxX), ReportFloat(Rect.MaxY)]);
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

// The fields notes show: the pattern's name from the call's file name, or the file it came from
function TEditorApiServer.FieldValuesFor(Params: TJSONObject): TFieldValues;
var
  FileName: string;
begin
  FileName := OptionalString(Params, 'fileName');
  if FileName = '' then
    FileName := Document.FileName;
  Result := PatternFieldValues(Document.Pattern, FileName);
end;

// A callout's leader from its frame to Tip; none for a plain note
function LeaderToTip(Note: TNoteObject; const Frame: TRect2; const Tip: TVec2): TLine2Array;
var
  Start: TVec2;
begin
  Result := nil;
  if (Note.Leader <> nlNone) and LeaderStart(Frame, Tip, Start) then
    Result := LeaderStrokes(Start, Tip, Note.Leader);
end;

// A stamp's paths where it is drawn, in mm, for a canvas's Path2D
function StampToSceneJSON(Note: TNoteObject): TJSONArray;
var
  Path: TStampPath;
begin
  Result := TJSONArray.Create;
  try
    for Path in Note.Drawing.Paths do
      Result.Add(TJSONObject.Create(['d', StampPathData(Path, Note.Position, Note.Scale), 'fill', StampColourText(Path.Fill), 'stroke',
        StampColourText(Path.Stroke), 'strokeWidth', ReportFloat(Path.StrokeWidth * Note.Scale), 'evenOdd', Path.EvenOdd]));
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// A note as the canvas draws it: its text (Shown, as the note shows it or
// as typed) with fields filled in, line by line, its look, where its text
// and frame are, and its leader
function NoteToSceneJSON(Pattern: TPattern; Note: TNoteObject; const PatternValues: TFieldValues;
  const Shown: string): TJSONObject;
var
  Values: TFieldValues;
  Lines: TJSONArray;
  Line: string;
  Frame: TRect2;
begin
  Values := NoteFieldValues(Pattern, Note, PatternValues, Shown);
  Frame := NoteFrame(Note, Values, Shown);
  Result := SceneObject(Pattern, Note);
  Result.Add('print', Note.Print);
  Lines := TJSONArray.Create;
  for Line in TextLines(ExpandFields(Shown, Values)) do
    Lines.Add(Line);
  Result.Add('lines', Lines);
  Result.Add('size', ReportFloat(Note.Size));
  Result.Add('lineHeight', ReportFloat(LineHeight(Note.Size)));
  Result.Add('align', TEXT_ALIGN_NAMES[Note.Align]);
  Result.Add('boxed', Note.Boxed);
  Result.Add('font', Note.Style.Font);
  Result.Add('bold', Note.Style.Bold);
  Result.Add('italic', Note.Style.Italic);
  Result.Add('box', RectToJSON(NoteBox(Note, Values, Shown)));
  Result.Add('frame', RectToJSON(Frame));
  Result.Add('anchor', NOTE_ANCHOR_NAMES[Note.Anchor]);
  Result.Add('anchorAt', LineToJSON([Note.AnchorPosition]));
  Result.Add('leader', NOTE_LEADER_NAMES[Note.Leader]);
  Result.Add('leaderStrokes', SegmentsToJSON(LeaderToTip(Note, Frame, Note.AnchorPosition)));
  if Note.IsStamp then
    Result.Add('stamp', StampToSceneJSON(Note));
end;

function NoteLeaderStrokes(Pattern: TPattern; Note: TNoteObject; const PatternValues: TFieldValues; const Tip: TVec2): TLine2Array;
var
  Values: TFieldValues;
  Shown: string;
begin
  Shown := Note.ShownText;
  Values := NoteFieldValues(Pattern, Note, PatternValues, Shown);
  Result := LeaderToTip(Note, NoteFrame(Note, Values, Shown), Tip);
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
  Index: integer;
  Seam: TSeamObject;
  Values: TFieldValues;
begin
  Pattern := Document.Pattern;
  Values := FieldValuesFor(Params);
  Tolerance := DEFAULT_TOLERANCE;
  OptionalNumber(Params, 'tolerance', Tolerance);
  if Tolerance < MIN_TOLERANCE then
    Tolerance := MIN_TOLERANCE;
  Scene := TJSONObject.Create;
  try
    Scene.Add('unit', MEASURE_UNIT_NAMES[Pattern.Units]);
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
        Item.Add('marks', SegmentsToJSON(Concat(Piece.GrainArrow, Piece.FoldArrow, Piece.MarkingStrokes)));
        Item.Add('notches', SegmentsToJSON(NotchSegments(Piece)));
        Item.Add('caption', Pattern.PieceCaption(Piece));
        Item.Add('middle', LineToJSON([PieceMiddle(Piece)]));
        Item.Add('chevrons', ChevronsToJSON(PieceChevrons(Pattern, Piece)));
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
    Scene.Add('notes', List);
    if not Pattern.View.HideAnnotations then
      for Index := 0 to Pattern.ObjectCount - 1 do
        if (Pattern.Objects[Index] is TNoteObject) and Pattern.Objects[Index].HasResult and not Pattern.IsHidden(Pattern.Objects[Index]) then
          List.Add(NoteToSceneJSON(Pattern, TNoteObject(Pattern.Objects[Index]), Values,
            TNoteObject(Pattern.Objects[Index]).ShownText));

    // Drawn while selected, each side in its colour with its direction
    List := TJSONArray.Create;
    Scene.Add('seams', List);
    for Index := 0 to Pattern.ObjectCount - 1 do
      if (Pattern.Objects[Index] is TSeamObject) and Pattern.Objects[Index].HasResult then
      begin
        Seam := TSeamObject(Pattern.Objects[Index]);
        Item := SceneObject(Pattern, Seam);
        Item.Add('sideA', SideLinesToJSON(Pattern, Seam.SideA, Tolerance));
        Item.Add('sideB', SideLinesToJSON(Pattern, Seam.SideB, Tolerance));
        Item.Add('chevronsA', ChevronsToJSON(SeamChevrons(Pattern, Seam, False)));
        Item.Add('chevronsB', ChevronsToJSON(SeamChevrons(Pattern, Seam, True)));
        List.Add(Item);
      end;

    // A marker shows at its point whether or not it is on a piece yet
    List := TJSONArray.Create;
    Scene.Add('markers', List);
    for DraftObject in ShownObjects(Pattern) do
      if (DraftObject.Marker <> pmPlain) and DraftObject.HasResult and (DraftObject.MarkerSize > 0) then
      begin
        Item := SceneObject(Pattern, DraftObject);
        Item.Add('strokes', SegmentsToJSON(MarkerSegments(DraftObject)));
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
  PointRadius, EdgeRadius, NoteMargin: double;
  Handle: TCurveHandle;
  Answer: TJSONObject;
  Selection: TStringArray;
  TipKey: string;
begin
  At := Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y'));
  PointRadius := RequireNumber(Params, 'pointRadius');
  EdgeRadius := RequireNumber(Params, 'edgeRadius');
  NoteMargin := 0;
  OptionalNumber(Params, 'noteMargin', NoteMargin);
  // A note lies over whatever is under it
  Answer := TJSONObject.Create(['objects', KeysToJSON(Concat(NotesAt(Document.Pattern, At, FieldValuesFor(Params), NoteMargin),
    ObjectsAt(Document.Pattern, At, PointRadius, EdgeRadius)))]);
  // A selected callout's tip or curve's handle lies over everything
  if Assigned(Params.Find('selection')) then
  begin
    Selection := KeysParam(Params, 'selection');
    TipKey := CalloutTipAt(Document.Pattern, Selection, At, PointRadius);
    if TipKey <> '' then
      Answer.Add('tip', KeyToJSON(TipKey))
    else
      Answer.Add('tip', TJSONNull.Create);
    if HandleAt(Document.Pattern, Selection, At, PointRadius, Handle) then
      Answer.Add('handle', TJSONObject.Create(['edge', KeyToJSON(Handle.EdgeKey), 'field', Handle.LengthField]))
    else
      Answer.Add('handle', TJSONNull.Create);
  end;
  Result := Answer;
end;

function TEditorApiServer.DoVariableAdd: TJSONData;
var
  Key, Reason: string;
begin
  if not AddVariableStep(Document, Key, Reason) then
    raise EApiError.Create(RPC_REFUSED, Reason);
  Result := TJSONObject.Create(['id', KeyToJSON(Key)]);
end;

function TEditorApiServer.DoVariableDelete(Params: TJSONObject): TJSONData;
var
  Reason: string;
begin
  if not DeleteVariableStep(Document, FindTarget(Params).Key, Reason) then
    raise EApiError.Create(RPC_REFUSED, Reason);
  Result := TJSONObject.Create(['done', True]);
end;

// A refused value is an answer, not an error: the cell keeps it, in red, with the reason
function TEditorApiServer.DoVariableSet(Params: TJSONObject): TJSONData;
var
  Column: TVariableColumn;
  Reason: string;
  ErrorPos: integer;
  Done: boolean;
begin
  Column := VARIABLE_COLUMNS[ChoiceParam(Params, 'column', VARIABLE_COLUMN_NAMES)];
  Done := CommitVariableCell(Document, FindTarget(Params).Key, Column, RequireString(Params, 'text'), Reason, ErrorPos);
  Result := TJSONObject.Create(['done', Done, 'reason', Reason, 'errorPos', ErrorPos]);
end;

function TEditorApiServer.DoBounds(Params: TJSONObject): TJSONData;
var
  Bounds: TRect2;
begin
  if ObjectsBounds(Document.Pattern, KeysParam(Params, 'ids'), Bounds) then
    Result := TJSONObject.Create(['bounds', RectToJSON(Bounds)])
  else
    Result := TJSONObject.Create(['bounds', TJSONNull.Create]);
end;

// A list of text, as row keys are given
function TextsParam(Params: TJSONObject; const AName: string): TStringArray;
var
  List: TJSONData;
  Index: integer;
begin
  Result := nil;
  List := Params.Find(AName);
  if not Assigned(List) or (List.JSONType <> jtArray) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
  SetLength(Result, List.Count);
  for Index := 0 to List.Count - 1 do
    if List.Items[Index].JSONType in [jtString, jtNumber] then
      Result[Index] := List.Items[Index].AsString
    else
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
end;

function DoListClick(Params: TJSONObject): TJSONData;
var
  Clicked: string;
begin
  Clicked := OptionalString(Params, 'clicked');
  if Clicked = '' then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['clicked']));
  // Object IDs go back as numbers, measurement keys as text
  Result := TJSONObject.Create(['selection', KeysToJSON(SelectionAfterClick(TextsParam(Params, 'visible'),
    TextsParam(Params, 'selected'), OptionalString(Params, 'anchor'), Clicked, BooleanParam(Params, 'toggle'),
    BooleanParam(Params, 'extend')))]);
end;

const
  // As TPropertyRowKind
  PROPERTY_ROW_KIND_NAMES: array[TPropertyRowKind] of string = ('text', 'name', 'formula', 'choice', 'check', 'button',
    'problem', 'number', 'longText', 'font', 'color');

function PropertyRowToJSON(Pattern: TPattern; Node: TEvalNode; const Row: TPropertyRow): TJSONObject;
var
  Choices: TJSONArray;
  Choice: string;
begin
  Result := TJSONObject.Create(['id', Row.Id, 'kind', PROPERTY_ROW_KIND_NAMES[Row.Kind], 'caption', Row.Caption,
    'text', Row.Text]);
  case Row.Kind of
    prkFormula:
    begin
      Result.Add('field', Row.Field);
      // The suggestions button shows
      if CanSuggest(Pattern, Node, Row.Field) then
        Result.Add('suggest', True);
    end;
    prkChoice:
      Result.Add('choice', Row.Choice);
    prkCheck:
      Result.Add('checked', Row.Checked);
    prkNumber:
    begin
      Result.Add('value', ReportFloat(Row.Value));
      Result.Add('min', ReportFloat(Row.MinValue));
      Result.Add('max', ReportFloat(Row.MaxValue));
      Result.Add('step', ReportFloat(Row.Step));
      Result.Add('decimals', Row.Decimals);
    end;
    prkColor:
      Result.Add('color', Row.Color);
  end;
  if Row.Kind in [prkChoice, prkFont, prkColor] then
  begin
    Choices := TJSONArray.Create;
    for Choice in Row.Choices do
      Choices.Add(Choice);
    Result.Add('choices', Choices);
  end;
  if not Row.Enabled then
    Result.Add('enabled', False);
  if Row.Hint <> '' then
    Result.Add('hint', Row.Hint);
end;

function TEditorApiServer.DoProperties(Params: TJSONObject): TJSONData;
var
  Keys: TStringArray;
  Node: TEvalNode;
  Rows: TJSONArray;
  Row: TPropertyRow;
  Answer: TJSONObject;
begin
  // Keys as the canvas holds them, so a repeat's point not yet used is shown too
  Keys := TextsParam(Params, 'selection');
  Node := nil;
  if Length(Keys) = 1 then
  begin
    Node := Document.Pattern.FindNode(Keys[0]);
    if not Assigned(Node) then
      Node := Document.Pattern.FindObject(Keys[0]);
    if Assigned(Node) then
      Node := Document.Pattern.FindNode(PropertyKey(Document.Pattern, Node.Key));
  end;
  Answer := TJSONObject.Create;
  Rows := TJSONArray.Create;
  if Assigned(Node) then
  begin
    Answer.Add('id', KeyToJSON(Node.Key));
    Answer.Add('title', '');
    Answer.Add('locked', Document.Pattern.IsLocked(Node));
    for Row in PropertyRows(Document.Pattern, Node) do
      Rows.Add(PropertyRowToJSON(Document.Pattern, Node, Row));
  end
  else
  begin
    Answer.Add('id', TJSONNull.Create);
    if Length(Keys) > 1 then
      Answer.Add('title', Format(rsPropMany, [Length(Keys)]))
    else
      Answer.Add('title', rsPropNothing);
    Answer.Add('locked', False);
  end;
  Answer.Add('rows', Rows);
  Result := Answer;
end;

// A refused value is an answer, not an error: the field keeps it, with the reason
function TEditorApiServer.DoPropertySet(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  Row, Field, Reason: string;
  ErrorPos: integer;
  Done: boolean;
begin
  Node := FindTarget(Params);
  Row := OptionalString(Params, 'row');
  Field := OptionalString(Params, 'field');
  ErrorPos := 0;
  if Field <> '' then
    Done := CommitPropertyField(Document, Node, Field, RequireString(Params, 'text'), Reason, ErrorPos)
  else if Row = PROPERTY_ROW_NAME then
    Done := CommitPropertyField(Document, Node, '', RequireString(Params, 'text'), Reason, ErrorPos)
  else if Row = '' then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['row']))
  else if Assigned(Params.Find('text')) then
    Done := CommitPropertyText(Document, Node, Row, RequireString(Params, 'text'), Reason)
  else if Assigned(Params.Find('number')) then
    Done := CommitPropertyNumber(Document, Node, Row, RequireNumber(Params, 'number'), Reason)
  else if (Row = PROPERTY_ROW_GRAIN) and Assigned(Params.Find('from')) then
    Done := CommitGrainPoints(Document, Node, RequireWhole(Params, 'from'), RequireWhole(Params, 'to'), Reason)
  else if (Row = PROPERTY_ROW_FLIP) or (Row = PROPERTY_ROW_NOTE_FREE) then
    Done := CommitPropertyRow(Document, Node, Row, 0, Reason)
  else
    Done := CommitPropertyRow(Document, Node, Row, RequireWhole(Params, 'value'), Reason);
  Result := TJSONObject.Create(['done', Done, 'reason', Reason, 'errorPos', ErrorPos]);
end;

function TEditorApiServer.DoHandles(Params: TJSONObject): TJSONData;
var
  Handles: TJSONArray;
  Handle: TCurveHandle;
  Reason: string;
begin
  Handles := TJSONArray.Create;
  for Handle in SelectionHandles(Document.Pattern, KeysParam(Params, 'selection')) do
    Handles.Add(TJSONObject.Create(['edge', KeyToJSON(Handle.EdgeKey), 'field', Handle.LengthField, 'anchorX',
      ReportFloat(Handle.Anchor.X), 'anchorY', ReportFloat(Handle.Anchor.Y), 'x', ReportFloat(Handle.Position.X), 'y',
      ReportFloat(Handle.Position.Y), 'draggable', CanDragHandle(TEdgeObject(Document.Pattern.FindNode(Handle.EdgeKey)),
      Handle, Reason)]));
  Result := TJSONObject.Create(['handles', Handles]);
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

// The place a tool's call gives, as a group of x, y and radius
function TEditorApiServer.SnapOf(Group: TJSONObject; const AnchorKey: string): TSnap;
begin
  Result := FindSnap(Document.Pattern, Vec2(RequireNumber(Group, 'x'), RequireNumber(Group, 'y')), RequireNumber(Group, 'radius'),
    AnchorKey);
end;

// The place itself, as a group of x and y gives it
function PlaceOf(Group: TJSONObject): TVec2;
begin
  Result := Vec2(RequireNumber(Group, 'x'), RequireNumber(Group, 'y'));
end;

// The call's start group, or nil when it has none
function StartGroup(Params: TJSONObject): TJSONObject;
var
  Data: TJSONData;
begin
  Data := Params.Find('start');
  if not Assigned(Data) or (Data.JSONType = jtNull) then
    Exit(nil);
  if Data.JSONType <> jtObject then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['start']));
  Result := TJSONObject(Data);
end;

function SnapToJSON(const Snap: TSnap): TJSONObject;
begin
  Result := TJSONObject.Create(['kind', SNAP_KIND_NAMES[Snap.Kind], 'x', ReportFloat(Snap.Position.X), 'y',
    ReportFloat(Snap.Position.Y)]);
end;

// A line or curve lines up with its start once that is a point
function StartAnchor(const Start: TSnap): string;
begin
  Result := '';
  if Start.Kind = snPoint then
    Result := Start.PointKey;
end;

function TEditorApiServer.DoToolSnap(Params: TJSONObject): TJSONData;
var
  ToolName: string;
  Group: TJSONObject;
  Start, Snap: TSnap;
  Answer: TJSONObject;
  Description: string;
begin
  ToolName := SNAP_TOOL_NAMES[ChoiceParam(Params, 'tool', SNAP_TOOL_NAMES)];
  Group := StartGroup(Params);
  Start := Default(TSnap);
  if Assigned(Group) then
    Start := SnapOf(Group, '');
  if Assigned(Group) and ((ToolName = 'line') or (ToolName = 'curve')) then
    Snap := SnapOf(Params, StartAnchor(Start))
  else
    Snap := SnapOf(Params, '');
  if Assigned(Group) and ((ToolName = 'circle') or (ToolName = 'rectangle')) then
    Description := ShapeSizeText(Document.Pattern, Start.Position, Snap.Position, ToolName = 'circle')
  else if ToolName = 'text' then
    Description := NoteSnapDescription(Document.Pattern, Snap, PlaceOf(Params))
  else if (ToolName = 'callout') and Assigned(Group) then
    Description := rsToolCalloutBox
  else if ToolName = 'callout' then
    Description := CalloutSnapDescription(Document.Pattern, Snap, PlaceOf(Params))
  else
    Description := SnapDescription(Document.Pattern, Snap);
  Answer := SnapToJSON(Snap);
  Answer.Add('description', Description);
  Answer.Add('objects', KeysToJSON(SnapObjectKeys(Snap)));
  if Assigned(Group) then
  begin
    Answer.Add('start', SnapToJSON(Start));
    Answer.Add('startObjects', KeysToJSON(SnapObjectKeys(Start)));
  end;
  Result := Answer;
end;

function EditToJSON(const Edit: TSelectionEdit): TJSONObject;
begin
  Result := TJSONObject.Create(['done', Edit.Done, 'message', Edit.Message]);
  if Edit.Reselect then
    Result.Add('select', KeysToJSON(Edit.Selection))
  else
    Result.Add('select', TJSONNull.Create);
end;

function TEditorApiServer.DoToolClick(Params: TJSONObject): TJSONData;
var
  ToolName, EndKey, CurveKey: string;
  Group: TJSONObject;
  Start, Snap: TSnap;
  Role: TEdgeRole;
  Edit: TSelectionEdit;
  Answer: TJSONObject;
  EndPoint: TPointObject;
begin
  ToolName := CLICK_TOOL_NAMES[ChoiceParam(Params, 'tool', CLICK_TOOL_NAMES)];
  Role := erOutline;
  if Assigned(Params.Find('role')) then
    Role := TEdgeRole(ChoiceParam(Params, 'role', EDGE_ROLE_NAMES));
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  Group := StartGroup(Params);
  Start := Default(TSnap);
  if Assigned(Group) then
    Start := SnapOf(Group, '');
  EndKey := '';
  // The first click of a two-click tool is kept by the editor; nothing changes yet
  if not Assigned(Group) and (ToolName <> 'point') and (ToolName <> 'piece') and (ToolName <> 'notch') and (ToolName <> 'text') then
  begin
    Answer := EditToJSON(Default(TSelectionEdit));
    // A callout's tip must be on something
    if ToolName = 'callout' then
    begin
      Answer.Strings['message'] := CalloutStartRefusal(Document.Pattern, SnapOf(Params, ''), PlaceOf(Params));
      Answer.Add('started', Answer.Strings['message'] = '');
      if Answer.Strings['message'] = '' then
        Answer.Strings['message'] := rsToolCalloutBox;
      Exit(Answer);
    end;
    Answer.Add('started', True);
    if ToolName = 'circle' then
      Answer.Strings['message'] := rsToolCircleRim
    else if ToolName = 'rectangle' then
      Answer.Strings['message'] := rsToolRectangleCorner;
    Exit(Answer);
  end;
  case ToolName of
    'point': Edit := AddPointFromSnap(Document, SnapOf(Params, ''));
    'line', 'curve':
    begin
      Snap := SnapOf(Params, StartAnchor(Start));
      if (ToolName = 'curve') and Assigned(Params.Find('extend')) then
        Edit := ExtendCurveToSnap(Document, Reference(Params, 'extend', False), Start, Snap, Role, EndKey)
      else
        Edit := AddEdgeFromSnaps(Document, Start, Snap, ToolName = 'curve', Role, EndKey);
    end;
    'circle', 'rectangle': Edit := AddShapeFromSnap(Document, Start, SnapOf(Params, '').Position, ToolName = 'circle', Role);
    'piece': Edit := AddPieceAt(Document, Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y')));
    'notch': Edit := ToggleNotchAt(Document, Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y')),
        RequireNumber(Params, 'radius'));
    'text': Edit := AddNoteFromSnap(Document, SnapOf(Params, ''), PlaceOf(Params));
    'callout': Edit := AddCalloutFromSnap(Document, Start, PlaceOf(Group), PlaceOf(Params));
  end;
  Answer := EditToJSON(Edit);
  Answer.Add('started', False);
  if Edit.Done and (EndKey <> '') then
  begin
    EndPoint := TPointObject(Document.Pattern.FindNode(EndKey));
    Answer.Add('end', TJSONObject.Create(['x', ReportFloat(EndPoint.Position.X), 'y', ReportFloat(EndPoint.Position.Y)]));
    if ToolName = 'curve' then
    begin
      CurveKey := Edit.Selection[0];
      Answer.Add('curve', KeyToJSON(CurveKey));
    end;
  end;
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

function TEditorApiServer.Pending: TPendingMeasurements;
begin
  if not Assigned(FPending) then
    FPending := TPendingMeasurements.Create;
  if Document.MeasurementPath <> FPendingPath then
  begin
    FPending.Clear;
    FPendingPath := Document.MeasurementPath;
  end;
  Result := FPending;
end;

// The values shown while trying sizes are scaled, so none is edited then
procedure TEditorApiServer.CheckNotTesting;
begin
  // Exactly 1 is no test, so this is not a tolerance compare
  if Document.MeasurementScale <> 1 then
    raise EApiError.Create(RPC_REFUSED, rsPanelTestingSizes);
end;

procedure TEditorApiServer.CheckNothingPending;
begin
  if Pending.Count > 0 then
    raise EApiError.Create(RPC_REFUSED, rsEditorPendingMeasurements);
end;

function TEditorApiServer.DoListMeasurements(Params: TJSONObject): TJSONData;
var
  Row: TMeasurementPanelRow;
  Rows, Sizes: TJSONArray;
  Size: string;
  Index: integer;
begin
  CheckMeasurementsShared;
  Rows := TJSONArray.Create;
  for Row in Pending.Rows(Document.Pattern, Document.Measurements, OptionalString(Params, 'search')) do
    Rows.Add(TJSONObject.Create(['key', Row.Key, 'value', Row.Value, 'description', Row.Description, 'missing', Row.Missing,
      'pending', Row.Pending, 'isNew', Row.IsNew]));
  Sizes := TJSONArray.Create;
  Size := '';
  if Assigned(Document.Measurements) then
  begin
    for Index := 0 to Document.Measurements.SizeCount - 1 do
      Sizes.Add(Document.Measurements.Sizes[Index]);
    Size := Document.Measurements.SizeName;
  end;
  Result := TJSONObject.Create(['rows', Rows, 'file', Document.Pattern.MeasurementFile, 'sizes', Sizes, 'size', Size,
    'testPercent', Round((Document.MeasurementScale - 1) * 100), 'pendingCount', Pending.Count]);
end;

function TEditorApiServer.DoMeasurementAdd: TJSONData;
begin
  CheckMeasurementsShared;
  CheckNotTesting;
  Result := TJSONObject.Create(['key', Pending.AddNew(Document.Measurements)]);
end;

// A refused value is an answer, not an error: the cell keeps it, in red, with the reason
function TEditorApiServer.DoMeasurementSet(Params: TJSONObject): TJSONData;
var
  Key, NewKey, Reason: string;
  Done: boolean;
begin
  CheckMeasurementsShared;
  CheckNotTesting;
  Key := RequireString(Params, 'key');
  Done := Pending.CommitCell(Document.Measurements, Key, TMeasurementColumn(ChoiceParam(Params, 'column',
    MEASUREMENT_COLUMN_NAMES)), RequireString(Params, 'text'), NewKey, Reason);
  Result := TJSONObject.Create(['done', Done, 'reason', Reason, 'key', NewKey]);
end;

function TEditorApiServer.DoMeasurementsSave(Params: TJSONObject): TJSONData;
var
  Changes: TMeasurementChangeArray;
  Reason, NewFile: string;
  Empty: TMeasurementSet;
begin
  CheckMeasurementsShared;
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  if (Pending.Count > 0) and (Document.MeasurementPath = '') then
  begin
    NewFile := OptionalString(Params, 'file');
    if NewFile = '' then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsEditorNewMeasurementsFile);
    Empty := TMeasurementSet.Create;
    try
      if not Document.UseMeasurementsText(Empty.SaveToText, NewFile, Reason) then
        raise EApiError.Create(RPC_REFUSED, Reason);
    finally
      FreeAndNil(Empty);
    end;
    // The new set is the one the edits are for
    FPendingPath := Document.MeasurementPath;
  end;
  if Pending.Count = 0 then
    Exit(TJSONObject.Create(['done', True, 'reason', '', 'text', Document.MeasurementText, 'file',
      Document.Pattern.MeasurementFile, 'message', '']));
  if not Pending.Save(Document, Changes, Reason) then
    Exit(TJSONObject.Create(['done', False, 'reason', Reason]));
  Result := TJSONObject.Create(['done', True, 'reason', '', 'text', Document.MeasurementText, 'file',
    Document.Pattern.MeasurementFile, 'message', MeasurementsSavedText(Changes, Document.Pattern.MeasurementFile)]);
end;

function TEditorApiServer.DoMeasurementsRevert: TJSONData;
begin
  Pending.Clear;
  Result := TJSONObject.Create(['done', True]);
end;

function TEditorApiServer.DoMeasurementSize(Params: TJSONObject): TJSONData;
var
  Size: string;
begin
  CheckMeasurementsShared;
  CheckNothingPending;
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  Size := RequireString(Params, 'size');
  if not Document.SelectMeasurementSize(Size) then
    raise EApiError.Create(RPC_REFUSED, Format(rsMeasurementUnknownSize, [Size]));
  Result := TJSONObject.Create(['size', Document.Measurements.SizeName]);
end;

function TEditorApiServer.DoMeasurementScale(Params: TJSONObject): TJSONData;
var
  Percent: integer;
begin
  CheckMeasurementsShared;
  CheckNothingPending;
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  Percent := Max(-MAX_TEST_PERCENT, Min(MAX_TEST_PERCENT, RequireWhole(Params, 'percent')));
  Document.SetMeasurementScale(1 + Percent / 100);
  Result := TJSONObject.Create(['testPercent', Percent]);
end;

function SuggestionToJSON(const Suggestion: TSuggestion; Kind: TSuggestionKind; Pattern: TPattern;
  Grade: TGradeCheck): TJSONObject;
var
  Values: TSizeValues;
begin
  Result := TJSONObject.Create(['text', Suggestion.Text, 'value', ReportFloat(Suggestion.Value), 'valueText',
    SuggestionValueText(Suggestion.Value, Kind, Pattern.Units), 'delta', ReportFloat(Suggestion.Delta), 'deltaText',
    SuggestionDeltaText(Suggestion.Delta, Kind, Pattern.Units), 'objects', KeysToJSON(SuggestionObjectKeys(Pattern, [Suggestion.Text]))]);
  if not Assigned(Grade) then
    Exit;
  Values := Grade.Values(Suggestion.Text);
  Result.Add('range', SizeRangeText(Values, Kind, Pattern.Units));
  Result.Add('sizeValues', SizeValuesText(Grade, Values, Kind, Pattern.Units));
end;

function TEditorApiServer.GradeFor(Node: TEvalNode; const FieldName: string): TGradeCheck;
begin
  if Assigned(FGrade) and ((FGradeKey <> Node.Key) or (FGradeField <> FieldName)) then
    FreeAndNil(FGrade);
  // Never made during a drag, as it copies the pattern for each size
  if not Assigned(FGrade) and Document.ChangeOpen then
    Exit(nil);
  if not Assigned(FGrade) then
  begin
    FGrade := TGradeCheck.Create(Document.Pattern, Node, FieldName);
    FGradeKey := Node.Key;
    FGradeField := FieldName;
  end;
  Result := FGrade;
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
  Items, Sizes: TJSONArray;
  Answer: TJSONObject;
  Grade: TGradeCheck;
begin
  Pattern := Document.Pattern;
  Node := FindTarget(Params);
  FieldName := RequireString(Params, 'field');
  if not CanSuggest(Pattern, Node, FieldName) then
    raise EApiError.Create(RPC_REFUSED, Format(rsEditorCannotSuggest, [FieldName, Node.DisplayName]));
  if not OptionalNumber(Params, 'value', Target) then
    SuggestionTarget(Pattern, Node, FieldName, Target);
  Grade := GradeFor(Node, FieldName);
  Source := TSuggestionSource.Create(Pattern, Node, FieldName);
  try
    Found := Source.Match(Target);
    Answer := TJSONObject.Create;
    Answer.Add('kind', SUGGESTION_KIND_NAMES[Source.Kind]);
    Answer.Add('tolerance', SuggestionToleranceText(Source.Kind, Pattern.Units));
    // During a drag the grade check of before it serves, or none
    if Assigned(Grade) and Grade.Available then
    begin
      Sizes := TJSONArray.Create([Grade.Sizes[0], Grade.Sizes[Grade.SizeCount - 1]]);
      Answer.Add('sizes', Sizes);
    end
    else
      Grade := nil;
    Items := TJSONArray.Create;
    Answer.Add('items', Items);
    for Suggestion in Found.Items do
      Items.Add(SuggestionToJSON(Suggestion, Source.Kind, Pattern, Grade));
    if Found.HasNearest then
      Answer.Add('nearest', SuggestionToJSON(Found.Nearest, Source.Kind, Pattern, Grade))
    else
      Answer.Add('nearest', TJSONNull.Create);
    Result := Answer;
  finally
    FreeAndNil(Source);
  end;
end;

function GhostToJSON(const Ghost: TGradeGhost): TJSONObject;
var
  Lines: TJSONArray;
  Line: TVec2Array;
begin
  Lines := TJSONArray.Create;
  for Line in Ghost.Lines do
    Lines.Add(LineToJSON(Line));
  Result := TJSONObject.Create(['lines', Lines]);
  if Ghost.HasPoint then
    Result.Add('point', TJSONArray.Create([ReportFloat(Ghost.Point.X), ReportFloat(Ghost.Point.Y)]))
  else
    Result.Add('point', TJSONNull.Create);
end;

// As the desktop's suggestion list does when a row is hovered
function TEditorApiServer.DoSuggestPreview(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  Node: TEvalNode;
  FieldName, FormulaText: string;
  Position: TVec2;
  Grade: TGradeCheck;
  Ghosts: TJSONArray;
  Ghost: TGradeGhost;
  Answer: TJSONObject;
begin
  Pattern := Document.Pattern;
  Node := FindTarget(Params);
  FieldName := RequireString(Params, 'field');
  FormulaText := RequireString(Params, 'text');
  if not CanSuggest(Pattern, Node, FieldName) then
    raise EApiError.Create(RPC_REFUSED, Format(rsEditorCannotSuggest, [FieldName, Node.DisplayName]));
  Answer := TJSONObject.Create;
  if (Node is TPointObject) and FieldPosition(Pattern, TPointObject(Node), FieldName, RequireNumber(Params, 'value'),
    Position) then
    Answer.Add('position', TJSONObject.Create(['x', ReportFloat(Position.X), 'y', ReportFloat(Position.Y)]))
  else
    Answer.Add('position', TJSONNull.Create);
  Ghosts := TJSONArray.Create;
  Answer.Add('ghosts', Ghosts);
  Grade := GradeFor(Node, FieldName);
  if Assigned(Grade) then
    for Ghost in Grade.Ghosts(FormulaText) do
      Ghosts.Add(GhostToJSON(Ghost));
  Result := Answer;
end;

function TEditorApiServer.DoExportDraft(Params: TJSONObject): TJSONData;
var
  Options: TDraftSVGOptions;
  FileName: string;
begin
  FileName := OptionalString(Params, 'fileName');
  if FileName = '' then
    FileName := Document.FileName;
  Options := DefaultDraftSVGOptions;
  Options.NoFills := BooleanParam(Params, 'noFills');
  Options.HiddenRoles := Document.Pattern.View.HiddenRoles;
  Options.HideAnnotations := Document.Pattern.View.HideAnnotations;
  Options.FollowPieceView := True;
  Options.PatternFileName := FileName;
  Options.LabelChosen := True;
  Options.LabelKeys := TextsParam(Params, 'labels');
  Result := TJSONObject.Create(['text', DraftToSVG(Document.Pattern, Options)]);
end;

const
  // A new layout's paper
  PRINT_PAPER = 'A4';

// The pattern as open, unsaved edits and all, through a layout that is never saved
function TEditorApiServer.DoPrint(Params: TJSONObject): TJSONData;
var
  Layout: TLayout;
  Source: TPatternSource;
  FileName, Paper, Size, Refusal, MeasurementText: string;
  Problem: TLayoutProblem;
  Warnings: TJSONArray;
begin
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  FileName := OptionalString(Params, 'fileName');
  if FileName = '' then
    FileName := ExtractFileName(Document.FileName);
  if FileName = '' then
    FileName := rsEditorPrintUnnamed;
  Paper := OptionalString(Params, 'paper');
  if Paper = '' then
    Paper := PRINT_PAPER;
  Size := '';
  MeasurementText := '';
  if Assigned(Document.Measurements) then
  begin
    MeasurementText := Document.MeasurementText;
    if Document.Measurements.SizeCount > 0 then
      Size := Document.Measurements.SizeName;
  end;
  Layout := TLayout.Create;
  try
    Layout.Name := ChangeFileExt(FileName, '');
    Source := Layout.AddSource(FileName, '', Size);
    Layout.LoadSourceText(Source, Document.SnapshotText, MeasurementText);
    if not PaperSize(Paper, Layout.Output.Tiles.PaperWidth, Layout.Output.Tiles.PaperHeight) then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadChoice, ['paper', 'A4, A3, Letter']));
    Layout.Output.Paper := Paper;
    Layout.PlaceNewPieces;
    Layout.UseDefaultTitle;
    Refusal := Layout.Refusal;
    if Refusal <> '' then
      Exit(TJSONObject.Create(['done', False, 'reason', Refusal]));
    Warnings := TJSONArray.Create;
    for Problem in Layout.Problems do
      if not Problem.Blocking then
        Warnings.Add(Problem.Text);
    Result := TJSONObject.Create(['done', True, 'pdf', EncodeStringBase64(LayoutToPDF(Layout)), 'warnings', Warnings]);
  finally
    FreeAndNil(Layout);
  end;
end;

function TEditorApiServer.DoMaterials: TJSONData;
var
  Pattern: TPattern;
  Rows, Fills, Fabrics: TJSONArray;
  Row: TMaterialRow;
  Fill: TMaterialFill;
  Fabric: TFabric;
begin
  Pattern := Document.Pattern;
  Rows := TJSONArray.Create;
  for Row in MaterialRows(Pattern) do
    Rows.Add(TJSONObject.Create(['name', Row.Name, 'color', Row.Color, 'fill', MATERIAL_FILL_NAMES[Ord(Row.Fill)],
      'fillCaption', Row.FillCaption, 'allowance', Row.AllowanceText, 'size', Row.SizeText, 'hatchAngle',
      ReportFloat(Row.HatchAngle)]));
  Fills := TJSONArray.Create;
  for Fill in TMaterialFill do
    Fills.Add(TJSONObject.Create(['name', MATERIAL_FILL_NAMES[Ord(Fill)], 'caption', MaterialFillCaption(Fill)]));
  Fabrics := TJSONArray.Create;
  for Fabric in TFabric do
    Fabrics.Add(TJSONObject.Create(['name', FABRIC_NAMES[Ord(Fabric)], 'caption', FabricCaption(Fabric)]));
  Result := TJSONObject.Create(['rows', Rows, 'cutList', Pattern.CutList, 'unit', MEASURE_UNIT_NAMES[Pattern.Units],
    'fills', Fills, 'fabrics', Fabrics]);
end;

// The material by name, or -1 for all
function GarmentMaterialIndex(Pattern: TPattern; const AName: string): integer;
begin
  if AName <> '' then
    for Result := 0 to Pattern.MaterialCount - 1 do
      if Pattern.Materials[Result].Name = AName then
        Exit;
  Result := -1;
end;

function TEditorApiServer.GarmentScene(Params: TJSONObject): TGarmentScene;
begin
  if not Assigned(FGarment) then
    FGarment := TGarmentBuilder.Create;
  Result := FGarment.Build(Document.Pattern, True);
  Result := GarmentOfMaterial(Result, GarmentMaterialIndex(Document.Pattern, Params.Get('material', '')));
end;

function TEditorApiServer.DoGarment(Params: TJSONObject): TJSONData;
var
  Scene: TGarmentScene;
  Pieces, Materials: TJSONArray;
  Piece: TGarmentPiece;
  Bounds: TJSONData;
  Index: integer;
  Shown: string;
begin
  Scene := GarmentScene(Params);
  Pieces := TJSONArray.Create;
  for Piece in Scene.Pieces do
    Pieces.Add(TJSONObject.Create(['id', KeyToJSON(Piece.PieceKey), 'name', Piece.Name, 'outline', LineToJSON(Piece.Outline)]));
  if Length(Scene.Pieces) = 0 then
    Bounds := TJSONNull.Create
  else
    Bounds := TJSONObject.Create(['left', ReportFloat(Scene.Bounds.MinX), 'top', ReportFloat(Scene.Bounds.MinY), 'right',
      ReportFloat(Scene.Bounds.MaxX), 'bottom', ReportFloat(Scene.Bounds.MaxY)]);
  Materials := TJSONArray.Create;
  for Index := 0 to Document.Pattern.MaterialCount - 1 do
    Materials.Add(Document.Pattern.Materials[Index].Name);
  Index := GarmentMaterialIndex(Document.Pattern, Params.Get('material', ''));
  Shown := '';
  if Index >= 0 then
    Shown := Document.Pattern.Materials[Index].Name;
  Result := TJSONObject.Create(['svg', GarmentToSVG(Scene, DefaultGarmentLight), 'bounds', Bounds, 'pieces', Pieces,
    'notes', TextsToJSON(Scene.Notes), 'materials', Materials, 'material', Shown]);
end;

function TEditorApiServer.DoProblems: TJSONData;
var
  List: TJSONArray;
  Item: TJSONObject;
  Problem: TPatternProblem;
  Node: TEvalNode;
  BlockedCount: integer;
begin
  List := TJSONArray.Create;
  for Problem in PatternProblemList(Document.Pattern, BlockedCount) do
  begin
    Item := TJSONObject.Create(['text', Problem.Text]);
    Node := nil;
    if Problem.Key <> '' then
      Node := Document.Pattern.FindNode(Problem.Key);
    if Node is TMeasurementNode then
    begin
      Item.Add('kind', 'measurement');
      // Its key without the @ formulas put before it
      Item.Add('key', Copy(Node.Key, 2, Length(Node.Key) - 1));
    end
    else if Node is TVariable then
    begin
      Item.Add('kind', 'variable');
      Item.Add('id', KeyToJSON(Node.Key));
    end
    else if Assigned(Node) then
    begin
      Item.Add('kind', 'object');
      Item.Add('id', KeyToJSON(Node.Key));
    end
    else
      Item.Add('kind', 'none');
    List.Add(Item);
  end;
  Result := TJSONObject.Create(['problems', List, 'blocked', BlockedCount]);
end;

function TEditorApiServer.DoGarmentMarks(Params: TJSONObject): TJSONData;
var
  Scene: TGarmentScene;
  Marks: TGarmentMarks;
  Selected, Lines: TJSONArray;
  Piece: TGarmentPiece;
  Line: TVec2Array;
  Key: string;
begin
  Marks := GarmentSelectionMarks(Document.Pattern, KeysParam(Params, 'selection'));
  Scene := GarmentScene(Params);
  Selected := TJSONArray.Create;
  for Piece in Scene.Pieces do
    for Key in Marks.SelectedPieces do
      if Key = Piece.PieceKey then
        Selected.Add(KeyToJSON(Key));
  Lines := TJSONArray.Create;
  for Line in GarmentMarkedLines(Scene, Marks) do
    Lines.Add(LineToJSON(Line));
  Result := TJSONObject.Create(['pieces', Selected, 'lines', Lines]);
end;

// A drag holds the document's change open, and every other change waits for it
procedure RequireIdle(Document: TPatternDocument);
begin
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
end;

function MaterialIndexParam(Document: TPatternDocument; Params: TJSONObject): integer;
begin
  Result := RequireWhole(Params, 'index');
  if (Result < 0) or (Result >= Document.Pattern.MaterialCount) then
    raise EApiError.Create(RPC_REFUSED, rsPanelNoMaterial);
end;

function TEditorApiServer.DoMaterial(Params: TJSONObject): TJSONData;
var
  Index: integer;
  Field: TMaterialField;
  Answer: TJSONObject;
begin
  Index := MaterialIndexParam(Document, Params);
  Answer := TJSONObject.Create;
  for Field in TMaterialField do
    Answer.Add(MATERIAL_FIELD_NAMES[Field], MaterialFieldText(Document, Index, Field));
  Answer.Add('canDelete', Document.Pattern.MaterialCount > 1);
  Result := Answer;
end;

function TEditorApiServer.DoMaterialSet(Params: TJSONObject): TJSONData;
var
  Index, FieldIndex: integer;
  Reason: string;
  Answer: TJSONObject;
begin
  Index := MaterialIndexParam(Document, Params);
  FieldIndex := IndexStr(RequireString(Params, 'field'), MATERIAL_FIELD_NAMES);
  if FieldIndex < 0 then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadChoice, ['field', string.Join(', ',
      MATERIAL_FIELD_NAMES)]));
  RequireIdle(Document);
  Answer := TJSONObject.Create(['done', CommitMaterialField(Document, Index, TMaterialField(FieldIndex),
    RequireString(Params, 'text'), Reason)]);
  if Reason <> '' then
    Answer.Add('reason', Reason);
  Result := Answer;
end;

function TEditorApiServer.DoMaterialAdd: TJSONData;
begin
  RequireIdle(Document);
  Result := TJSONObject.Create(['index', AddMaterialStep(Document)]);
end;

function TEditorApiServer.DoMaterialDelete(Params: TJSONObject): TJSONData;
var
  Reason: string;
  Answer: TJSONObject;
begin
  RequireIdle(Document);
  Answer := TJSONObject.Create(['done', DeleteMaterialStep(Document, MaterialIndexParam(Document, Params), Reason)]);
  if Reason <> '' then
    Answer.Add('reason', Reason);
  Result := Answer;
end;

const
  FEATURE_FIELD_KIND_NAMES: array[TFeatureFieldKind] of string = ('text', 'choice', 'check', 'combo');

function FeatureParam(Params: TJSONObject): TFeatureKind;
begin
  if not FeatureKindOf(RequireString(Params, 'feature'), Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiBadChoice, ['feature', string.Join(', ', FEATURE_NAMES)]));
end;

// The fields' values as sent, or none when left out
function FeatureValuesParam(Params: TJSONObject): TFeatureValues;
var
  List: TJSONData;
  Item: TJSONData;
  Index: integer;
begin
  Result := nil;
  List := Params.Find('values');
  if not Assigned(List) then
    Exit;
  if List.JSONType <> jtArray then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['values']));
  for Index := 0 to List.Count - 1 do
  begin
    Item := List.Items[Index];
    if Item.JSONType <> jtObject then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['values[].id']));
    SetFeatureValue(Result, RequireString(TJSONObject(Item), 'id'), TJSONObject(Item).Get('text', ''));
  end;
end;

// The selection's keys, each given by ID or name
function SelectionKeys(Pattern: TPattern; Params: TJSONObject): TStringArray;
var
  Index: integer;
  Node: TObject;
begin
  Result := TextsParam(Params, 'selection');
  for Index := 0 to High(Result) do
    if not Assigned(Pattern.FindNode(Result[Index])) then
    begin
      Node := Pattern.FindObject(Result[Index]);
      if Node is TEvalNode then
        Result[Index] := TEvalNode(Node).Key;
    end;
end;

function FeatureValuesToJSON(const Values: TFeatureValues): TJSONArray;
var
  Value: TFeatureValue;
begin
  Result := TJSONArray.Create;
  for Value in Values do
    Result.Add(TJSONObject.Create(['id', Value.Id, 'text', Value.Text]));
end;

function TEditorApiServer.DoFeatures(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  Kind: TFeatureKind;
  Values: TFeatureValues;
  Form: TFeatureForm;
  Field: TFeatureField;
  Features, Fields, Choices: TJSONArray;
  Choice: string;
  Answer: TJSONObject;
begin
  Pattern := Document.Pattern;
  Kind := FeatureParam(Params);
  if Assigned(Params.Find('values')) then
    Values := FeatureValuesParam(Params)
  else
    Values := FeatureStartingValues(Pattern, Kind, nil);
  if OptionalString(Params, 'changed') <> '' then
    Values := FeatureValueChanged(Pattern, Kind, Values, OptionalString(Params, 'changed'),
      OptionalString(Params, 'previous'));
  Form := FeatureForm(Pattern, Kind, FeatureSelectionOf(Pattern, SelectionKeys(Pattern, Params)), Values);
  Features := TJSONArray.Create;
  for Kind in TFeatureKind do
    Features.Add(TJSONObject.Create(['name', FEATURE_NAMES[Kind], 'caption', FeatureCaption(Kind)]));
  Fields := TJSONArray.Create;
  for Field in Form.Fields do
  begin
    Choices := TJSONArray.Create;
    for Choice in Field.Choices do
      Choices.Add(Choice);
    Fields.Add(TJSONObject.Create(['id', Field.Id, 'kind', FEATURE_FIELD_KIND_NAMES[Field.Kind], 'caption', Field.Caption,
      'text', Field.Text, 'choices', Choices, 'enabled', Field.Enabled]));
  end;
  Answer := TJSONObject.Create(['features', Features, 'header', Form.Header, 'note', Form.Note, 'canApply',
    Form.CanApply, 'values', FeatureValuesToJSON(Values), 'fields', Fields]);
  Result := Answer;
end;

// A refusal is an answer, for the status bar, not an error
function TEditorApiServer.DoFeatureApply(Params: TJSONObject): TJSONData;
var
  Message: string;
  Done: boolean;
begin
  Done := ApplyFeature(Document, FeatureParam(Params), FeatureSelectionOf(Document.Pattern,
    SelectionKeys(Document.Pattern, Params)), FeatureValuesParam(Params), Message);
  Result := TJSONObject.Create(['done', Done, 'message', Message]);
end;

function TEditorApiServer.DoNotePreview(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
begin
  Node := FindTarget(Params);
  if not (Node is TNoteObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsEditorNotNote, [Node.DisplayName]));
  Result := TJSONObject.Create(['note', NoteToSceneJSON(Document.Pattern, TNoteObject(Node), FieldValuesFor(Params),
    NotePreviewText(Document.Pattern, RequireString(Params, 'text')))]);
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

procedure TEditorApiServer.AfterConstruction;
begin
  inherited AfterConstruction;
  Document.AddListener(@DocumentChanged);
end;

destructor TEditorApiServer.Destroy;
begin
  if Assigned(Document) then
    Document.RemoveListener(@DocumentChanged);
  FreeAndNil(FPending);
  FreeAndNil(FGrade);
  FreeAndNil(FGarment);
  inherited Destroy;
end;

procedure TEditorApiServer.DocumentChanged(ADocument: TPatternDocument; Changes: TDocumentChanges);
begin
  FChanges := FChanges + Changes;
  if Changes - [dcView] <> [] then
    Inc(FSaveRevision);
  // A drag changes only the field's own object, which no candidate reads
  if (Changes * [dcPattern, dcObjectsReplaced, dcMeasurements] <> []) and not ADocument.ChangeOpen then
    FreeAndNil(FGrade);
end;

function TEditorApiServer.DoChanges: TJSONData;
var
  Change: TDocumentChange;
  Names: TJSONArray;
begin
  Names := TJSONArray.Create;
  for Change in FChanges do
    Names.Add(DOCUMENT_CHANGE_NAMES[Change]);
  FChanges := [];
  Result := TJSONObject.Create(['changes', Names, 'generation', Document.Generation, 'canUndo', Document.CanUndo, 'canRedo',
    Document.CanRedo, 'undo', Document.UndoDescription, 'redo', Document.RedoDescription, 'modified', Document.Modified]);
end;

function TEditorApiServer.DoSnapshot: TJSONData;
var
  Answer: TJSONObject;
begin
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  Answer := TJSONObject.Create(['text', Document.SnapshotText, 'measurementsFile', Document.Pattern.MeasurementFile,
    'modified', Document.Modified, 'generation', Document.Generation, 'revision', FSaveRevision]);
  if Document.MeasurementsInMemory then
    Answer.Add('measurementsText', Document.MeasurementText)
  else
    Answer.Add('measurementsText', TJSONNull.Create);
  Result := Answer;
end;

function TEditorApiServer.DoSaveComplete(Params: TJSONObject): TJSONData;
begin
  if (RequireWhole(Params, 'revision') = FSaveRevision) and not Document.ChangeOpen then
    Document.MarkSaved;
  Result := TJSONObject.Create(['modified', Document.Modified]);
end;

function TEditorApiServer.DoMarkUnsaved: TJSONData;
begin
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsApiBusy);
  Document.MarkUnsaved;
  Result := TJSONObject.Create(['modified', Document.Modified]);
end;

// The handle of Edge named by its length field, which names one handle of
// a curve; False when it has none such, as before it is worked out
function FindHandle(Edge: TEdgeObject; const LengthField: string; out Handle: TCurveHandle): boolean;
var
  Candidate: TCurveHandle;
begin
  Handle := Default(TCurveHandle);
  for Candidate in CurveHandles(Edge) do
    if Candidate.LengthField = LengthField then
    begin
      Handle := Candidate;
      Exit(True);
    end;
  Result := False;
end;

function TEditorApiServer.DraggedHandle: TCurveHandle;
begin
  if not FindHandle(TEdgeObject(Document.Pattern.FindNode(FDragKey)), FDragHandle, Result) then
    raise EApiError.Create(RPC_REFUSED, Format(rsEditorNoHandle, [Document.Pattern.FindNode(FDragKey).DisplayName,
      FDragHandle]));
end;

function GuideToJSON(const Guide: TFieldGuide): TJSONData;
begin
  case Guide.Kind of
    fgLine:
      Result := TJSONObject.Create(['kind', 'line', 'x1', ReportFloat(Guide.Start.X), 'y1', ReportFloat(Guide.Start.Y),
        'x2', ReportFloat(Guide.Finish.X), 'y2', ReportFloat(Guide.Finish.Y)]);
    fgCircle:
      Result := TJSONObject.Create(['kind', 'circle', 'cx', ReportFloat(Guide.Centre.X), 'cy',
        ReportFloat(Guide.Centre.Y), 'radius', ReportFloat(Guide.Radius)]);
    else
      Result := TJSONNull.Create;
  end;
end;

function TEditorApiServer.DragPosition: TJSONObject;
var
  Node: TEvalNode;
  At: TVec2;
begin
  Node := Document.Pattern.FindNode(FDragKey);
  if FDragHandle <> '' then
    At := DraggedHandle.Position
  else if FDragTip then
    At := TNoteObject(Node).AnchorPosition
  else if Node is TNoteObject then
    At := TNoteObject(Node).Position
  else
    At := TPointObject(Node).Position;
  Result := TJSONObject.Create(['x', ReportFloat(At.X), 'y', ReportFloat(At.Y)]);
  if FDragField <> '' then
    Result.Add('guide', GuideToJSON(FieldGuide(Document.Pattern, TPointObject(Node), FDragField)))
  // A point with a formula field moves along its plain field only
  else if (FDragHandle = '') and not FDragTip and (Node is TPointObject) and (PartialDragField(TPointObject(Node)) <> '') then
    Result.Add('guide', GuideToJSON(FieldGuide(Document.Pattern, TPointObject(Node), PartialDragField(TPointObject(Node)))));
end;

procedure TEditorApiServer.RequireDrag;
begin
  if FDragKey = '' then
    raise EApiError.Create(RPC_REFUSED, rsEditorNoDrag);
end;

function TEditorApiServer.DoDragBegin(Params: TJSONObject): TJSONData;
var
  Node: TEvalNode;
  FieldName, HandleField, Reason: string;
  Handle: TCurveHandle;
  Allowed: boolean;
begin
  if FDragKey <> '' then
    raise EApiError.Create(RPC_REFUSED, rsEditorDragOpen);
  Node := FindTarget(Params);
  FieldName := OptionalString(Params, 'field');
  HandleField := OptionalString(Params, 'handle');
  // A tip changes nothing until it is dropped, so no change is begun
  if BooleanParam(Params, 'tip') then
  begin
    if not (Node is TNoteObject) or (TNoteObject(Node).Leader = nlNone) then
      raise EApiError.Create(RPC_REFUSED, Format(rsEditorNotCallout, [Node.DisplayName]));
    if Document.Pattern.IsLocked(Node) then
      raise EApiError.Create(RPC_REFUSED, Format(rsPatternLocked, [Node.DisplayName]));
    FDragKey := Node.Key;
    FDragTip := True;
    FTipMoved := False;
    Exit(DragPosition);
  end;
  if HandleField <> '' then
  begin
    if not (Node is TEdgeObject) or not FindHandle(TEdgeObject(Node), HandleField, Handle) then
      raise EApiError.Create(RPC_REFUSED, Format(rsEditorNoHandle, [Node.DisplayName, HandleField]));
    if not CanDragHandle(TEdgeObject(Node), Handle, Reason) then
      raise EApiError.Create(RPC_REFUSED, Reason);
    BeginChange(rsToolMoveHandle);
    FDragKey := Node.Key;
    FDragHandle := HandleField;
    Exit(DragPosition);
  end;
  if Node is TNoteObject then
    Allowed := CanDragNote(TNoteObject(Node), Reason)
  else if not (Node is TPointObject) then
    raise EApiError.Create(RPC_REFUSED, Format(rsEditorNotDraggable, [Node.DisplayName]))
  else if FieldName <> '' then
    Allowed := CanDragField(Document.Pattern, TPointObject(Node), FieldName, Reason)
  else
    Allowed := CanDrag(Document.Pattern, TPointObject(Node), Reason);
  if not Allowed then
    raise EApiError.Create(RPC_REFUSED, Reason);
  if Node is TNoteObject then
    BeginChange(rsToolMoveNote)
  else
    BeginChange(rsToolMovePoint);
  FDragKey := Node.Key;
  FDragField := FieldName;
  Result := DragPosition;
end;

function TEditorApiServer.DoDragTo(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  Node: TEvalNode;
  Target: TVec2;
  Reason: string;
  Moved: boolean;
  Answer: TJSONObject;
begin
  RequireDrag;
  if FDragTip then
    Exit(DoTipTo(Params));
  Target := Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y'));
  Pattern := Document.Pattern;
  Node := Pattern.FindNode(FDragKey);
  if FDragHandle <> '' then
    Moved := DragHandle(Pattern, TEdgeObject(Node), DraggedHandle, Target, Reason)
  else if Node is TNoteObject then
    Moved := DragNote(Pattern, TNoteObject(Node), Target, Reason)
  else if FDragField <> '' then
    Moved := DragPointField(Pattern, TPointObject(Node), FDragField, Target, Reason)
  else
    Moved := DragPoint(Pattern, TPointObject(Node), Target, Reason);
  if Moved then
    Document.LiveUpdate;
  Answer := DragPosition;
  Answer.Add('moved', Moved);
  if not Moved then
    Answer.Add('reason', Reason);
  Result := Answer;
end;

function TEditorApiServer.DoDragEnd(Cancel: boolean): TJSONData;
var
  Changed: boolean;
begin
  RequireDrag;
  if FDragTip then
    Exit(DoTipEnd(Cancel));
  FDragKey := '';
  FDragField := '';
  FDragHandle := '';
  Changed := False;
  if Cancel then
    Document.CancelChange
  else
  begin
    Changed := Document.EndChange;
    if Document.ChangeRefused then
      raise EApiError.Create(RPC_REFUSED, Document.Pattern.LastError);
  end;
  Result := TJSONObject.Create(['changed', Changed]);
end;

function TEditorApiServer.DoTipTo(Params: TJSONObject): TJSONData;
var
  Pattern: TPattern;
  Note: TNoteObject;
  Radius: double;
  Answer: TJSONObject;
begin
  Pattern := Document.Pattern;
  Note := TNoteObject(Pattern.FindNode(FDragKey));
  Radius := 0;
  OptionalNumber(Params, 'radius', Radius);
  FTipClick := Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y'));
  FTipSnap := FindSnap(Pattern, FTipClick, Radius);
  FTipMoved := True;
  Answer := SnapToJSON(FTipSnap);
  Answer.Add('moved', True);
  Answer.Add('message', CalloutSnapDescription(Pattern, FTipSnap, FTipClick));
  Answer.Add('leaderStrokes', SegmentsToJSON(NoteLeaderStrokes(Pattern, Note, FieldValuesFor(Params), FTipSnap.Position)));
  Result := Answer;
end;

function TEditorApiServer.DoTipEnd(Cancel: boolean): TJSONData;
var
  Edit: TSelectionEdit;
  Moved: boolean;
begin
  Moved := FTipMoved and not Cancel;
  FDragTip := False;
  FTipMoved := False;
  if not Moved then
  begin
    FDragKey := '';
    Exit(TJSONObject.Create(['changed', False]));
  end;
  Edit := MoveCalloutTip(Document, TNoteObject(Document.Pattern.FindNode(FDragKey)), FTipSnap, FTipClick);
  FDragKey := '';
  if not Edit.Done then
    raise EApiError.Create(RPC_REFUSED, Edit.Message);
  Result := TJSONObject.Create(['changed', True]);
end;

// What a point can be changed to, for the web editor's box
function PointTypesToJSON: TJSONArray;
var
  Conversion: TPointConversion;
begin
  Result := TJSONArray.Create;
  for Conversion := Low(TPointConversion) to High(TPointConversion) do
    Result.Add(TJSONObject.Create(['name', POINT_CONVERSION_TYPES[Conversion], 'caption', PointConversionCaption(Conversion),
      'hint', PointConversionHint(Conversion)]));
end;

function RolesToJSON: TJSONArray;
var
  Role: TEdgeRole;
  Dashes: TJSONArray;
  DashLength: double;
begin
  Result := TJSONArray.Create;
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
  begin
    Dashes := TJSONArray.Create;
    // A pattern ends at its first 0
    for DashLength in ROLE_DASHES[Role] do
      if DashLength > 0 then
        Dashes.Add(ReportFloat(DashLength))
      else
        Break;
    Result.Add(TJSONObject.Create(['name', EDGE_ROLE_NAMES[Role], 'caption', RoleCaption(Role), 'color', ROLE_COLORS[Role],
      'dashes', Dashes]));
  end;
end;

// A list of IDs or names as keys; empty when the parameter is left out
function TEditorApiServer.KeysParam(Params: TJSONObject; const AName: string): TStringArray;
var
  List: TJSONData;
  Index: integer;
  Holder: TJSONObject;
begin
  Result := nil;
  List := Params.Find(AName);
  if not Assigned(List) or (List.JSONType = jtNull) then
    Exit;
  if List.JSONType <> jtArray then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
  for Index := 0 to List.Count - 1 do
  begin
    // Each is read as one reference would be, so names and IDs both do
    Holder := TJSONObject.Create(['item', List.Items[Index].Clone]);
    try
      Insert(Reference(Holder, 'item', False), Result, Length(Result));
    finally
      FreeAndNil(Holder);
    end;
  end;
end;

function TEditorApiServer.DoLabelKeys(Params: TJSONObject): TJSONData;
var
  Mode: TLabelMode;
  HoverKey: string;
begin
  Mode := TLabelMode(ChoiceParam(Params, 'mode', LABEL_MODE_NAMES));
  HoverKey := '';
  if Assigned(Params.Find('hover')) and (Params.Find('hover').JSONType <> jtNull) then
    HoverKey := Reference(Params, 'hover', False);
  Result := TJSONObject.Create(['objects', KeysToJSON(LabelKeys(Document.Pattern, Mode, KeysParam(Params, 'selection'), HoverKey,
    Concat(KeysParam(Params, 'tool'), KeysParam(Params, 'suggestions'))))]);
end;

// A seam side by IDs, as the editor keeps it
function SideToJSON(const Side: TSeamSide): TJSONArray;
var
  Entry: TSeamEntry;
begin
  Result := TJSONArray.Create;
  for Entry in Side do
    Result.Add(TJSONObject.Create(['piece', KeyToJSON(Entry.PieceKey), 'edge', KeyToJSON(Entry.EdgeKey)]));
end;

function TEditorApiServer.DoSeamPick(Params: TJSONObject): TJSONData;
var
  SideA, SideB: TSeamSide;
  OnB, Picked: boolean;
  Message: string;
  At: TVec2;
  Answer: TJSONObject;
begin
  SideA := ExistingSeamEntries(Document.Pattern, SeamSideParam(Params, 'sideA'));
  SideB := ExistingSeamEntries(Document.Pattern, SeamSideParam(Params, 'sideB'));
  OnB := BooleanParam(Params, 'onB');
  Picked := False;
  if Assigned(Params.Find('x')) then
  begin
    At := Vec2(RequireNumber(Params, 'x'), RequireNumber(Params, 'y'));
    Picked := PickSeamEntry(Document.Pattern, At, RequireNumber(Params, 'radius'), SideA, SideB, OnB, Message);
  end
  else
    Message := SeamProgressText(Document.Pattern, SideA, SideB, OnB);
  Answer := TJSONObject.Create(['picked', Picked, 'sideA', SideToJSON(SideA), 'sideB', SideToJSON(SideB), 'message', Message]);
  Answer.Add('lines', TJSONObject.Create(['sideA', SideLinesToJSON(Document.Pattern, SideA, DEFAULT_TOLERANCE), 'sideB',
    SideLinesToJSON(Document.Pattern, SideB, DEFAULT_TOLERANCE)]));
  Result := Answer;
end;

function TEditorApiServer.DoSeamMake(Params: TJSONObject): TJSONData;
var
  SideA, SideB: TSeamSide;
begin
  SideA := SeamSideParam(Params, 'sideA');
  SideB := SeamSideParam(Params, 'sideB');
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  Result := EditToJSON(AddSeamFromSides(Document, SideA, SideB));
end;

function TEditorApiServer.DoDelete(Params: TJSONObject): TJSONData;
var
  Selection: TStringArray;
begin
  Selection := KeysParam(Params, 'selection');
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  Result := EditToJSON(DeleteSelection(Document, Selection, rsSelectionDelete));
end;

function TEditorApiServer.DoConvertPoint(Params: TJSONObject): TJSONData;
var
  Selection: TStringArray;
  Conversion: TPointConversion;
begin
  Selection := KeysParam(Params, 'selection');
  Conversion := TPointConversion(ChoiceParam(Params, 'type', POINT_CONVERSION_TYPES));
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  Result := EditToJSON(ConvertPointSelection(Document, Selection, Conversion));
end;

function TEditorApiServer.DoCopy(Params: TJSONObject; Cut: boolean): TJSONData;
var
  Selection: TStringArray;
  Copied: TFragmentCopy;
  Edit: TSelectionEdit;
  Answer: TJSONObject;
begin
  Selection := KeysParam(Params, 'selection');
  if Cut and Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  if Cut then
    Edit := CutSelection(Document, Selection, Copied)
  else
    Edit := CopySelection(Document, Selection, Copied);
  Answer := EditToJSON(Edit);
  Answer.Add('text', Copied.Text);
  Answer.Add('names', Copied.Names);
  Result := Answer;
end;

function TEditorApiServer.DoPaste(Params: TJSONObject): TJSONData;
var
  Text: string;
begin
  Text := RequireString(Params, 'text');
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  Result := EditToJSON(PasteFragmentText(Document, Text));
end;

function TEditorApiServer.DoVariableImport(Params: TJSONObject): TJSONData;
var
  Text, FileName, Message: string;
  Imported: TVariableImport;
  Done, Warning: boolean;
begin
  Text := RequireString(Params, 'text');
  FileName := RequireString(Params, 'fileName');
  if Document.ChangeOpen then
    raise EApiError.Create(RPC_REFUSED, rsEditorBusy);
  Done := ImportVariablesTextStep(Document, Text, FileName, Imported, Message, Warning);
  Result := TJSONObject.Create(['done', Done, 'message', Message, 'warning', Warning, 'added', KeysToJSON(Imported.Added)]);
end;

function TEditorApiServer.DispatchMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'editor_scene': Result := DoScene(Params);
    'editor_snap': Result := DoSnap(Params);
    'editor_objects_at': Result := DoObjectsAt(Params);
    'editor_objects_in_box': Result := DoObjectsInBox(Params);
    'editor_handles': Result := DoHandles(Params);
    'editor_bounds': Result := DoBounds(Params);
    'editor_properties': Result := DoProperties(Params);
    'editor_property_set': Result := DoPropertySet(Params);
    'editor_variable_add': Result := DoVariableAdd;
    'editor_variable_delete': Result := DoVariableDelete(Params);
    'editor_variable_set': Result := DoVariableSet(Params);
    'editor_list_click': Result := DoListClick(Params);
    'editor_tool_snap': Result := DoToolSnap(Params);
    'editor_tool_click': Result := DoToolClick(Params);
    'editor_label_keys': Result := DoLabelKeys(Params);
    'editor_seam_pick': Result := DoSeamPick(Params);
    'editor_seam_make': Result := DoSeamMake(Params);
    'editor_delete': Result := DoDelete(Params);
    'editor_convert_point': Result := DoConvertPoint(Params);
    'editor_copy': Result := DoCopy(Params, False);
    'editor_cut': Result := DoCopy(Params, True);
    'editor_paste': Result := DoPaste(Params);
    'editor_variable_import': Result := DoVariableImport(Params);
    'editor_complete': Result := DoComplete(Params);
    'editor_list_objects': Result := DoListObjects(Params);
    'editor_list_variables': Result := DoListVariables(Params);
    'editor_list_measurements': Result := DoListMeasurements(Params);
    'editor_measurement_add': Result := DoMeasurementAdd;
    'editor_measurement_set': Result := DoMeasurementSet(Params);
    'editor_measurements_save': Result := DoMeasurementsSave(Params);
    'editor_measurements_revert': Result := DoMeasurementsRevert;
    'editor_measurement_size': Result := DoMeasurementSize(Params);
    'editor_measurement_scale': Result := DoMeasurementScale(Params);
    'editor_suggest': Result := DoSuggest(Params);
    'editor_suggest_preview': Result := DoSuggestPreview(Params);
    'editor_note_preview': Result := DoNotePreview(Params);
    'editor_export_draft': Result := DoExportDraft(Params);
    'editor_print': Result := DoPrint(Params);
    'editor_materials': Result := DoMaterials;
    'editor_problems': Result := DoProblems;
    'editor_garment': Result := DoGarment(Params);
    'editor_garment_marks': Result := DoGarmentMarks(Params);
    'editor_material': Result := DoMaterial(Params);
    'editor_material_set': Result := DoMaterialSet(Params);
    'editor_material_add': Result := DoMaterialAdd;
    'editor_material_delete': Result := DoMaterialDelete(Params);
    'editor_features': Result := DoFeatures(Params);
    'editor_feature_apply': Result := DoFeatureApply(Params);
    'editor_changes': Result := DoChanges;
    'editor_snapshot': Result := DoSnapshot;
    'editor_save_complete': Result := DoSaveComplete(Params);
    'editor_mark_unsaved': Result := DoMarkUnsaved;
    'editor_drag_begin': Result := DoDragBegin(Params);
    'editor_drag_to': Result := DoDragTo(Params);
    'editor_drag_end': Result := DoDragEnd(False);
    'editor_drag_cancel': Result := DoDragEnd(True);
    'editor_tables': Result := TJSONObject.Create(['tools', ToolsToJSON, 'commands', CommandsToJSON, 'shortcuts', ShortcutsToJSON,
        'roles', RolesToJSON, 'pointTypes', PointTypesToJSON]);
    else
      Result := inherited DispatchMethod(Method, Params);
  end;
end;

end.
