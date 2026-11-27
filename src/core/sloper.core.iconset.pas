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

// The icon each command shows, as a Tabler outline SVG in data/icons, and the
// commands that show them, for the Icons reference page. Kept free of the LCL
// so the docs and the tests can read it.
unit Sloper.Core.IconSet;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Shortcuts;

type
  TAppIcon = (aiNew, aiOpen, aiSave, aiSaveAs, aiMeasurements, aiPublish, aiDrape, aiExportDraft, aiQuit,
    aiUndo, aiRedo, aiCut, aiCopy, aiPaste, aiDelete,
    aiZoomIn, aiZoomOut, aiFit, aiTrueSize, aiZoomArea, aiSidePanel, aiLabels, aiPieceFills, aiAbout, aiUserGuide,
    aiSelect, aiPoint, aiLine, aiCurve, aiPiece, aiNotch, aiSeam,
    aiSplit, aiCircle, aiArc, aiRectangle, aiRoundCorner, aiOffsetLeft, aiOffsetRight, aiToLine, aiToCurve,
    aiMergePoints, aiBreakPoint, aiRepeat,
    aiHole, aiPlacement, aiStitchHoles, aiRemoveMarking,
    aiRotate, aiMirror, aiMove, aiSuggestSeams,
    // The measurements and publish apps
    aiImport, aiExport, aiCheckPattern, aiStopCheck,
    aiExportPDF, aiExportSVG, aiExportDXF, aiExportMachineDXF, aiReload, aiPrint,
    aiRulers, aiPreferences,
    // Notes
    aiText, aiAnnotations, aiCallout,
    // Overlapping pieces
    aiHidePiece, aiShowPieces, aiIsolate, aiBringToFront, aiSendToBack,
    // Locked objects
    aiLock, aiUnlock,
    // Formula suggestions
    aiWand,
    // Stepping through the objects
    aiSelectNext, aiSelectPrevious,
    // The problems drawn on the canvas
    aiProblems,
    // Dependency arrows to what reads an object
    aiDependents,
    // The side panel's tabs, those the commands above do not already give
    aiPropertiesTab, aiObjectsTab, aiGarmentTab, aiVariablesTab, aiLinesTab, aiMaterialsTab,
    aiPatternsTab, aiPiecesTab, aiInfoTab, aiClaudeTab, aiFeaturesTab);

const
  APP_ICON_NAMES: array[TAppIcon] of string = ('file-plus', 'folder-open', 'device-floppy', 'file-pencil',
    'ruler-measure', 'printer', 'hanger', 'file-type-svg', 'logout',
    'arrow-back-up', 'arrow-forward-up', 'cut', 'copy', 'clipboard', 'trash',
    'zoom-in', 'zoom-out', 'zoom-scan', 'zoom-reset', 'zoom-in-area', 'layout-sidebar-right', 'tag', 'bucket', 'info-circle', 'help-circle',
    'pointer', 'point', 'line', 'vector-bezier', 'polygon', 'triangle-inverted', 'needle-thread',
    'scissors', 'circle', 'rainbow', 'rectangle', 'border-corner-rounded', 'arrow-bar-left', 'arrow-bar-right', 'line', 'vector-bezier',
    'arrows-join', 'arrows-split', 'dots',
    'circle-dot', 'line-dashed', 'line-dotted', 'eraser',
    'rotate', 'flip-vertical', 'arrows-move', 'sparkles',
    'file-import', 'file-export', 'file-search', 'player-stop',
    'file-type-pdf', 'file-type-svg', 'file-vector', 'cut', 'refresh', 'printer',
    'ruler-2', 'settings',
    'typography', 'notes', 'message',
    'eye-off', 'eye', 'focus-2', 'stack-front', 'stack-back', 'lock', 'lock-open',
    'wand',
    'arrow-narrow-right', 'arrow-narrow-left',
    'alert-triangle', 'sitemap',
    'adjustments-horizontal', 'list-tree', 'shirt', 'variable', 'brush', 'texture',
    'files', 'puzzle', 'id-badge', 'message-question', 'components');

type
  // Where a command's icon shows: on the toolbar along the top, on the design
  // app's tools down the left of the canvas, on the side panel's tabs, only
  // in its menu, or beside a field in the properties
  TIconPlace = (ipToolbar, ipTools, ipSideTabs, ipMenu, ipProperties);

  // A command with an icon, for the Icons page
  TIconCommand = record
    Icon: TAppIcon;
    App: TShortcutApp;
    Place: TIconPlace;
    Name: string;
    // The menu it is in, such as "Tools → Edge", or '' when it is in none
    Menu: string;
    // As Sloper.Core.Shortcuts writes them, or '' when it has none
    Keys: string;
    Description: string;
  end;

  TIconCommandArray = array of TIconCommand;

function IconFileName(const Dir: string; Icon: TAppIcon): string;
// Tabler draws in currentColor; this gives it Color, such as #202020
function TintedSVG(const Text, Color: string): string;
// Every command the apps show an icon for, by app, in the order they show
// them. Kept by hand beside the main forms; the tests check every icon is in it.
function IconCommands: TIconCommandArray;

resourcestring
  rsIconMenuFile = 'File';
  rsIconMenuFileMeasurements = 'File → Measurements';
  rsIconMenuEdit = 'Edit';
  rsIconMenuView = 'View';
  rsIconMenuViewLabels = 'View → Labels';
  rsIconMenuTools = 'Tools';
  rsIconMenuToolsEdge = 'Tools → Edge';
  rsIconMenuToolsOffset = 'Tools → Offset';
  rsIconMenuToolsPoints = 'Tools → Points';
  rsIconMenuToolsMarkings = 'Tools → Markings';
  rsIconMenuToolsTransform = 'Tools → Transform';
  rsIconMenuHelp = 'Help';
  rsIconMenuPieces = 'Pieces';

  rsIconNew = 'New';
  rsIconOpen = 'Open…';
  rsIconSave = 'Save';
  rsIconSaveAs = 'Save As…';
  rsIconQuit = 'Quit';
  rsIconUndo = 'Undo';
  rsIconRedo = 'Redo';
  rsIconPreferences = 'Preferences…';
  rsIconProfiles = 'Output and Machine Profiles…';
  rsIconZoomIn = 'Zoom In';
  rsIconZoomOut = 'Zoom Out';
  rsIconUserGuide = 'User Guide';
  rsIconAbout = 'About';
  rsIconNewSet = 'New Set…';
  rsIconOpenSet = 'Open Set…';
  rsIconEditSet = 'Edit in Measurements App…';
  rsIconPublish = 'Publish…';
  rsIconDrape = 'Drape…';
  rsIconExportDraft = 'Export Draft SVG…';
  rsIconCut = 'Cut';
  rsIconCopy = 'Copy';
  rsIconPaste = 'Paste';
  rsIconDelete = 'Delete';
  rsIconSelectNext = 'Select Next';
  rsIconSelectPrevious = 'Select Previous';
  rsIconLock = 'Lock';
  rsIconUnlock = 'Unlock';
  rsIconMaterials = 'Materials…';
  rsIconFitPattern = 'Fit Pattern';
  rsIconTrueSize = 'True Size';
  rsIconSidePanel = 'Side Panel';
  rsIconRulers = 'Rulers';
  rsIconLabels = 'Labels';
  rsIconPieceFills = 'Piece Fills';
  rsIconAnnotations = 'Annotations';
  rsIconHidePiece = 'Hide Piece';
  rsIconShowPieces = 'Show All Pieces';
  rsIconIsolate = 'Isolate Piece';
  rsIconBringToFront = 'Bring to Front';
  rsIconSendToBack = 'Send to Back';
  rsIconProblems = 'Problems';
  rsIconDependents = 'Dependents';
  rsIconSelect = 'Select';
  rsIconZoom = 'Zoom';
  rsIconPoint = 'Point';
  rsIconLine = 'Line';
  rsIconCurve = 'Curve';
  rsIconCircle = 'Circle';
  rsIconRectangle = 'Rectangle';
  rsIconPiece = 'Piece';
  rsIconNotch = 'Notch';
  rsIconSeam = 'Seam';
  rsIconText = 'Text';
  rsIconCallout = 'Callout';
  rsIconArc = 'Arc';
  rsIconSplit = 'Split Edge';
  rsIconRoundCorner = 'Round Corner';
  rsIconToLine = 'Change to Line';
  rsIconToCurve = 'Change to Curve';
  rsIconOffsetLeft = 'Offset Edge Left';
  rsIconOffsetRight = 'Offset Edge Right';
  rsIconOffsetInside = 'Offset Inside Piece';
  rsIconOffsetOutside = 'Offset Outside Piece';
  rsIconMerge = 'Merge Points';
  rsIconBreak = 'Break Point';
  rsIconRepeat = 'Repeat Points';
  rsIconHole = 'Mark Hole';
  rsIconAttachLine = 'Attach Marking to Piece';
  rsIconStitch = 'Mark Stitch Holes';
  rsIconRemoveMarking = 'Remove Marking';
  rsIconRotate = 'Rotate Copy…';
  rsIconMirror = 'Mirror Copy…';
  rsIconMove = 'Move Copy…';
  rsIconSuggestSeams = 'Suggest Seams…';
  rsIconSuggestFormula = 'Suggest formulas';
  rsIconImport = 'Import…';
  rsIconExport = 'Export…';
  rsIconCheck = 'Check Against Pattern…';
  rsIconStopCheck = 'Stop Checking';
  rsIconExportPDF = 'Export PDF…';
  rsIconExportSVG = 'Export SVG…';
  rsIconExportDXF = 'Export DXF…';
  rsIconExportMachineDXF = 'Export Machine DXF…';
  rsIconPrint = 'Print…';
  rsIconFitPages = 'Fit Pages';
  rsIconZoomArea = 'Zoom Area';
  rsIconReload = 'Reload Patterns';

  rsIconNewPatternText = 'Start a new pattern';
  rsIconOpenPatternText = 'Open a pattern';
  rsIconSaveText = 'Save the file';
  rsIconSaveAsText = 'Save the file under another name';
  rsIconQuitText = 'Close the app';
  rsIconUndoText = 'Take back the last change';
  rsIconRedoText = 'Make the change undone again';
  rsIconPreferencesText = 'Settings for every pattern: units, colours, the canvas';
  rsIconProfilesText = 'Add, rename and edit your output and machine profiles';
  rsIconUserGuideText = 'Open this guide';
  rsIconAboutText = 'The version and licence';
  rsIconNewSetText = 'Start a measurement set for the pattern';
  rsIconOpenSetText = 'Choose the measurement set the pattern is drafted from';
  rsIconEditSetText = 'Open the measurement set in the measurements app, checked against the pattern';
  rsIconPublishText = 'Lay out and print the pattern in the publish app';
  rsIconDrapeText = 'Place the pattern''s pieces on a body in the drape app, for draping in Blender';
  rsIconExportDraftText = 'Save the draft as an SVG drawing, as it shows on the canvas';
  rsIconCutText = 'Copy the selection and delete it';
  rsIconCopyText = 'Copy the selection, to paste in this or another pattern';
  rsIconPasteText = 'Paste what was copied, as new objects';
  rsIconDeleteText = 'Delete the selection';
  rsIconSelectNextText = 'Select the next object the Objects tab lists';
  rsIconSelectPreviousText = 'Select the object before';
  rsIconLockText = 'Stop the selected objects being moved, edited or deleted';
  rsIconUnlockText = 'Let the selected objects be changed again';
  rsIconMaterialsText = 'The materials pieces are cut from, with their colours and allowances';
  rsIconZoomInText = 'Zoom in a step';
  rsIconZoomOutText = 'Zoom out a step';
  rsIconFitPatternText = 'Fit the whole pattern in the window';
  rsIconTrueSizeText = 'Show the pattern at its real size on screen';
  rsIconSidePanelText = 'Show or hide the side panel';
  rsIconRulersText = 'Show or hide the rulers';
  rsIconLabelsText = 'Which names show: where they help, all, or none';
  rsIconPieceFillsText = 'Show or hide the pieces'' colours';
  rsIconAnnotationsText = 'Show or hide the notes';
  rsIconHidePieceText = 'Take the selected pieces off the canvas, with what only they use';
  rsIconShowPiecesText = 'Bring every hidden piece back';
  rsIconIsolateText = 'Work on the selected piece alone, the rest shown faintly';
  rsIconBringToFrontText = 'Draw the selected pieces over the others';
  rsIconSendToBackText = 'Draw the selected pieces under the others';
  rsIconTabProperties = 'Properties';
  rsIconTabObjects = 'Objects';
  rsIconTabGarment = 'Garment';
  rsIconTabVariables = 'Variables';
  rsIconTabMeasurements = 'Measurements';
  rsIconTabLines = 'Lines';
  rsIconTabMaterials = 'Materials';
  rsIconTabFeatures = 'Features';
  rsIconTabClaude = 'Claude';
  rsIconTabProblems = 'Problems';
  rsIconTabPatterns = 'Patterns';
  rsIconTabPieces = 'Pieces';
  rsIconTabInfo = 'Information Block';
  rsIconTabNotes = 'Notes';
  rsIconTabOutput = 'Output';
  rsIconTabPropertiesText = 'The selected object''s formulas and settings';
  rsIconTabObjectsText = 'Every object in the pattern, to find, filter and select';
  rsIconTabGarmentText = 'The pieces as they will look sewn, in their materials';
  rsIconTabVariablesText = 'The pattern''s own variables, to add and edit';
  rsIconTabMeasurementsText = 'The measurements the pattern reads, from its measurement file';
  rsIconTabLinesText = 'Which kinds of line are shown';
  rsIconTabMaterialsText = 'The materials pieces are cut from';
  rsIconTabFeaturesText = 'Sewing details to apply in one step, such as a zip along a piece''s edge';
  rsIconTabClaudeText = 'Ask Claude about the pattern, or to change it';
  rsIconTabProblemsText = 'Every problem in the pattern; choose one to select what it is about';
  rsIconTabPatternsText = 'The patterns the layout is made from';
  rsIconTabPiecesText = 'The selected piece, placing and packing pieces, and the tray of pieces not yet placed';
  rsIconTabPublishMaterialsText = 'How much of each material the patterns need';
  rsIconTabInfoText = 'The pattern, measurements, date and other details printed in a page corner';
  rsIconTabNotesText = 'Text placed on the pages';
  rsIconTabOutputText = 'What the layout prints on, the paper, marks and profiles, and the exports';
  rsIconTabPublishProblemsText = 'What stops the layout printing, and the warnings; choose one to select its piece or note';
  rsIconProblemsText = 'Mark the objects with problems on the canvas; pointing at one says what is wrong';
  rsIconDependentsText = 'Arrows from the hovered or selected object also go to what reads it, not only to what it reads';
  rsIconSelectText = 'Select points, edges and pieces; drag to move points';
  rsIconZoomText = 'Zoom in a step; Shift and click zooms out, and dragging a box zooms to it';
  rsIconPointText = 'Add a point';
  rsIconLineText = 'Draw a straight edge between two points';
  rsIconCurveText = 'Draw a curved edge between two points';
  rsIconCircleText = 'Draw a circle from its centre and a point on it';
  rsIconRectangleText = 'Draw a rectangle from one corner to the opposite one';
  rsIconPieceText = 'Make a piece from the closed outline around the click';
  rsIconNotchText = 'Add a notch on a piece''s edge, or remove one';
  rsIconSeamText = 'Pick the edges of two pieces that are sewn together';
  rsIconTextText = 'Add a note';
  rsIconCalloutText = 'Add a note with a line to what it is about';
  rsIconArcText = 'Draw an arc around the selected point';
  rsIconSplitText = 'Split an edge in two at a point on it';
  rsIconRoundCornerText = 'Round the corner where two selected edges meet';
  rsIconToLineText = 'Make the selected curve a straight line';
  rsIconToCurveText = 'Make the selected line a curve';
  rsIconOffsetLeftText = 'A line following the selected edges, at a distance on their left';
  rsIconOffsetRightText = 'A line following the selected edges, at a distance on their right';
  rsIconOffsetInsideText = 'A line following the selected edges, inside the selected piece';
  rsIconOffsetOutsideText = 'A line following the selected edges, outside the selected piece';
  rsIconMergeText = 'Make the selected points one, which everything that used them then uses';
  rsIconBreakText = 'Give each edge that meets at the selected point a point of its own';
  rsIconRepeatText = 'A row of evenly spaced points between two points or along an edge';
  rsIconHoleText = 'Put a hole, button or match dot marker on the selected point';
  rsIconAttachLineText = 'Add the selected line to a piece as a marking';
  rsIconStitchText = 'Mark stitch holes along the selected edge';
  rsIconRemoveMarkingText = 'Take the selected marking off its piece';
  rsIconRotateText = 'Copies of the selection turned about a point, which follow it';
  rsIconMirrorText = 'Copies of the selection reflected in a line, which follow it';
  rsIconMoveText = 'Copies of the selection moved aside, which follow it';
  rsIconSuggestSeamsText = 'List edges of different pieces that look sewn together, to make seams';
  rsIconSuggestFormulaText = 'Beside a formula: formulas that give its value, from the measurements';
  rsIconNewSetFileText = 'Start a measurement set';
  rsIconOpenSetFileText = 'Open a measurement set';
  rsIconImportText = 'Import a Valentina or Seamly2D measurement file';
  rsIconExportText = 'Export the set as a Valentina or Seamly2D file';
  rsIconCheckText = 'Show what a pattern needs that the set does not have';
  rsIconStopCheckText = 'Close the pattern the set is being checked against';
  rsIconOpenLayoutText = 'Open a layout';
  rsIconNewDrapeText = 'Start a drape file from a pattern, every piece placed by a guess';
  rsIconOpenDrapeText = 'Open a drape file';
  rsIconFitBody = 'Fit Body';
  rsIconFitBodyText = 'Show the whole body and every piece';
  rsIconReloadDrapeText = 'Read the patterns and the body''s measurements again';
  rsIconGuess = 'Guess Placements';
  rsIconGuessText = 'Place every piece not yet placed where it would likely go';
  rsIconFlipPiece = 'Flip';
  rsIconFlipPieceText = 'Turn the selected piece round to face the other way';
  rsIconUnplace = 'Unplace';
  rsIconUnplaceText = 'Take the selected piece off the body, so it is left out';
  rsIconTabDrapePatternsText = 'The patterns placed, and the body they are placed on';
  rsIconTabDrapePiecesText = 'Every piece, placed or not; choose one to select it';
  rsIconTabDrapePropertiesText = 'Where the selected piece is placed and how it is turned';
  rsIconTabDrapeProblemsText = 'Pieces left out, pieces gone and files that cannot be read; choose one to select its piece';
  rsIconExportPDFText = 'Export the layout as a PDF';
  rsIconExportSVGText = 'Export the layout as SVG: true size, pieces where they lie';
  rsIconExportDXFText = 'Export the layout as DXF-AAMA, for pattern software';
  rsIconExportMachineDXFText = 'Export DXF for a cutting machine, on its profile''s layers';
  rsIconPrintText = 'Print the layout';
  rsIconFitPagesText = 'Fit every page in the window';
  rsIconZoomAreaText = 'Drag a box to zoom to it';
  rsIconReloadText = 'Read the patterns again';

implementation

uses
  SysUtils;

function IconFileName(const Dir: string; Icon: TAppIcon): string;
begin
  Result := ConcatPaths([Dir, APP_ICON_NAMES[Icon] + '.svg']);
end;

function TintedSVG(const Text, Color: string): string;
begin
  Result := StringReplace(Text, 'currentColor', Color, [rfReplaceAll]);
end;

function IconCommands: TIconCommandArray;
var
  App: TShortcutApp;
  Place: TIconPlace;
  Menu: string;

  procedure Add(Icon: TAppIcon; const AName, Description: string);
  var
    Command: TIconCommand;
  begin
    Command.Icon := Icon;
    Command.App := App;
    Command.Place := Place;
    Command.Name := AName;
    Command.Menu := Menu;
    Command.Keys := '';
    Command.Description := Description;
    Insert(Command, Result, Length(Result));
  end;

  procedure AddKey(Icon: TAppIcon; const AName: string; Key: TKeyCommand; const Description: string);
  begin
    Add(Icon, AName, Description);
    Result[High(Result)].Keys := ShortcutInfo(Key).Keys;
  end;

  procedure Start(AApp: TShortcutApp; APlace: TIconPlace; const AMenu: string);
  begin
    App := AApp;
    Place := APlace;
    Menu := AMenu;
  end;

begin
  Result := nil;
  // The design app's toolbar, then its tools, then commands in menus only
  Start(saDesign, ipToolbar, rsIconMenuFile);
  AddKey(aiNew, rsIconNew, kcNew, rsIconNewPatternText);
  AddKey(aiOpen, rsIconOpen, kcOpen, rsIconOpenPatternText);
  AddKey(aiSave, rsIconSave, kcSave, rsIconSaveText);
  Menu := rsIconMenuEdit;
  AddKey(aiUndo, rsIconUndo, kcUndo, rsIconUndoText);
  AddKey(aiRedo, rsIconRedo, kcRedo, rsIconRedoText);
  AddKey(aiDelete, rsIconDelete, kcDelete, rsIconDeleteText);
  Menu := rsIconMenuView;
  AddKey(aiZoomIn, rsIconZoomIn, kcZoomIn, rsIconZoomInText);
  AddKey(aiZoomOut, rsIconZoomOut, kcZoomOut, rsIconZoomOutText);
  AddKey(aiFit, rsIconFitPattern, kcFit, rsIconFitPatternText);
  AddKey(aiTrueSize, rsIconTrueSize, kcTrueSize, rsIconTrueSizeText);
  Menu := rsIconMenuFileMeasurements;
  AddKey(aiMeasurements, rsIconOpenSet, kcOpenMeasurements, rsIconOpenSetText);
  Menu := rsIconMenuFile;
  AddKey(aiPublish, rsIconPublish, kcPublish, rsIconPublishText);
  AddKey(aiDrape, rsIconDrape, kcDrape, rsIconDrapeText);
  Add(aiExportDraft, rsIconExportDraft, rsIconExportDraftText);

  Start(saDesign, ipTools, rsIconMenuTools);
  AddKey(aiSelect, rsIconSelect, kcToolSelect, rsIconSelectText);
  AddKey(aiZoomArea, rsIconZoom, kcToolZoom, rsIconZoomText);
  AddKey(aiPoint, rsIconPoint, kcToolPoint, rsIconPointText);
  AddKey(aiLine, rsIconLine, kcToolLine, rsIconLineText);
  AddKey(aiCurve, rsIconCurve, kcToolCurve, rsIconCurveText);
  AddKey(aiCircle, rsIconCircle, kcToolCircle, rsIconCircleText);
  AddKey(aiRectangle, rsIconRectangle, kcToolRectangle, rsIconRectangleText);
  AddKey(aiPiece, rsIconPiece, kcToolPiece, rsIconPieceText);
  AddKey(aiNotch, rsIconNotch, kcToolNotch, rsIconNotchText);
  AddKey(aiSeam, rsIconSeam, kcToolSeam, rsIconSeamText);
  AddKey(aiText, rsIconText, kcToolText, rsIconTextText);
  AddKey(aiCallout, rsIconCallout, kcToolCallout, rsIconCalloutText);
  Add(aiArc, rsIconArc, rsIconArcText);
  Menu := rsIconMenuToolsEdge;
  Add(aiSplit, rsIconSplit, rsIconSplitText);
  Add(aiRoundCorner, rsIconRoundCorner, rsIconRoundCornerText);
  Menu := rsIconMenuToolsOffset;
  Add(aiOffsetLeft, rsIconOffsetLeft, rsIconOffsetLeftText);
  Add(aiOffsetRight, rsIconOffsetRight, rsIconOffsetRightText);
  Menu := rsIconMenuToolsPoints;
  Add(aiMergePoints, rsIconMerge, rsIconMergeText);
  Add(aiBreakPoint, rsIconBreak, rsIconBreakText);
  Add(aiRepeat, rsIconRepeat, rsIconRepeatText);
  Menu := rsIconMenuToolsMarkings;
  Add(aiHole, rsIconHole, rsIconHoleText);
  Add(aiPlacement, rsIconAttachLine, rsIconAttachLineText);
  Add(aiStitchHoles, rsIconStitch, rsIconStitchText);
  Add(aiRemoveMarking, rsIconRemoveMarking, rsIconRemoveMarkingText);
  Menu := rsIconMenuToolsTransform;
  Add(aiRotate, rsIconRotate, rsIconRotateText);
  Add(aiMirror, rsIconMirror, rsIconMirrorText);
  Add(aiMove, rsIconMove, rsIconMoveText);
  Menu := rsIconMenuTools;
  Add(aiSuggestSeams, rsIconSuggestSeams, rsIconSuggestSeamsText);

  Start(saDesign, ipSideTabs, '');
  Add(aiPropertiesTab, rsIconTabProperties, rsIconTabPropertiesText);
  Add(aiObjectsTab, rsIconTabObjects, rsIconTabObjectsText);
  Add(aiGarmentTab, rsIconTabGarment, rsIconTabGarmentText);
  Add(aiVariablesTab, rsIconTabVariables, rsIconTabVariablesText);
  Add(aiMeasurements, rsIconTabMeasurements, rsIconTabMeasurementsText);
  Add(aiLinesTab, rsIconTabLines, rsIconTabLinesText);
  Add(aiMaterialsTab, rsIconTabMaterials, rsIconTabMaterialsText);
  Add(aiFeaturesTab, rsIconTabFeatures, rsIconTabFeaturesText);
  Add(aiClaudeTab, rsIconTabClaude, rsIconTabClaudeText);
  Add(aiProblems, rsIconTabProblems, rsIconTabProblemsText);

  Start(saDesign, ipMenu, rsIconMenuFile);
  AddKey(aiSaveAs, rsIconSaveAs, kcSaveAs, rsIconSaveAsText);
  AddKey(aiQuit, rsIconQuit, kcQuit, rsIconQuitText);
  Menu := rsIconMenuFileMeasurements;
  Add(aiNew, rsIconNewSet, rsIconNewSetText);
  Add(aiOpen, rsIconEditSet, rsIconEditSetText);
  Menu := rsIconMenuEdit;
  AddKey(aiCut, rsIconCut, kcCut, rsIconCutText);
  AddKey(aiCopy, rsIconCopy, kcCopy, rsIconCopyText);
  AddKey(aiPaste, rsIconPaste, kcPaste, rsIconPasteText);
  AddKey(aiSelectNext, rsIconSelectNext, kcSelectNext, rsIconSelectNextText);
  AddKey(aiSelectPrevious, rsIconSelectPrevious, kcSelectPrevious, rsIconSelectPreviousText);
  Add(aiLock, rsIconLock, rsIconLockText);
  Add(aiUnlock, rsIconUnlock, rsIconUnlockText);
  Add(aiPieceFills, rsIconMaterials, rsIconMaterialsText);
  AddKey(aiPreferences, rsIconPreferences, kcPreferences, rsIconPreferencesText);
  Menu := rsIconMenuView;
  Add(aiSidePanel, rsIconSidePanel, rsIconSidePanelText);
  AddKey(aiRulers, rsIconRulers, kcRulers, rsIconRulersText);
  Add(aiLabels, rsIconLabels, rsIconLabelsText);
  Add(aiPieceFills, rsIconPieceFills, rsIconPieceFillsText);
  Add(aiAnnotations, rsIconAnnotations, rsIconAnnotationsText);
  Add(aiHidePiece, rsIconHidePiece, rsIconHidePieceText);
  Add(aiShowPieces, rsIconShowPieces, rsIconShowPiecesText);
  Add(aiIsolate, rsIconIsolate, rsIconIsolateText);
  Add(aiBringToFront, rsIconBringToFront, rsIconBringToFrontText);
  Add(aiSendToBack, rsIconSendToBack, rsIconSendToBackText);
  Add(aiProblems, rsIconProblems, rsIconProblemsText);
  Add(aiDependents, rsIconDependents, rsIconDependentsText);
  // On the menu only, as on the toolbar they would look like the Line and
  // Curve tools and the two offsets
  Menu := rsIconMenuToolsEdge;
  Add(aiToLine, rsIconToLine, rsIconToLineText);
  Add(aiToCurve, rsIconToCurve, rsIconToCurveText);
  Menu := rsIconMenuToolsOffset;
  Add(aiOffsetRight, rsIconOffsetInside, rsIconOffsetInsideText);
  Add(aiOffsetLeft, rsIconOffsetOutside, rsIconOffsetOutsideText);
  Menu := rsIconMenuHelp;
  Add(aiUserGuide, rsIconUserGuide, rsIconUserGuideText);
  Add(aiAbout, rsIconAbout, rsIconAboutText);

  Start(saDesign, ipProperties, '');
  Add(aiWand, rsIconSuggestFormula, rsIconSuggestFormulaText);

  Start(saMeasurements, ipToolbar, rsIconMenuFile);
  AddKey(aiNew, rsIconNew, kcNew, rsIconNewSetFileText);
  AddKey(aiOpen, rsIconOpen, kcOpen, rsIconOpenSetFileText);
  AddKey(aiSave, rsIconSave, kcSave, rsIconSaveText);
  Menu := rsIconMenuEdit;
  AddKey(aiUndo, rsIconUndo, kcUndo, rsIconUndoText);
  AddKey(aiRedo, rsIconRedo, kcRedo, rsIconRedoText);
  Menu := rsIconMenuFile;
  AddKey(aiImport, rsIconImport, kcImport, rsIconImportText);
  AddKey(aiExport, rsIconExport, kcExportMeasurements, rsIconExportText);
  Add(aiCheckPattern, rsIconCheck, rsIconCheckText);

  Start(saMeasurements, ipMenu, rsIconMenuFile);
  AddKey(aiSaveAs, rsIconSaveAs, kcSaveAs, rsIconSaveAsText);
  Add(aiStopCheck, rsIconStopCheck, rsIconStopCheckText);
  AddKey(aiQuit, rsIconQuit, kcQuit, rsIconQuitText);
  Menu := rsIconMenuEdit;
  AddKey(aiPreferences, rsIconPreferences, kcPreferences, rsIconPreferencesText);
  Menu := rsIconMenuHelp;
  Add(aiUserGuide, rsIconUserGuide, rsIconUserGuideText);
  Add(aiAbout, rsIconAbout, rsIconAboutText);

  Start(saPublish, ipToolbar, rsIconMenuFile);
  AddKey(aiOpen, rsIconOpen, kcOpen, rsIconOpenLayoutText);
  AddKey(aiSave, rsIconSave, kcSave, rsIconSaveText);
  Menu := rsIconMenuEdit;
  AddKey(aiUndo, rsIconUndo, kcUndo, rsIconUndoText);
  AddKey(aiRedo, rsIconRedo, kcRedo, rsIconRedoText);
  Menu := rsIconMenuView;
  AddKey(aiZoomIn, rsIconZoomIn, kcZoomIn, rsIconZoomInText);
  AddKey(aiZoomOut, rsIconZoomOut, kcZoomOut, rsIconZoomOutText);
  AddKey(aiFit, rsIconFitPages, kcFit, rsIconFitPagesText);
  AddKey(aiZoomArea, rsIconZoomArea, kcToolZoom, rsIconZoomAreaText);
  AddKey(aiReload, rsIconReload, kcReload, rsIconReloadText);
  Menu := rsIconMenuFile;
  AddKey(aiPrint, rsIconPrint, kcPrint, rsIconPrintText);
  AddKey(aiExportPDF, rsIconExportPDF, kcExportPDF, rsIconExportPDFText);
  Add(aiExportSVG, rsIconExportSVG, rsIconExportSVGText);
  Add(aiExportDXF, rsIconExportDXF, rsIconExportDXFText);
  Add(aiExportMachineDXF, rsIconExportMachineDXF, rsIconExportMachineDXFText);

  Start(saPublish, ipSideTabs, '');
  Add(aiPatternsTab, rsIconTabPatterns, rsIconTabPatternsText);
  Add(aiPiecesTab, rsIconTabPieces, rsIconTabPiecesText);
  Add(aiMaterialsTab, rsIconTabMaterials, rsIconTabPublishMaterialsText);
  Add(aiInfoTab, rsIconTabInfo, rsIconTabInfoText);
  Add(aiAnnotations, rsIconTabNotes, rsIconTabNotesText);
  Add(aiPrint, rsIconTabOutput, rsIconTabOutputText);
  Add(aiProblems, rsIconTabProblems, rsIconTabPublishProblemsText);

  Start(saPublish, ipMenu, rsIconMenuFile);
  AddKey(aiSaveAs, rsIconSaveAs, kcSaveAs, rsIconSaveAsText);
  AddKey(aiQuit, rsIconQuit, kcQuit, rsIconQuitText);
  Menu := rsIconMenuEdit;
  AddKey(aiPreferences, rsIconPreferences, kcPreferences, rsIconPreferencesText);
  Add(aiPreferences, rsIconProfiles, rsIconProfilesText);
  Menu := rsIconMenuHelp;
  Add(aiUserGuide, rsIconUserGuide, rsIconUserGuideText);
  Add(aiAbout, rsIconAbout, rsIconAboutText);

  Start(saDrape, ipToolbar, rsIconMenuFile);
  AddKey(aiNew, rsIconNew, kcNew, rsIconNewDrapeText);
  AddKey(aiOpen, rsIconOpen, kcOpen, rsIconOpenDrapeText);
  AddKey(aiSave, rsIconSave, kcSave, rsIconSaveText);
  Menu := rsIconMenuEdit;
  AddKey(aiUndo, rsIconUndo, kcUndo, rsIconUndoText);
  AddKey(aiRedo, rsIconRedo, kcRedo, rsIconRedoText);
  Menu := rsIconMenuView;
  AddKey(aiZoomIn, rsIconZoomIn, kcZoomIn, rsIconZoomInText);
  AddKey(aiZoomOut, rsIconZoomOut, kcZoomOut, rsIconZoomOutText);
  AddKey(aiFit, rsIconFitBody, kcFit, rsIconFitBodyText);
  AddKey(aiReload, rsIconReload, kcReload, rsIconReloadDrapeText);
  Menu := rsIconMenuPieces;
  AddKey(aiWand, rsIconGuess, kcGuessPlacements, rsIconGuessText);
  Add(aiMirror, rsIconFlipPiece, rsIconFlipPieceText);
  AddKey(aiDelete, rsIconUnplace, kcUnplacePiece, rsIconUnplaceText);

  Start(saDrape, ipSideTabs, '');
  Add(aiPatternsTab, rsIconTabPatterns, rsIconTabDrapePatternsText);
  Add(aiPiecesTab, rsIconTabPieces, rsIconTabDrapePiecesText);
  Add(aiPropertiesTab, rsIconTabProperties, rsIconTabDrapePropertiesText);
  Add(aiProblems, rsIconTabProblems, rsIconTabDrapeProblemsText);

  Start(saDrape, ipMenu, rsIconMenuFile);
  AddKey(aiSaveAs, rsIconSaveAs, kcSaveAs, rsIconSaveAsText);
  AddKey(aiQuit, rsIconQuit, kcQuit, rsIconQuitText);
  Menu := rsIconMenuEdit;
  AddKey(aiPreferences, rsIconPreferences, kcPreferences, rsIconPreferencesText);
  Menu := rsIconMenuHelp;
  Add(aiUserGuide, rsIconUserGuide, rsIconUserGuideText);
  Add(aiAbout, rsIconAbout, rsIconAboutText);
end;

end.
