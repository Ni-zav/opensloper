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

// Every Automation API method with its parameters and reply, for the
// reference documentation and for listing the methods as MCP tools.
// Tests hold it to the server: every method listed is answered, every method
// answered is listed, and every parameter is one the server reads. No LCL
// dependency.
unit Sloper.API.Methods;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

type
  // Features, sewing details applied in one step, are named feature_ and the
  // feature, as feature_zip
  TApiMethodGroup = (agFiles, agMeasurements, agObjects, agDrafting, agPieces, agMaterials, agSeams, agFeatures, agNotes, agChecking);

  TApiParamKind = (
    apTarget,     // the object it acts on: "id" (a number) or "name"
    apText,
    apNumber,     // a plain number
    apWhole,      // a whole number
    apFlag,       // true or false
    apFormula,    // formula text, or a plain number
    apReference,  // an object's ID, or its name
    apReferences, // a list of IDs or names
    apMaterial,     // a material's ID or name
    apChoice,     // one of the words in Choices
    apNames,      // a list of words from Choices
    apTexts,      // a list of text
    apList,       // a list of objects, whose members follow as list[].member
    apGroup,      // an object, whose members follow as group.member
    apMembers);   // the members of the chosen type, as on the operations page

  TApiParam = record
    Name: string;
    Kind: TApiParamKind;
    Required: boolean;
    Choices: string;
    Description: string;
  end;
  TApiParamArray = array of TApiParam;

  TApiMethod = record
    Name: string;
    Group: TApiMethodGroup;
    Summary: string;
    Params: TApiParamArray;
    Returns: string;
    // Changes neither the pattern nor any file
    ReadOnly: boolean;
  end;
  TApiMethodArray = array of TApiMethod;

// Every method, grouped and in the order the documentation lists them
function ApiMethods: TApiMethodArray;
// For other tables, such as the publish and drape apps' tools: a method, then
// its parameters, added to the end of Methods
procedure AddApiMethod(var Methods: TApiMethodArray; const AName, ASummary, AReturns: string; AReadOnly: boolean = False);
procedure AddApiParam(var Methods: TApiMethodArray; const AName: string; AKind: TApiParamKind; ARequired: boolean;
  const ADescription: string; const AChoices: string = '');
function FindApiMethod(const AName: string; out Method: TApiMethod): boolean;
// The fabrics a material can take, as the API names them: FABRIC_NAMES, with
// none for a material without one
function ApiFabricNames: TStringArray;

resourcestring
  rsApiTarget = 'The object, by its ID or its name';
  rsApiPieceTarget = 'The piece, by its ID or its name';
  rsApiReturnsObject = 'The object, as `get_object` gives it';
  rsApiReturnsPiece = 'The piece, as `get_object` gives it';
  rsApiReturnsDocument = 'The pattern''s file, measurement file and `measurementsFile`, the name the pattern records for ' +
    'it, relative to the pattern''s folder; its unit, object and variable counts, and whether it is modified';
  rsApiReturnsMaterials = 'The materials and the cut list, as `list_materials` gives them';

  rsApiOpen = 'Opens a pattern, optionally with another measurement file and a size. A pattern given as text opens ' +
    'with no file and no measurements: give its measurement file, which the reply''s `measurementsFile` names, to ' +
    '`use_measurements`.';
  rsApiOpenPath = 'The pattern file (.sloper); give this or text';
  rsApiOpenText = 'The pattern file''s contents, in place of a path';
  rsApiOpenMeasurements = 'A measurement file to use in place of the one the pattern names';
  rsApiOpenSize = 'The size to use from a size table';
  rsApiSave = 'Saves the pattern.';
  rsApiSavePath = 'Where to save it, a .sloper file; by default, where it was opened from. A file that is not a pattern is never replaced';
  rsApiSaveText = 'Gives the file''s contents as `text` instead of writing a file, and counts the pattern as saved';
  rsApiSaveReturns = 'As `open` gives it, with `text`, the contents, when asked for';
  rsApiUseMeasurements = 'Uses another measurement file for the pattern, which records it; not an undo step. A file ' +
    'given as text is not written by `set_measurement`.';
  rsApiUseMeasurementsPath = 'The measurement file (.slm); give this or text';
  rsApiUseMeasurementsText = 'The measurement file''s contents, in place of a path';
  rsApiUseMeasurementsFile = 'With text, the name the pattern records for the file, relative to the pattern''s folder ' +
    'with /; by default the one it records now';
  rsApiConvertUnits = 'Converts the pattern to another unit, rewriting only lengths, as one undo step. While a number''s ' +
    'role is open nothing changes and the reply lists it; mark each and call again.';
  rsApiConvertUnitsUnits = 'The unit to convert to';
  rsApiConvertMarks = 'The numbers the formulas leave open, each marked as a length or a number';
  rsApiMarkField = 'The field the number is in';
  rsApiMarkToken = 'The number''s token, as the reply listed it';
  rsApiMarkRole = 'What the number is';
  rsApiConvertReturns = '`converted` true and the new `units`; or `converted` false and the `undecided` numbers, each with ' +
    'its object, `field`, `token`, `number`, `formula` and `position` in it';
  rsApiUndo = 'Undoes the last change.';
  rsApiRedo = 'Redoes the change last undone.';

  rsApiGetMeasurements = 'Lists the current measurement set: its file, sizes and values in mm.';
  rsApiGetMeasurementsReturns = '`path`, `size` and `sizes` for a size table, and `measurements`, each with `key`, `value` ' +
    'and `description`';
  rsApiSetMeasurement = 'Adds or changes one value in the measurement file, and saves the file.';
  rsApiSetMeasurementKey = 'The measurement''s key, such as waist';
  rsApiSetMeasurementValue = 'The value in mm';
  rsApiSetMeasurementSize = 'For a size table, the size to change';
  rsApiSetMeasurementDescription = 'Its description; by default, the one it has';
  rsApiSetMeasurementReturns = '`key`, `value`, whether it was `added`, and its `oldValue` when it had one';
  rsApiMissingMeasurements = 'Lists what the pattern needs that the measurement set lacks.';
  rsApiMissingReturns = '`missing`, each with its `key` and the `sizes` with no value';

  rsApiListObjects = 'Lists the variables and objects with their formulas, values and state.';
  rsApiListReturns = '`variables` and `objects`, each as `get_object` gives it';
  rsApiGetObject = 'Gives one object or variable: its name, ID, type, formulas (as shown), computed values, state and whether it is locked.';
  rsApiSetFormula = 'Changes one formula of an object or variable.';
  rsApiSetFormulaField = 'The field, such as length or formula';
  rsApiSetFormulaFormula = 'The new formula';
  rsApiRename = 'Renames an object or variable; formulas that use it follow.';
  rsApiRenameNewName = 'The new name';
  rsApiDelete = 'Deletes an object or variable that nothing uses.';
  rsApiSetLocked = 'Locks or unlocks an object. A locked object cannot be moved, edited or deleted, but its formulas ' +
    'still run, so it follows what it uses; a change that would alter it is refused.';
  rsApiSetLockedLocked = 'true to lock, false to unlock';
  rsApiAddVariable = 'Adds a variable.';
  rsApiVariableName = 'Its name, used in formulas as #name';
  rsApiVariableFormula = 'Its formula';
  rsApiVariableDescription = 'What it is for';
  rsApiImportVariables = 'Imports the variables of another pattern file, as one undo step. A variable whose name ' +
    'this pattern has is kept as it is, never overwritten, and an imported formula reading it reads this ' +
    'pattern''s one. Refused when the files are in different units.';
  rsApiImportVariablesPath = 'The other pattern file (.sloper); give this or text';
  rsApiImportVariablesText = 'The other pattern file''s contents, in place of a path';
  rsApiReturnsImportVariables = '`variables`, those added, each as `get_object` gives it; `kept`, the names this ' +
    'pattern has with another formula; `same`, those it has with the same formula';

  rsApiAddPoint = 'Adds a point of any type.';
  rsApiAddEdge = 'Adds an edge: a line, curve, curve path, circle, arc or offset edge.';
  rsApiTypePoint = 'The point''s type';
  rsApiTypeEdge = 'The edge''s type';
  rsApiNewName = 'Its name; by default the next free one';
  rsApiTypeMembers = 'The type''s members, as on the [operations page](operations.md); points and edges are given by ID ' +
    'or name';
  rsApiEdgeTypeMembers = 'The type''s members, as on the [operations page](operations.md); points and edges are given by ' +
    'ID or name. An offset edge''s `side` may also be `inside` or `outside` a `piece`';
  rsApiNewEdgeRole = 'Its role; by default construction';
  rsApiAddRepeat = 'Adds a repeat: points evenly spaced between two points or along an edge.';
  rsApiRepeatA = 'The first point';
  rsApiRepeatB = 'The last point';
  rsApiRepeatEdge = 'Along this edge, in place of a and b';
  rsApiRepeatCount = 'How many points';
  rsApiRepeatEnds = 'Whether the ends have points of their own';
  rsApiSplitEdge = 'Splits an edge at a point on it into two parts; pieces and seams that used it take the parts.';
  rsApiSplitEdgeEdge = 'The edge';
  rsApiSplitEdgePoint = 'The point on it';
  rsApiSplitReturns = 'The two parts';
  rsApiAddRectangle = 'Adds a rectangle of four lines from a corner.';
  rsApiRectangleCorner = 'The corner point';
  rsApiRectangleWidth = 'How far right the opposite corner is';
  rsApiRectangleHeight = 'How far down the opposite corner is';
  rsApiRectangleReturns = 'The four lines';
  rsApiRoundCorner = 'Rounds the corner where two edges meet with an arc.';
  rsApiInsertZip = 'Puts a zip along a piece''s edge, as the Features tab does, in one undo step: a ZipStop point at the ' +
    'zip''s length, the edge split there, the opening''s own allowance, a notch at the stop on every piece using the edge, ' +
    'the style''s topstitching, and for a fly front a fly shield piece cut on the fold beside the pattern. They are ordinary ' +
    'objects. Its length starts as #zip_length, a variable the first zip adds. When the edge is in a seam with another ' +
    'edge, that side needs a zip too.';
  rsApiZipReturns = '`stop`, `opening` and `rest` (the edge''s two parts) and `shield` (a fly front''s) as `get_object` ' +
    'gives them, `stitching` the topstitching''s objects, `pieces` the IDs of the pieces it went into, and `otherSide`, ' +
    'whether a seam joins the edge to another that needs a zip too';
  rsApiZipEdge = 'The edge the zip opens along, on one or more pieces';
  rsApiZipStyle = 'centred: topstitched either side; invisible: no topstitching; lapped: one side over the zip, stitched down ' +
    'and across the stop; flyFront: stitched as a J at the fly''s width, with a fly shield. Default centred';
  rsApiZipFrom = 'The end of the edge the opening starts from. Default start';
  rsApiZipLength = 'The zip''s length. Default #zip_length';
  rsApiZipAllowance = 'The allowance along the opening; for a fly front, its extension past the seam. Default the style''s';
  rsApiZipStitch = 'How far the topstitching is from the seam. Default the style''s';
  rsApiZipShield = 'A fly shield''s width as worn; it is cut on the fold. Default 40 mm';
  rsApiInsertDart = 'Puts a dart in a piece''s edge, as the Features tab does, in one undo step: a DartMid point on the ' +
    'edge, the points either side where its legs leave it, a DartApex point at the depth square to the edge (or the point ' +
    'given as `apex`), the legs in place of the edge between them in the piece''s outline, a seam closing the dart, a ' +
    'notch at each leg, a hole near the point, the centre line as a fold, and a cap on the seam allowance across the dart. ' +
    'They are ordinary objects.';
  rsApiDartReturns = '`mid`, `apex`, `legs` (the two legs, the start''s side first), `seam`, `hole` and `centre` as ' +
    '`get_object` gives them, and `piece`, the ID of the piece';
  rsApiDartEdge = 'The edge the dart opens in, on one piece';
  rsApiDartPosition = 'Where the dart''s middle is along the edge, from the end `from` names. Default halfway';
  rsApiDartFrom = 'The end of the edge the position is from. Default start';
  rsApiDartWidth = 'The dart''s width at the edge. Default 20 mm';
  rsApiDartDepth = 'How far the dart runs into the piece, square to the edge. Default 90 mm';
  rsApiDartApex = 'A point the dart runs to instead, such as a bust point; the dart follows it';
  rsApiDartHoleInset = 'How far back from the point the hole goes, along the centre line; 0 puts it on the point. ' +
    'Default 10 mm';
  rsApiDartFold = 'The end of the edge the dart is pressed towards, which shapes the cap. Default start';
  rsApiInsertHem = 'Hems pieces along their edges, as the Features tab does, in one undo step: on each piece the edges'' ' +
    'allowance at the hem''s depth (plus the turn-under for a double or narrow hem), their allowance ends mirroring the ' +
    'neighbouring edges'' so the hem lies flat turned up, topstitching inside the piece, and a notch at each end of the hem ' +
    'in the neighbouring edge. They are ordinary objects. The depth starts as #hem_depth, a variable the first hem adds, ' +
    'so every hem shares it; a narrow hem starts at 6 mm of its own.';
  rsApiHemReturns = '`edges` and `stitching` (the topstitching) as `get_object` gives them, `notches` (each with its ' +
    '`piece` and `edge` IDs), `pieces` the IDs of the pieces hemmed, and `problems`, what is worth checking though it was ' +
    'done, such as a hem deeper than its piece';
  rsApiHemEdges = 'The edges to hem, on one or more pieces; each piece''s must run end to end';
  rsApiHemStyle = 'single: turned once, the raw edge overlocked; double: turned twice; narrow: a small double hem; blind: ' +
    'turned once with no topstitching. Default single';
  rsApiHemDepth = 'How deep the hem is, turned up. Default #hem_depth, or 6 mm for a narrow hem';
  rsApiHemTurnUnder = 'How much a double or narrow hem turns under besides its depth. Default 10 mm';
  rsApiHemStitch = 'How far the topstitching is from the hem''s fold. Default 3 mm short of the depth';
  rsApiHemNotches = 'Whether to notch the neighbouring edges where the hem turns up. Default true';
  rsApiInsertFacing = 'Faces pieces along their edges, as the Features tab does, in one undo step, such as a neckline, an ' +
    'armhole or a front opening: on each piece an inner edge at the facing''s width, meeting the edges either side, which ' +
    'are split there; a facing piece, Facing_ and the piece''s name, cut as the piece is (material, grain, count, fold); a ' +
    'seam joining it to the piece; the piece''s notches along it; seams between facings where their pieces are seamed, as ' +
    'at the shoulder; and an interfacing piece if asked for. They are ordinary objects. The width starts as #facing_width, ' +
    'a variable the first facing adds, so every facing shares it.';
  rsApiFacingReturns = '`facings`, `interfacings` (those made), `inner` (each facing''s inner edge) and `seams` (joining ' +
    'each facing to its piece, then the facings to one another) as `get_object` gives them, and `pieces`, the IDs of the ' +
    'pieces faced';
  rsApiFacingEdges = 'The edges to face, on one or more pieces; each piece''s must run end to end, and not all round it';
  rsApiFacingWidth = 'How wide the facing is, in from the edges. Default #facing_width, 60 mm to start with';
  rsApiFacingAside = 'Whether to draw the facing beside its piece, as Move Copy does, rather than over it. Default false';
  rsApiFacingInterfacing = 'The name of a material to cut an interfacing from, the facing''s shape; a name no material has ' +
    'adds one. Default none';
  rsApiInsertButtons = 'Puts buttons and buttonholes along a front opening, as the Features tab does, in one undo step: ' +
    'ButtonTop and ButtonBottom along the edge at first and last from its ends, a Buttonhole repeat between them with ' +
    'the buttonhole marker, a slot the button''s size and thickness long, and a Button repeat with the button marker, on ' +
    'the same piece or along the other front''s edge, and an extension if asked for, the edge becoming a placement line. ' +
    'They are ordinary objects, so changing #button_count moves and adds holes. The size, thickness and count start as ' +
    '#button_size, #button_thickness and #button_count, variables the first buttons add.';
  rsApiButtonsReturns = '`top` and `bottom` (the first and last buttonholes'' points), `holes` and `buttons` (the repeats) ' +
    'and `extension` (its edges) as `get_object` gives them, `holesPiece` and `buttonsPiece` (IDs), and `problems`, ' +
    'what is worth checking though it was done, such as an extension narrower than half a button';
  rsApiButtonsEdge = 'The opening''s edge on a piece, such as a centre front, for the buttonholes, and the buttons too unless ' +
    '`buttonsEdge` is given';
  rsApiButtonsOtherEdge = 'The other front''s matching edge, for the buttons, when the fronts are separate pieces';
  rsApiButtonsSize = 'The button''s size, across. Default #button_size, 15 mm to start with';
  rsApiButtonsThickness = 'The button''s thickness, which a buttonhole is longer by. Default #button_thickness, 3 mm';
  rsApiButtonsCount = 'How many buttons. Default #button_count, 5 to start with';
  rsApiButtonsFirst = 'How far the first button is from the edge''s start. Default 20 mm';
  rsApiButtonsLast = 'How far the last button is from the edge''s end. Default 20 mm';
  rsApiButtonsExtension = 'The width of an extension added past the edge, such as #button_size. Default none';
  rsApiButtonsDirection = 'horizontal: buttonholes square to the edge, starting 3 mm past it; vertical: along it, centred on ' +
    'the buttons. Default horizontal';
  rsApiSetAllowanceEnd = 'Sets how an edge''s seam allowance ends where it meets its neighbours: plain, where their ' +
    'cutting lines meet, or mirror, their allowance reflected in the edge, as a hem''s ends are so it lies flat turned up.';
  rsApiAllowanceEndEdge = 'An edge of the piece';
  rsApiAllowanceEnd = 'plain or mirror';
  rsApiSetDartCap = 'Gives a dart a cap: its seam allowance across the edge shaped as the dart lies folded, so it sews ' +
    'into the seam. The dart is two neighbouring edges of the piece meeting at its point.';
  rsApiDartCapFirst = 'One leg of the dart';
  rsApiDartCapSecond = 'The other leg';
  rsApiDartCapTowards = 'The leg whose side the dart is pressed towards, or none to take the cap off';
  rsApiCornerEdgeA = 'The first edge';
  rsApiCornerEdgeB = 'The second edge';
  rsApiCornerRadius = 'The arc''s radius';
  rsApiConvertEdge = 'Changes an edge to a line or a curve in place, keeping its ID.';
  rsApiConvertEdgeTo = 'What it becomes';
  rsApiMergePoints = 'Merges two or more points into one, which every edge and formula then uses.';
  rsApiMergeReturns = 'The point kept';
  rsApiBreakPoint = 'Breaks a point into one for each edge that meets there.';
  rsApiBreakReturns = '`points`, the points it became';
  rsApiCopyObjects = 'Copies points and edges, with what they depend on, as Edit → Copy does.';
  rsApiCopyReturns = '`fragment`, the copy as text for `paste_objects`; `names`, the copied objects'' names; ' +
    '`leftOut`, the names of those that cannot be copied';
  rsApiCopyObjectsList = 'The points and edges to copy';
  rsApiPasteObjects = 'Pastes a copy as Edit → Paste does: into the pattern it came from, the objects join what they ' +
    'used there; into another, what they depend on comes too. They take new IDs, and a name already taken the next number.';
  rsApiPasteReturns = '`objects`, the pasted copies of the copied objects; `renamed`, names that changed, as "A → A2"';
  rsApiPasteFragment = 'The `fragment` that `copy_objects` gave';
  rsApiArrange = 'Aligns or distributes points. Points a formula places are left as they are and listed, unless named ' +
    'in replace.';
  rsApiArrangeAction = 'What to do';
  rsApiArrangePoints = 'The points';
  rsApiArrangeReference = 'For aligning: the point to line up with';
  rsApiArrangeEdge = 'For distributeAlongEdge: the edge';
  rsApiArrangeReplace = 'Points placed by a formula to change all the same';
  rsApiArrangeReturns = 'The names of the points `changed`, `asked` (left, as a formula places them) and `kept`';
  rsApiAddTransform = 'Adds rotated, mirrored or moved copies of points and edges.';
  rsApiTransformType = 'The transform';
  rsApiTransformName = 'The transform''s name';
  rsApiTransformSuffix = 'Added to the names of the copies';
  rsApiTransformSources = 'The points and edges to copy';
  rsApiTransformPivot = 'rotate: the point to turn about; move: a point to turn the copies about';
  rsApiTransformAngle = 'rotate: how far to turn; mirror with axis.a only: the axis''s direction; move: the direction';
  rsApiTransformAxis = 'mirror: the line to reflect in';
  rsApiTransformAxisEdge = 'An edge';
  rsApiTransformAxisA = 'Or a point on the line';
  rsApiTransformAxisB = 'And a second point on it';
  rsApiTransformLength = 'move: how far, at the angle';
  rsApiTransformDx = 'move: how far right, in place of length';
  rsApiTransformDy = 'move: how far down';
  rsApiTransformRotate = 'move with pivot: how far the copies turn';
  rsApiSetRole = 'Changes an edge''s role. A marking role puts it on the pieces it lies in.';
  rsApiRole = 'The new role';
  rsApiSetRoleReturns = 'The edge, as `get_object` gives it, with the `pieces` it is marked on';
  rsApiSetMarker = 'Gives a point or repeat a marker; it is marked on the pieces it lies in.';
  rsApiMarker = 'The marker';
  rsApiMarkerSize = 'Its size, a buttonhole''s length; by default a size for the marker and the pattern''s unit';
  rsApiMarkerAngle = 'A buttonhole''s angle, the way its slot runs. Default 0, across';
  rsApiMarkerOffset = 'How far along its angle a buttonhole''s middle is from the point. Default 0, centred on it';

  rsApiCreatePiece = 'Makes a piece from the closed outline around a place.';
  rsApiPieceX = 'Across, in mm, inside the outline';
  rsApiPieceY = 'Down, in mm';
  rsApiPieceName = 'Its name';
  rsApiPieceAllowance = 'Its seam allowance; by default the first material''s, or a round value for the pattern''s unit';
  rsApiSetEdgeAllowance = 'Gives one edge of a piece its own seam allowance, or clears it.';
  rsApiEdgeAllowanceEdge = 'The edge';
  rsApiEdgeAllowance = 'The allowance; left out, the edge goes back to the piece''s';
  rsApiSetGrainline = 'Sets a piece''s grainline: at an angle, between two points, or none.';
  rsApiGrainAngle = 'At this angle';
  rsApiGrainStart = 'Or from this point';
  rsApiGrainEnd = 'To this one';
  rsApiGrainNone = 'No grainline';
  rsApiAddNotch = 'Adds a notch on a piece''s seam line, at a point or a distance along an edge.';
  rsApiNotchPoint = 'At this point';
  rsApiNotchEdge = 'Or on this edge of the piece';
  rsApiNotchPosition = 'With edge: the distance from its start';
  rsApiRemoveNotch = 'Removes a notch.';
  rsApiNotchNumber = 'Its number, from 1';
  rsApiAddMarking = 'Marks a point or a line on a piece, or adds stitch holes along an edge.';
  rsApiMarkingKind = 'What to add';
  rsApiMarkingPoint = 'point: the point or repeat';
  rsApiMarkingEdge = 'line, stitch: the edge';
  rsApiMarkingSpacing = 'stitch: the distance between holes';
  rsApiMarkingSize = 'stitch: the hole size';
  rsApiRemoveMarking = 'Removes a marking.';
  rsApiMarkingNumber = 'Its number, from 1';
  rsApiSetCut = 'Sets how many of a piece to cut, and whether every other one is mirrored.';
  rsApiCutCount = 'How many';
  rsApiCutMirrored = 'Whether every other one is mirrored';
  rsApiSetFold = 'Puts a piece on the fold of one of its straight edges, or takes it off.';
  rsApiFoldEdge = 'The edge';
  rsApiFoldNone = 'Off the fold';
  rsApiSetPieceMaterial = 'Sets the material a piece is cut from.';
  rsApiPieceMaterial = 'The material';
  rsApiPieceMaterialNone = 'No material';
  rsApiSetPieceFill = 'Sets how a piece is filled on screen.';
  rsApiFillColor = 'Its own colour, as #rrggbb, or empty for its material''s';
  rsApiFillStyle = 'How it is filled';

  rsApiListMaterials = 'Lists the materials and the cut list.';
  rsApiListMaterialsReturns = '`materials`, each with `id`, `name`, `color`, `fill`, and `allowance`, `width`, `length` and `allowTurns` when set, and the `cutList`';
  rsApiAddMaterial = 'Adds a material.';
  rsApiMaterialName = 'Its name; by default the next free one';
  rsApiMaterialColor = 'Its colour, as #rrggbb';
  rsApiMaterialFill = 'How pieces of it are filled';
  rsApiRenameMaterial = 'Renames a material.';
  rsApiMaterial = 'The material, by ID or name';
  rsApiMaterialNewName = 'The new name';
  rsApiSetMaterial = 'Changes a material''s colour, fill, seam allowance, size or fabric. Pieces that cannot fit its size are ' +
    'problems.';
  rsApiMaterialAllowance = 'A seam allowance for pieces of it, in the pattern''s unit';
  rsApiMaterialNoAllowance = 'Takes its seam allowance away';
  rsApiMaterialWidth = 'Its width in the pattern''s unit, 0 for none, which takes the length away too; a width alone is a roll';
  rsApiMaterialLength = 'The length of a sheet of it in the pattern''s unit, with a width; 0 for a roll';
  rsApiMaterialAllowTurns = 'Whether pieces may lie a quarter turn round on it, for material with no grain';
  rsApiMaterialFabric = 'How it drapes in Blender, from the drape app; none drapes as cotton';
  rsApiDeleteMaterial = 'Deletes a material; its pieces are left with none.';

  rsApiAddSeam = 'Adds a seam: two runs of piece edges sewn together, whose lengths are checked.';
  rsApiSideA = 'Side A, in order along the seam';
  rsApiSideB = 'Side B';
  rsApiSidePiece = 'The piece';
  rsApiSideEdge = 'The edge of that piece';
  rsApiSeamName = 'Its name';
  rsApiSeamEase = 'How much longer side B should be; by default 0';
  rsApiSeamTolerance = 'How far the difference may be from the ease; by default a small value for the pattern''s unit';
  rsApiFlipSeam = 'Turns a seam''s side B round, for edges sewn running the same way.';
  rsApiSuggestSeams = 'Suggests pairs of piece edges that look like they are sewn together, without adding them.';
  rsApiSuggestReturns = '`suggestions`, each with `sideA`, `sideB`, whether the edge is `shared`, and the length ' +
    '`difference`';

  rsApiAddNote = 'Adds a note, free or hung from a point, edge or piece; with a leader it is a callout, and with svg a ' +
    'stamp: a drawing in place of the text.';
  rsApiNoteText = 'The text, with draft values such as {=@waist / 4}; needed unless svg is given, as a stamp''s text ' +
    'only names it';
  rsApiNoteSvg = 'An SVG drawing''s text, making the note a stamp drawn at true size from the SVG''s units (pixels at 96 to ' +
    'the inch). Paths and shapes only: text must be converted to paths first. The reply''s warnings say what was drawn ' +
    'differently.';
  rsApiNoteScale = 'How much bigger than true size a stamp is drawn, from 0.01 to 100; 1 when left out';
  rsApiNoteAnchor = 'What it hangs from; left out for a free note';
  rsApiNoteAnchorPoint = 'A point';
  rsApiNoteAnchorEdge = 'Or an edge';
  rsApiNoteAnchorPiece = 'Or a piece';
  rsApiNoteAnchorPosition = 'With edge: how far along it, 0 to 1';
  rsApiNoteX = 'A free note: its place across';
  rsApiNoteY = 'A free note: its place down';
  rsApiNoteDx = 'A hung note: how far right of what it hangs from';
  rsApiNoteDy = 'A hung note: how far down';
  rsApiNoteSize = 'The text size in points';
  rsApiNotePrint = 'Whether it prints; by default true';
  rsApiNoteLeader = 'A line to what it hangs from';
  rsApiNoteAlign = 'How its lines line up';
  rsApiNoteBox = 'A white box behind it';
  rsApiNoteFont = 'The font family it prints in; empty for the default sans-serif. One not installed prints in the default font';
  rsApiNoteBold = 'Bold';
  rsApiNoteItalic = 'Italic';
  rsApiNoteName = 'Its name';
  rsApiSetText = 'Changes a note''s text, size, printing, leader, alignment, box or font, or a stamp''s drawing or scale.';

  rsApiEvaluate = 'Works the pattern out again and lists its problems.';
  rsApiEvaluateReturns = 'The problems: objects that are invalid or blocked, gaps, and seams out of tolerance';
  rsApiCheck = 'As evaluate, with the full report of every computed value.';
  rsApiCheckReturns = 'The problems, and every object''s computed values';
  rsApiRender = 'Draws the pattern as SVG or as a PNG image, as the drafting window shows it.';
  rsApiRenderFormat = 'svg, or png for an image; by default svg';
  rsApiRenderWidth = 'png: the image''s width in pixels, from 16 to 4096; by default 1600. Its height follows the drawing';
  rsApiRenderLabels = 'Name the points and pieces';
  rsApiRenderHiddenRoles = 'Roles of edges to leave out';
  rsApiRenderAnnotations = 'Whether to draw notes; by default true';
  rsApiRenderRegion = 'Only this part, in mm';
  rsApiRenderMin = 'The left or top';
  rsApiRenderMax = 'The right or bottom';
  rsApiRenderGarment = 'The Garment view instead: each piece as sewn, darts closed and folds opened, shaded, ' +
    'arranged as on the canvas; labels, hiddenRoles, annotations and region do not apply. By default false';
  rsApiRenderMaterial = 'garment: only the pieces cut from this material, by name; by default all';
  rsApiRenderReturns = '`format` and the `svg` text; or, for png, the `png` file as base64 and its `width`';
  rsApiExport = 'Exports a saved layout file as PDF, SVG, DXF or machine DXF.';
  rsApiExportLayout = 'The layout file (.slayout)';
  rsApiExportPath = 'The file to write, ending in the format''s extension (.pdf, .svg or .dxf)';
  rsApiExportFormat = 'By default, from the file name''s extension';
  rsApiExportProfile = 'A machine profile from the settings, in place of the layout''s';
  rsApiExportOverwrite = 'True to replace a file already at path; without it, an existing file is refused';
  rsApiUIState = 'Gives the design window''s state: its pattern file, the selection, the label mode and the part ' +
    'of the draft in view. Only through opensloper-cli serve --connect, with the window in automation mode.';
  rsApiUIStateReturns = '`file`, `modified`, `units`, `selection` (each with `id`, `name` and `type`), `labels` and ' +
    '`view`, the region in view in mm (`minX`, `minY`, `maxX`, `maxY`), which `render` takes as its `region`';
  rsApiExportReturns = 'The `path` written';

implementation

uses
  Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.Note, Sloper.Core.Materials, Sloper.Core.Units, Sloper.Core.Features;

var
  Table: TApiMethodArray;
  Building: integer;

function ApiFabricNames: TStringArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(FABRIC_NAMES));
  for Index := 0 to High(FABRIC_NAMES) do
    Result[Index] := FABRIC_NAMES[Index];
  Result[0] := 'none';
end;

function Joined(const Names: array of string): string;
begin
  Result := string.Join(', ', Names);
end;

function RoleChoices: string;
var
  Role: TEdgeRole;
begin
  Result := '';
  for Role := Low(TEdgeRole) to High(TEdgeRole) do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + EDGE_ROLE_NAMES[Role];
  end;
end;

procedure AddApiMethod(var Methods: TApiMethodArray; const AName, ASummary, AReturns: string; AReadOnly: boolean);
var
  Item: TApiMethod;
begin
  Item := Default(TApiMethod);
  Item.Name := AName;
  Item.Summary := ASummary;
  Item.Returns := AReturns;
  Item.ReadOnly := AReadOnly;
  Insert(Item, Methods, Length(Methods));
end;

procedure AddApiParam(var Methods: TApiMethodArray; const AName: string; AKind: TApiParamKind; ARequired: boolean;
  const ADescription: string; const AChoices: string);
var
  Param: TApiParam;
begin
  Param.Name := AName;
  Param.Kind := AKind;
  Param.Required := ARequired;
  Param.Description := ADescription;
  Param.Choices := AChoices;
  Insert(Param, Methods[High(Methods)].Params, Length(Methods[High(Methods)].Params));
end;

procedure Method(const AName: string; AGroup: TApiMethodGroup; const ASummary, AReturns: string);
begin
  Building := Length(Table);
  SetLength(Table, Building + 1);
  Table[Building].Name := AName;
  Table[Building].Group := AGroup;
  Table[Building].Summary := ASummary;
  Table[Building].Returns := AReturns;
  Table[Building].ReadOnly := False;
end;

procedure ReadsOnly;
begin
  Table[Building].ReadOnly := True;
end;

procedure P(const AName: string; AKind: TApiParamKind; ARequired: boolean; const ADescription: string;
  const AChoices: string = '');
var
  Param: TApiParam;
begin
  Param.Name := AName;
  Param.Kind := AKind;
  Param.Required := ARequired;
  Param.Description := ADescription;
  Param.Choices := AChoices;
  Insert(Param, Table[Building].Params, Length(Table[Building].Params));
end;

procedure Target;
begin
  P('id', apTarget, True, rsApiTarget);
end;

procedure PieceTarget;
begin
  P('id', apTarget, True, rsApiPieceTarget);
end;

procedure BuildTable;
begin
  Table := nil;
  // Files
  Method('open', agFiles, rsApiOpen, rsApiReturnsDocument);
  P('path', apText, False, rsApiOpenPath);
  P('text', apText, False, rsApiOpenText);
  P('measurements', apText, False, rsApiOpenMeasurements);
  P('size', apText, False, rsApiOpenSize);
  Method('save', agFiles, rsApiSave, rsApiSaveReturns);
  P('path', apText, False, rsApiSavePath);
  P('text', apFlag, False, rsApiSaveText);
  Method('convert_units', agFiles, rsApiConvertUnits, rsApiConvertReturns);
  P('units', apChoice, True, rsApiConvertUnitsUnits, Joined(MEASURE_UNIT_NAMES));
  P('marks', apList, False, rsApiConvertMarks);
  P('marks[].id', apTarget, True, rsApiTarget);
  P('marks[].field', apText, True, rsApiMarkField);
  P('marks[].token', apWhole, True, rsApiMarkToken);
  P('marks[].role', apChoice, True, rsApiMarkRole, 'length, number');
  Method('undo', agFiles, rsApiUndo, rsApiReturnsDocument);
  Method('redo', agFiles, rsApiRedo, rsApiReturnsDocument);
  // Measurements
  Method('use_measurements', agMeasurements, rsApiUseMeasurements, rsApiReturnsDocument);
  P('path', apText, False, rsApiUseMeasurementsPath);
  P('text', apText, False, rsApiUseMeasurementsText);
  P('file', apText, False, rsApiUseMeasurementsFile);
  Method('get_measurements', agMeasurements, rsApiGetMeasurements, rsApiGetMeasurementsReturns);
  ReadsOnly;
  Method('set_measurement', agMeasurements, rsApiSetMeasurement, rsApiSetMeasurementReturns);
  P('key', apText, True, rsApiSetMeasurementKey);
  P('value', apNumber, True, rsApiSetMeasurementValue);
  P('size', apText, False, rsApiSetMeasurementSize);
  P('description', apText, False, rsApiSetMeasurementDescription);
  Method('missing_measurements', agMeasurements, rsApiMissingMeasurements, rsApiMissingReturns);
  ReadsOnly;
  // Objects
  Method('list_objects', agObjects, rsApiListObjects, rsApiListReturns);
  ReadsOnly;
  Method('get_object', agObjects, rsApiGetObject, rsApiReturnsObject);
  ReadsOnly;
  Target;
  Method('set_formula', agObjects, rsApiSetFormula, rsApiReturnsObject);
  Target;
  P('field', apText, True, rsApiSetFormulaField);
  P('formula', apText, True, rsApiSetFormulaFormula);
  Method('rename', agObjects, rsApiRename, rsApiReturnsObject);
  Target;
  P('newName', apText, True, rsApiRenameNewName);
  Method('delete', agObjects, rsApiDelete, rsApiReturnsDocument);
  Target;
  Method('set_locked', agObjects, rsApiSetLocked, rsApiReturnsObject);
  Target;
  P('locked', apFlag, True, rsApiSetLockedLocked);
  Method('add_variable', agObjects, rsApiAddVariable, rsApiReturnsObject);
  P('name', apText, True, rsApiVariableName);
  P('formula', apFormula, True, rsApiVariableFormula);
  P('description', apText, False, rsApiVariableDescription);
  Method('import_variables', agObjects, rsApiImportVariables, rsApiReturnsImportVariables);
  P('path', apText, False, rsApiImportVariablesPath);
  P('text', apText, False, rsApiImportVariablesText);
  // Drafting
  Method('add_point', agDrafting, rsApiAddPoint, rsApiReturnsObject);
  P('type', apChoice, True, rsApiTypePoint, 'freePoint, offsetPoint, alongEdgePoint, betweenPoint, intersectPoint, ' +
    'circleEdgePoint, circleCirclePoint, projectPoint');
  P('name', apText, False, rsApiNewName);
  P('...', apMembers, True, rsApiTypeMembers);
  Method('add_edge', agDrafting, rsApiAddEdge, rsApiReturnsObject);
  P('type', apChoice, True, rsApiTypeEdge, 'line, curve, curvePath, circle, arc, offsetEdge');
  P('name', apText, False, rsApiNewName);
  P('role', apChoice, False, rsApiNewEdgeRole, RoleChoices);
  P('...', apMembers, True, rsApiEdgeTypeMembers);
  Method('add_repeat', agDrafting, rsApiAddRepeat, rsApiReturnsObject);
  P('a', apReference, False, rsApiRepeatA);
  P('b', apReference, False, rsApiRepeatB);
  P('edge', apReference, False, rsApiRepeatEdge);
  P('count', apFormula, True, rsApiRepeatCount);
  P('ends', apChoice, False, rsApiRepeatEnds, 'include, exclude');
  P('name', apText, False, rsApiNewName);
  Method('split_edge', agDrafting, rsApiSplitEdge, rsApiSplitReturns);
  P('edge', apReference, True, rsApiSplitEdgeEdge);
  P('point', apReference, True, rsApiSplitEdgePoint);
  Method('add_rectangle', agDrafting, rsApiAddRectangle, rsApiRectangleReturns);
  P('corner', apReference, True, rsApiRectangleCorner);
  P('width', apFormula, True, rsApiRectangleWidth);
  P('height', apFormula, True, rsApiRectangleHeight);
  P('role', apChoice, False, rsApiNewEdgeRole, RoleChoices);
  Method('round_corner', agDrafting, rsApiRoundCorner, rsApiReturnsObject);
  P('edgeA', apReference, True, rsApiCornerEdgeA);
  P('edgeB', apReference, True, rsApiCornerEdgeB);
  P('radius', apFormula, True, rsApiCornerRadius);
  Method('feature_zip', agFeatures, rsApiInsertZip, rsApiZipReturns);
  P('edge', apReference, True, rsApiZipEdge);
  P('style', apChoice, False, rsApiZipStyle, string.Join(', ', ZIP_STYLE_NAMES));
  P('from', apChoice, False, rsApiZipFrom, 'start, end');
  P('length', apFormula, False, rsApiZipLength);
  P('allowance', apFormula, False, rsApiZipAllowance);
  P('stitch', apFormula, False, rsApiZipStitch);
  P('shieldWidth', apFormula, False, rsApiZipShield);
  Method('feature_dart', agFeatures, rsApiInsertDart, rsApiDartReturns);
  P('edge', apReference, True, rsApiDartEdge);
  P('position', apFormula, False, rsApiDartPosition);
  P('from', apChoice, False, rsApiDartFrom, 'start, end');
  P('width', apFormula, False, rsApiDartWidth);
  P('depth', apFormula, False, rsApiDartDepth);
  P('apex', apReference, False, rsApiDartApex);
  P('holeInset', apFormula, False, rsApiDartHoleInset);
  P('fold', apChoice, False, rsApiDartFold, 'start, end');
  Method('feature_hem', agFeatures, rsApiInsertHem, rsApiHemReturns);
  P('edges', apReferences, True, rsApiHemEdges);
  P('style', apChoice, False, rsApiHemStyle, string.Join(', ', HEM_STYLE_NAMES));
  P('depth', apFormula, False, rsApiHemDepth);
  P('turnUnder', apFormula, False, rsApiHemTurnUnder);
  P('stitchDistance', apFormula, False, rsApiHemStitch);
  P('notches', apFlag, False, rsApiHemNotches);
  Method('feature_facing', agFeatures, rsApiInsertFacing, rsApiFacingReturns);
  P('edges', apReferences, True, rsApiFacingEdges);
  P('width', apFormula, False, rsApiFacingWidth);
  P('aside', apFlag, False, rsApiFacingAside);
  P('interfacing', apText, False, rsApiFacingInterfacing);
  Method('feature_buttons', agFeatures, rsApiInsertButtons, rsApiButtonsReturns);
  P('edge', apReference, True, rsApiButtonsEdge);
  P('buttonsEdge', apReference, False, rsApiButtonsOtherEdge);
  P('size', apFormula, False, rsApiButtonsSize);
  P('thickness', apFormula, False, rsApiButtonsThickness);
  P('count', apFormula, False, rsApiButtonsCount);
  P('first', apFormula, False, rsApiButtonsFirst);
  P('last', apFormula, False, rsApiButtonsLast);
  P('extension', apFormula, False, rsApiButtonsExtension);
  P('direction', apChoice, False, rsApiButtonsDirection, string.Join(', ', BUTTON_DIRECTION_NAMES));
  Method('convert_edge', agDrafting, rsApiConvertEdge, rsApiReturnsObject);
  Target;
  P('to', apChoice, True, rsApiConvertEdgeTo, 'line, curve');
  Method('merge_points', agDrafting, rsApiMergePoints, rsApiMergeReturns);
  P('points', apReferences, True, rsApiArrangePoints);
  Method('break_point', agDrafting, rsApiBreakPoint, rsApiBreakReturns);
  Target;
  Method('copy_objects', agDrafting, rsApiCopyObjects, rsApiCopyReturns);
  ReadsOnly;
  P('objects', apReferences, True, rsApiCopyObjectsList);
  Method('paste_objects', agDrafting, rsApiPasteObjects, rsApiPasteReturns);
  P('fragment', apText, True, rsApiPasteFragment);
  Method('arrange', agDrafting, rsApiArrange, rsApiArrangeReturns);
  P('action', apChoice, True, rsApiArrangeAction, 'alignVertical, alignHorizontal, distribute, distributeHorizontal, ' +
    'distributeVertical, distributeAlongEdge');
  P('points', apReferences, True, rsApiArrangePoints);
  P('reference', apReference, False, rsApiArrangeReference);
  P('edge', apReference, False, rsApiArrangeEdge);
  P('replace', apReferences, False, rsApiArrangeReplace);
  Method('add_transform', agDrafting, rsApiAddTransform, rsApiReturnsObject);
  P('type', apChoice, True, rsApiTransformType, 'rotate, mirror, move');
  P('sources', apReferences, True, rsApiTransformSources);
  P('name', apText, False, rsApiTransformName);
  P('suffix', apText, False, rsApiTransformSuffix);
  P('pivot', apReference, False, rsApiTransformPivot);
  P('angle', apFormula, False, rsApiTransformAngle);
  P('axis', apGroup, False, rsApiTransformAxis);
  P('axis.edge', apReference, False, rsApiTransformAxisEdge);
  P('axis.a', apReference, False, rsApiTransformAxisA);
  P('axis.b', apReference, False, rsApiTransformAxisB);
  P('length', apFormula, False, rsApiTransformLength);
  P('dx', apFormula, False, rsApiTransformDx);
  P('dy', apFormula, False, rsApiTransformDy);
  P('rotate', apFormula, False, rsApiTransformRotate);
  Method('set_role', agDrafting, rsApiSetRole, rsApiSetRoleReturns);
  Target;
  P('role', apChoice, True, rsApiRole, RoleChoices);
  Method('set_marker', agDrafting, rsApiSetMarker, rsApiSetRoleReturns);
  Target;
  P('marker', apChoice, True, rsApiMarker, Joined(POINT_MARKER_NAMES));
  P('size', apFormula, False, rsApiMarkerSize);
  P('angle', apFormula, False, rsApiMarkerAngle);
  P('offset', apFormula, False, rsApiMarkerOffset);
  // Pieces
  Method('create_piece', agPieces, rsApiCreatePiece, rsApiReturnsPiece);
  P('x', apNumber, True, rsApiPieceX);
  P('y', apNumber, True, rsApiPieceY);
  P('name', apText, False, rsApiPieceName);
  P(PIECE_ALLOWANCE_FIELD, apFormula, False, rsApiPieceAllowance);
  Method('set_edge_allowance', agPieces, rsApiSetEdgeAllowance, rsApiReturnsPiece);
  PieceTarget;
  P('edge', apReference, True, rsApiEdgeAllowanceEdge);
  P(PIECE_ALLOWANCE_FIELD, apFormula, False, rsApiEdgeAllowance);
  Method('set_grainline', agPieces, rsApiSetGrainline, rsApiReturnsPiece);
  PieceTarget;
  P('angle', apFormula, False, rsApiGrainAngle);
  P('start', apReference, False, rsApiGrainStart);
  P('end', apReference, False, rsApiGrainEnd);
  P('none', apFlag, False, rsApiGrainNone);
  Method('add_notch', agPieces, rsApiAddNotch, rsApiReturnsPiece);
  PieceTarget;
  P('point', apReference, False, rsApiNotchPoint);
  P('edge', apReference, False, rsApiNotchEdge);
  P('position', apFormula, False, rsApiNotchPosition);
  Method('remove_notch', agPieces, rsApiRemoveNotch, rsApiReturnsPiece);
  PieceTarget;
  P('notch', apWhole, True, rsApiNotchNumber);
  Method('add_marking', agPieces, rsApiAddMarking, rsApiReturnsPiece);
  PieceTarget;
  P('kind', apChoice, True, rsApiMarkingKind, Joined(MARKING_KIND_NAMES));
  P('point', apReference, False, rsApiMarkingPoint);
  P('edge', apReference, False, rsApiMarkingEdge);
  P(MARKING_SPACING_FIELD, apFormula, False, rsApiMarkingSpacing);
  P(MARKING_SIZE_FIELD, apFormula, False, rsApiMarkingSize);
  Method('remove_marking', agPieces, rsApiRemoveMarking, rsApiReturnsPiece);
  PieceTarget;
  P('marking', apWhole, True, rsApiMarkingNumber);
  Method('set_cut', agPieces, rsApiSetCut, rsApiReturnsPiece);
  PieceTarget;
  P('count', apWhole, True, rsApiCutCount);
  P('mirrored', apFlag, False, rsApiCutMirrored);
  Method('set_fold', agPieces, rsApiSetFold, rsApiReturnsPiece);
  PieceTarget;
  P('edge', apReference, False, rsApiFoldEdge);
  P('none', apFlag, False, rsApiFoldNone);
  Method('set_dart_cap', agPieces, rsApiSetDartCap, rsApiReturnsPiece);
  PieceTarget;
  P('first', apReference, True, rsApiDartCapFirst);
  P('second', apReference, True, rsApiDartCapSecond);
  P('towards', apChoice, True, rsApiDartCapTowards, Joined(DART_PRESS_NAMES));
  Method('set_allowance_end', agPieces, rsApiSetAllowanceEnd, rsApiReturnsPiece);
  PieceTarget;
  P('edge', apReference, True, rsApiAllowanceEndEdge);
  P('end', apChoice, True, rsApiAllowanceEnd, Joined(ALLOWANCE_END_NAMES));
  Method('set_piece_material', agPieces, rsApiSetPieceMaterial, rsApiReturnsPiece);
  PieceTarget;
  P('material', apMaterial, False, rsApiPieceMaterial);
  P('none', apFlag, False, rsApiPieceMaterialNone);
  Method('set_piece_fill', agPieces, rsApiSetPieceFill, rsApiReturnsPiece);
  PieceTarget;
  P('color', apText, False, rsApiFillColor);
  P('style', apChoice, False, rsApiFillStyle, Joined(PIECE_FILL_NAMES));
  // Materials
  Method('list_materials', agMaterials, rsApiListMaterials, rsApiListMaterialsReturns);
  ReadsOnly;
  Method('add_material', agMaterials, rsApiAddMaterial, rsApiReturnsMaterials);
  P('name', apText, False, rsApiMaterialName);
  P('color', apText, False, rsApiMaterialColor);
  P('fill', apChoice, False, rsApiMaterialFill, Joined(MATERIAL_FILL_NAMES));
  P('fabric', apChoice, False, rsApiMaterialFabric, Joined(ApiFabricNames));
  Method('rename_material', agMaterials, rsApiRenameMaterial, rsApiReturnsMaterials);
  P('material', apMaterial, True, rsApiMaterial);
  P('name', apText, True, rsApiMaterialNewName);
  Method('set_material', agMaterials, rsApiSetMaterial, rsApiReturnsMaterials);
  P('material', apMaterial, True, rsApiMaterial);
  P('color', apText, False, rsApiMaterialColor);
  P('fill', apChoice, False, rsApiMaterialFill, Joined(MATERIAL_FILL_NAMES));
  P('allowance', apNumber, False, rsApiMaterialAllowance);
  P('noAllowance', apFlag, False, rsApiMaterialNoAllowance);
  P('width', apNumber, False, rsApiMaterialWidth);
  P('length', apNumber, False, rsApiMaterialLength);
  P('allowTurns', apFlag, False, rsApiMaterialAllowTurns);
  P('fabric', apChoice, False, rsApiMaterialFabric, Joined(ApiFabricNames));
  Method('delete_material', agMaterials, rsApiDeleteMaterial, rsApiReturnsMaterials);
  P('material', apMaterial, True, rsApiMaterial);
  // Seams
  Method('add_seam', agSeams, rsApiAddSeam, rsApiReturnsObject);
  P('sideA', apList, True, rsApiSideA);
  P('sideA[].piece', apReference, True, rsApiSidePiece);
  P('sideA[].edge', apReference, True, rsApiSideEdge);
  P('sideB', apList, True, rsApiSideB);
  P('sideB[].piece', apReference, True, rsApiSidePiece);
  P('sideB[].edge', apReference, True, rsApiSideEdge);
  P('name', apText, False, rsApiSeamName);
  P(SEAM_EASE_FIELD, apFormula, False, rsApiSeamEase);
  P(SEAM_TOLERANCE_FIELD, apFormula, False, rsApiSeamTolerance);
  Method('flip_seam', agSeams, rsApiFlipSeam, rsApiReturnsObject);
  Target;
  Method('suggest_seams', agSeams, rsApiSuggestSeams, rsApiSuggestReturns);
  ReadsOnly;
  // Notes
  Method('add_note', agNotes, rsApiAddNote, rsApiReturnsObject);
  P('text', apText, False, rsApiNoteText);
  P('anchor', apGroup, False, rsApiNoteAnchor);
  P('anchor.point', apReference, False, rsApiNoteAnchorPoint);
  P('anchor.edge', apReference, False, rsApiNoteAnchorEdge);
  P('anchor.piece', apReference, False, rsApiNoteAnchorPiece);
  P('anchor.position', apFormula, False, rsApiNoteAnchorPosition);
  P(NOTE_X_FIELD, apFormula, False, rsApiNoteX);
  P(NOTE_Y_FIELD, apFormula, False, rsApiNoteY);
  P(NOTE_DX_FIELD, apFormula, False, rsApiNoteDx);
  P(NOTE_DY_FIELD, apFormula, False, rsApiNoteDy);
  P('size', apNumber, False, rsApiNoteSize);
  P('print', apFlag, False, rsApiNotePrint);
  P('leader', apChoice, False, rsApiNoteLeader, Joined(NOTE_LEADER_NAMES));
  P('align', apChoice, False, rsApiNoteAlign, Joined(TEXT_ALIGN_NAMES));
  P('box', apFlag, False, rsApiNoteBox);
  P('font', apText, False, rsApiNoteFont);
  P('bold', apFlag, False, rsApiNoteBold);
  P('italic', apFlag, False, rsApiNoteItalic);
  P('name', apText, False, rsApiNoteName);
  P('svg', apText, False, rsApiNoteSvg);
  P('scale', apNumber, False, rsApiNoteScale);
  Method('set_text', agNotes, rsApiSetText, rsApiReturnsObject);
  Target;
  P('text', apText, False, rsApiNoteText);
  P('size', apNumber, False, rsApiNoteSize);
  P('print', apFlag, False, rsApiNotePrint);
  P('leader', apChoice, False, rsApiNoteLeader, Joined(NOTE_LEADER_NAMES));
  P('align', apChoice, False, rsApiNoteAlign, Joined(TEXT_ALIGN_NAMES));
  P('box', apFlag, False, rsApiNoteBox);
  P('font', apText, False, rsApiNoteFont);
  P('bold', apFlag, False, rsApiNoteBold);
  P('italic', apFlag, False, rsApiNoteItalic);
  P('svg', apText, False, rsApiNoteSvg);
  P('scale', apNumber, False, rsApiNoteScale);
  // Checking and output
  Method('evaluate', agChecking, rsApiEvaluate, rsApiEvaluateReturns);
  ReadsOnly;
  Method('check', agChecking, rsApiCheck, rsApiCheckReturns);
  ReadsOnly;
  Method('render', agChecking, rsApiRender, rsApiRenderReturns);
  ReadsOnly;
  P('format', apChoice, False, rsApiRenderFormat, 'svg, png');
  P('width', apWhole, False, rsApiRenderWidth);
  P('labels', apFlag, False, rsApiRenderLabels);
  P('hiddenRoles', apNames, False, rsApiRenderHiddenRoles, RoleChoices);
  P('annotations', apFlag, False, rsApiRenderAnnotations);
  P('region', apGroup, False, rsApiRenderRegion);
  P('region.minX', apNumber, True, rsApiRenderMin);
  P('region.minY', apNumber, True, rsApiRenderMin);
  P('region.maxX', apNumber, True, rsApiRenderMax);
  P('region.maxY', apNumber, True, rsApiRenderMax);
  P('garment', apFlag, False, rsApiRenderGarment);
  P('material', apText, False, rsApiRenderMaterial);
  Method('ui_state', agChecking, rsApiUIState, rsApiUIStateReturns);
  ReadsOnly;
  Method('export', agChecking, rsApiExport, rsApiExportReturns);
  P('layout', apText, True, rsApiExportLayout);
  P('path', apText, True, rsApiExportPath);
  P('format', apChoice, False, rsApiExportFormat, 'pdf, svg, dxf, machine-dxf');
  P('profile', apText, False, rsApiExportProfile);
  P('overwrite', apFlag, False, rsApiExportOverwrite);
end;

function ApiMethods: TApiMethodArray;
begin
  if Length(Table) = 0 then
    BuildTable;
  Result := Table;
end;

function FindApiMethod(const AName: string; out Method: TApiMethod): boolean;
var
  Candidate: TApiMethod;
begin
  Method := Default(TApiMethod);
  for Candidate in ApiMethods do
    if Candidate.Name = AName then
    begin
      Method := Candidate;
      Exit(True);
    end;
  Result := False;
end;

end.
