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
  Sloper.Core.Geometry, Sloper.Editor.Snap, Sloper.Core.Drag, Sloper.Editor.PanelEdits;

type
  TEditorApiServer = class(TApiServer)
  private
    FPending: TPendingMeasurements;
    // The measurement file the pending edits are for
    FPendingPath: string;
    // What the document has said changed since editor_changes last answered
    FChanges: TDocumentChanges;
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
  rsEditorSceneReturns = '`isolated`, the piece shown alone or null; `pieces`, each with `id`, `name`, `state`, ' +
    '`locked`, `dimmed`, `fillColor`, `fillStyle`, its `cutLine`, `marks` (grainline, fold and marking strokes) and ' +
    '`notches`, each a flat list of segments x1, y1, x2, y2, its label''s `caption`, its `middle` (x, y) and its ' +
    '`chevrons` (x, y and angle for each); `notes` (left out while annotations are hidden), each with `print`, ' +
    '`lines` with fields filled in, `size` in points, `lineHeight` in mm, `align`, `boxed`, `font`, `bold`, ' +
    '`italic`, `box` and `frame` (minX, minY, maxX, maxY), `anchorAt` (x, y), `leader` and `leaderStrokes` ' +
    '(segments); `seams`, each with its sides'' edges as `sideA` and `sideB` (a polyline ' +
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
    'choice, check, button or problem), `caption` and `text`, a formula row''s `field`, a choice row''s `choices` and ' +
    '`choice` (its index, or -1), a check row''s `checked`, and a `hint` when it has one';
  rsEditorPropertyTarget = 'The object, by ID or name';
  rsEditorPropertySet = 'Commits a row of the Properties tab as one undo step: the name or a formula as typed with ' +
    'names (`text`), or a choice, check or button (`value`). What the row already holds makes no step.';
  rsEditorPropertyRow = 'The row''s `id`, as editor_properties gives it';
  rsEditorPropertyField = 'A formula row''s field, in place of `row`';
  rsEditorPropertyText = 'What the name or formula field holds';
  rsEditorPropertyValue = 'A choice''s index, 1 or 0 for a check; a button ignores it';
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
    'what it reads and what reads it, and the objects a tool is working with; every point, edge and piece in all; ' +
    'none in none.';
  rsEditorLabelMode = 'contextual, all or none';
  rsEditorSelection = 'The selected objects'' IDs';
  rsEditorHover = 'The hovered object''s ID';
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
    '`text`, `value`, `valueText`, `delta` and `deltaText`, and `nearest`, the closest of all, or null';
  rsEditorCannotSuggest = 'No formula can be suggested for the %s of %s';
  rsEditorChanges = 'What changed since this was last asked, as the desktop document tells its panels, with what ' +
    'undo and redo would do and whether the pattern is modified. The editor asks after each call that may change ' +
    'something, and updates what the changes name.';
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
  rsEditorDragBeginReturns = '`x` and `y`, where the point, the note''s top left or the handle''s end is now, in mm';
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
  rsEditorNoDrag = 'No drag is open: call editor_drag_begin first';
  rsEditorDragOpen = 'A drag is already open';
  rsEditorTables = 'The design app''s tables the editor reads instead of copying: its canvas tools, its commands with ' +
    'their icons and menus, and its keys and mouse actions.';
  rsEditorTablesReturns = '`tools`, each with `name`, `caption`, `hint`, `icon` and `keys`; `commands`, each with ' +
    '`name`, `icon`, `place`, `menu`, `keys` and `description`; `shortcuts`, each with `command`, `keys`, `kind`, ' +
    '`group` and `description`. Keys are written as Mod+Shift+S, Mod being Ctrl, or Cmd on macOS. `roles`, each edge ' +
    'role with its `name`, `caption`, `color` (empty for outline and construction, drawn in ink) and `dashes`, dash and gap ' +
    'lengths in mm, empty for a solid line.';

implementation

uses
  TypInfo, Math, Sloper.API.Rpc, Sloper.Core.EvalTypes, Sloper.Core.Evaluator, Sloper.Core.Draft,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Transform, Sloper.Core.PatternCheck, Sloper.Core.Materials,
  Sloper.Core.Shortcuts, Sloper.Core.IconSet, Sloper.Editor.Scene, Sloper.Editor.Completion, Sloper.Editor.ObjectList,
  Sloper.Editor.Suggestion, Sloper.Editor.Tools, Sloper.Editor.SelectionEdits, Sloper.Editor.ToolEdits, Sloper.Editor.PropertyText,
  Sloper.Core.Note, Sloper.Core.Seam, Sloper.Core.Settings, Sloper.Core.Measurements, Sloper.Editor.PropertyRows;

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
    AddApiMethod(Built, 'editor_tables', rsEditorTables, rsEditorTablesReturns, True);
    AddApiMethod(Built, 'editor_changes', rsEditorChanges, rsEditorChangesReturns, True);
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

// A note as the canvas draws it: its text with fields filled in, line by
// line, its look, where its text and frame are, and its leader
function NoteToSceneJSON(Pattern: TPattern; Note: TNoteObject; const PatternValues: TFieldValues): TJSONObject;
var
  Values: TFieldValues;
  Shown: string;
  Lines: TJSONArray;
  Line: string;
  Frame: TRect2;
begin
  Shown := Note.ShownText;
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
          List.Add(NoteToSceneJSON(Pattern, TNoteObject(Pattern.Objects[Index]), Values));

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
    'problem');

function PropertyRowToJSON(const Row: TPropertyRow): TJSONObject;
var
  Choices: TJSONArray;
  Choice: string;
begin
  Result := TJSONObject.Create(['id', Row.Id, 'kind', PROPERTY_ROW_KIND_NAMES[Row.Kind], 'caption', Row.Caption,
    'text', Row.Text]);
  case Row.Kind of
    prkFormula:
      Result.Add('field', Row.Field);
    prkChoice:
    begin
      Choices := TJSONArray.Create;
      for Choice in Row.Choices do
        Choices.Add(Choice);
      Result.Add('choices', Choices);
      Result.Add('choice', Row.Choice);
    end;
    prkCheck:
      Result.Add('checked', Row.Checked);
  end;
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
      Rows.Add(PropertyRowToJSON(Row));
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
  else if Row = PROPERTY_ROW_FLIP then
    Done := CommitPropertyRow(Document, Node, Row, 0, Reason)
  else if Row <> '' then
    Done := CommitPropertyRow(Document, Node, Row, RequireWhole(Params, 'value'), Reason)
  else
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['row']));
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
  inherited Destroy;
end;

procedure TEditorApiServer.DocumentChanged(ADocument: TPatternDocument; Changes: TDocumentChanges);
begin
  FChanges := FChanges + Changes;
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
    KeysParam(Params, 'tool')))]);
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
    'editor_changes': Result := DoChanges;
    'editor_drag_begin': Result := DoDragBegin(Params);
    'editor_drag_to': Result := DoDragTo(Params);
    'editor_drag_end': Result := DoDragEnd(False);
    'editor_drag_cancel': Result := DoDragEnd(True);
    'editor_tables': Result := TJSONObject.Create(['tools', ToolsToJSON, 'commands', CommandsToJSON, 'shortcuts', ShortcutsToJSON,
        'roles', RolesToJSON]);
    else
      Result := inherited DispatchMethod(Method, Params);
  end;
end;

end.
