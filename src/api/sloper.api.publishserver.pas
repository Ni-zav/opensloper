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

// The web Publish app's methods, named publish_: a layout opened from files
// given as text, as the browser has no disk, and the files its sources still
// need, by their paths from the layout. The page finds those among the files
// the user chose and gives them. The web engine's editor server answers these
// methods (TEditorApiServer). No LCL dependency.
unit Sloper.API.PublishServer;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpjson, Sloper.Core.PatternSources, Sloper.API.Methods, Sloper.API.LayoutServer, Sloper.Output.LayoutDocument, Sloper.Output.Preview;

const
  PUBLISH_PREFIX = 'publish_';

type
  TPublishApiServer = class
  private
    FDocument: TLayoutDocument;
    FLayoutServer: TLayoutApiServer;
    // What a press on the pages holds, to drag
    FDrag: TPreviewDrag;
    procedure AddFiles(Params: TJSONObject);
    function DoOpen(Params: TJSONObject): TJSONData;
    function DoAddFiles(Params: TJSONObject): TJSONData;
    function DoState: TJSONData;
    function DoScene: TJSONData;
    function DoPress(Params: TJSONObject): TJSONData;
    function DoDrag(Params: TJSONObject): TJSONData;
    function DoDropCopy(Params: TJSONObject): TJSONData;
    function DoPieceEdit(const Method: string; Params: TJSONObject): TJSONData;
    function DoPlaceCopy(Params: TJSONObject): TJSONData;
    function SourceParam(Params: TJSONObject): TPatternSource;
    function DoPatterns: TJSONData;
    function DoAddPattern(Params: TJSONObject): TJSONData;
    function DoSetMeasurements(Params: TJSONObject): TJSONData;
    function DoSetSize(Params: TJSONObject): TJSONData;
    function DoOutput: TJSONData;
    function DoSetOutput(Params: TJSONObject): TJSONData;
    function DoTogglePage(Params: TJSONObject): TJSONData;
    function NoteParam(Params: TJSONObject): integer;
    function DoNote(Params: TJSONObject): TJSONData;
    function DoSetNote(Params: TJSONObject): TJSONData;
    function DoMaterials: TJSONData;
    function DoTitle: TJSONData;
    function DoSetTitle(Params: TJSONObject): TJSONData;
    function DoSave: TJSONData;
    function DoExport(Params: TJSONObject): TJSONData;
  public
    constructor Create;
    destructor Destroy; override;
    // Runs a method, by its full name; raises EApiError when it is refused.
    // The reply is the caller's.
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData;
    property Document: TLayoutDocument read FDocument;
  end;

// The Publish app's methods, documented as the API's are
function PublishMethods: TApiMethodArray;

resourcestring
  rsPublishOpen = 'Opens a layout from its file''s text, or starts one for a pattern with every piece placed, as the ' +
    'desktop''s Open does. The sources are read from the files given, not disk.';
  rsPublishFiles = 'The files the layout''s sources read, each with its path from the layout and its text';
  rsPublishFilePath = 'The file''s path from the layout, with /';
  rsPublishFileText = 'The file''s text';
  rsPublishLayout = 'The layout file''s text';
  rsPublishPattern = 'Without a layout, the path of the pattern among the files to start a layout for';
  rsPublishAddFiles = 'Gives more files, as those named in `missing`, and reads the sources again. Not an undo step.';
  rsPublishState = 'The layout, as layout_state gives it, with the files still needed.';
  rsPublishStateReturns = 'What layout_state gives, with `missing`: the paths, from the layout, of the files sources ' +
    'need and were not given; `tray`: the copies waiting to be placed, each with its `caption` and whether it ' +
    '`canPlace`; and `summary`, what the status bar says of the pages or sheet';
  rsPublishNeedsSource = 'Give a layout, or the pattern to start one for';
  rsPublishScene = 'What the preview shows, in layout mm with y down, as the desktop''s preview draws it.';
  rsPublishSceneReturns = '`tiled`, true for tiled pages; `cover`, the tiled print''s cover (minX, minY, maxX, maxY) or ' +
    'null; `notes`, the sheet notes, and `pieceNotes`, the pattern notes printing with the pieces, each with its ' +
    '`lines` (fields filled in), `size`, `lineHeight`, `align`, `boxed`, `font`, `bold`, `italic`, `box` and `frame` ' +
    '(each [minX, minY, maxX, maxY]), ' +
    '`leader` and its `leaderStrokes`, and its `stamp` paths for a drawing; `pages`, each with its `caption`, its area and whether it is `blank` or `excluded`; `pieces`, each with '
    +
    'its `placement` index, `caption`, `fillColor` (empty when not filled), `cutLine` and `seamLine` (flat lists of ' +
    'x, y), `marks` (flat segments), `lines` (each with flat `points` and `dashed`) and `label` (x, y), or null when ' +
    'labels are left out; `titleBoxes`, the information block''s boxes; `title`, its `lines`, text `size`, ' +
    '`lineHeight` and `padding` in mm';
  rsPublishPress = 'A press on the pages: finds the sheet note at a point of the layout, which lies over pieces, or ' +
    'else the smallest placed piece, and holds it for publish_drag. Changes nothing.';
  rsPublishPressReturns = '`placement`, the piece''s placement index, and `note`, the note''s index; -1 for none';
  rsPublishDrag = 'Moves what publish_press holds so the point pressed follows this one, on the 0.5 mm grid. The ' +
    'first move opens one undo step, which publish_release ends.';
  rsPublishDragReturns = '`moving`, false when nothing is held, as when an undo took it';
  rsPublishRelease = 'Ends a drag, making its moves one undo step, and lets go.';
  rsPublishCancel = 'Ends a drag, putting back what it moved.';
  rsPublishDone = 'An empty object';
  rsPublishDropCopy = 'Places one copy waiting in the tray centred on a point of the layout, kept on the sheet; ' +
    'one undo step. Refused when its piece has a problem in the pattern.';
  rsPublishLayoutMethod = 'As the layout method %s, on the open layout; one undo step.';
  rsPublishLayoutReturns = 'What %s gives';
  rsPublishSave = 'The layout file''s text, to download, counted as saved.';
  rsPublishSaveReturns = '`text`, the layout file''s text';
  rsPublishExport = 'The layout written as PDF, SVG or DXF-AAMA, to download. The problems that block a PDF block ' +
    'these too.';
  rsPublishExportFormat = 'pdf, svg or dxf';
  rsPublishExportReturns = '`base64`, the file''s bytes';
  rsPublishTurn = 'Turns a placed piece a quarter turn anticlockwise, as the Pieces tab''s Turn 90°; one undo step.';
  rsPublishFlip = 'Flips a placed piece over, as the Pieces tab''s Flip; one undo step.';
  rsPublishUnplace = 'Takes a placed piece off the pages, back to the tray; one undo step.';
  rsPublishPlacement = 'The piece''s placement index, as publish_press gives it';
  rsPublishPieceReturns = '`placement`, the piece''s index';
  rsPublishPlaceCopy = 'Places one copy waiting in the tray, in the rows below the others; one undo step. Refused when ' +
    'its piece has a problem in the pattern.';
  rsPublishTrayIndex = 'The copy''s index in publish_state''s `tray`';
  rsPublishPlaceCopyReturns = '`placed`, the new placement''s index';
  rsPublishNoCopy = 'There is no copy %d in the tray';
  rsPublishPatterns = 'The Patterns tab: each pattern in the layout with its measurements and size.';
  rsPublishPatternsReturns = '`patterns`, each with its source `id`, `caption` (its file, with the size once ' +
    'one is chosen), `pattern` (its file''s name), `measurements` (the measurement file in use, empty for none), ' +
    '`ownSet` (true when the layout chose the file rather than the pattern), `size`, `sizes` (its file''s) and ' +
    '`problem`, empty when it is read';
  rsPublishAddPattern = 'Adds a pattern to the layout, its copies waiting in the tray; one undo step. The files ' +
    'given are kept for the sources to read, as publish_add_files gives them.';
  rsPublishPatternPath = 'The pattern''s path from the layout, as among the files';
  rsPublishAddPatternReturns = '`added`, how many copies went in the tray';
  rsPublishRemovePattern = 'Takes a pattern out of the layout, with its placements; one undo step.';
  rsPublishSourceId = 'The pattern''s source id, as publish_patterns gives it';
  rsPublishSetMeasurements = 'Reads a pattern with another measurement file, at its first size; one undo step.';
  rsPublishMeasurementPath = 'The measurement file''s path from the layout, as among the files; empty for the one ' +
    'the pattern names';
  rsPublishSetSize = 'Reads a pattern at another size of its measurement file; one undo step.';
  rsPublishSize = 'One of the measurement file''s sizes';
  rsPublishNoSource = 'The layout has no pattern %d';
  rsPublishUnknownSize = 'The measurements have no size "%s"';
  rsPublishPatternsDone = '`patterns`, as publish_patterns gives them';
  rsPublishOutput = 'The Output tab: the layout''s output settings, which of them apply to its kind of output, and ' +
    'the papers, materials and output profiles to choose from.';
  rsPublishOutputReturns = 'The settings (`kind`, `paper`, `paperWidth`, `paperHeight`, `margin`, `overlap`, ' +
    '`rollWidth`, `materialWidth`, `materialLength`, `allowTurns`, `material`, `marks`, `fill`, `outputProfile`); ' +
    '`used`, whether each of `rollWidth`, `materialSize`, `allowTurns`, `paper`, `paperSize`, `overlap`, `marks`, ' +
    '`fill` and `titlePlace` (the information block''s corner and every page) applies; and the lists `papers`, `materials` and `outputProfiles`';
  rsPublishSetOutput = 'Changes the Output tab''s settings, as the desktop''s tab does: one undo step, joining changes ' +
    'within a second. Pages left out are forgotten once the page grid moves. Refused when nothing would be left to ' +
    'print on.';
  rsPublishSetOutputReturns = 'What publish_output gives';
  rsPublishKind = 'tiled, large, projector or material';
  rsPublishPaper = 'A4, A3, Letter, or custom for paperWidth and paperHeight';
  rsPublishPaperWidth = 'A custom paper''s width, in mm';
  rsPublishPaperHeight = 'A custom paper''s height, in mm';
  rsPublishMargin = 'The margin, in mm';
  rsPublishOverlap = 'Tiles'' overlap, in mm';
  rsPublishRollWidth = 'A large format roll''s width, in mm';
  rsPublishMaterialWidth = 'A material sheet''s width, in mm';
  rsPublishMaterialLength = 'A material sheet''s length, in mm; 0 for a roll';
  rsPublishAllowTurns = 'Whether packing may turn pieces a quarter on a material with no grain';
  rsPublishMaterial = 'The material to limit the layout to; empty for all';
  rsPublishMarks = 'diamond, none or halfCircle';
  rsPublishFill = 'none, tint or hatch';
  rsPublishOutputProfile = 'The output profile; empty for everything';
  rsPublishUnknownPaper = 'Unknown paper "%s"';
  rsPublishTogglePage = 'Leaves the page at a point of the layout out of the print, or puts it back; one undo step.';
  rsPublishTogglePageReturns = '`page`, the page''s caption, empty when there is none there';
  rsPublishAddNote = 'Adds a sheet note at the left, below the pieces, as the desktop''s Add note; one undo step.';
  rsPublishAddNoteReturns = '`note`, its index';
  rsPublishNote = 'A sheet note as typed, for the Notes tab.';
  rsPublishNoteReturns = '`text` (fields not filled in), `size` in points, `align`, `boxed`, `font`, `bold` and ' +
    '`italic`';
  rsPublishNoteIndex = 'The note''s index, as publish_scene lists the notes';
  rsPublishSetNote = 'Changes a sheet note, as the desktop''s Notes tab does; changes within a second join one undo ' +
    'step. A font name that cannot be used is refused, with nothing changed.';
  rsPublishNoteText = 'Its text, with fields such as {pattern.name}';
  rsPublishNoteSize = 'Its text size, in points';
  rsPublishNoteAlign = 'left, centre or right';
  rsPublishNoteBoxed = 'Whether it prints on a white box';
  rsPublishNoteFont = 'Its font''s name; empty for the default';
  rsPublishNoteBold = 'Bold';
  rsPublishNoteItalic = 'Italic';
  rsPublishDeleteNote = 'Deletes a sheet note; one undo step.';
  rsPublishNoNote = 'There is no sheet note %d';
  rsPublishBadNoteSize = 'A note''s size is from 1 to %d points';
  rsPublishTitle = 'The Info tab: the information block, whether it shows, its fields in the order they print, its ' +
    'corner and whether it is on every page.';
  rsPublishTitleReturns = '`enabled`, `fields` (those shown, in print order), `available` (every field, in the ' +
    'tab''s order), `corner`, `everyPage`, and `placeUsed`, whether the corner and every page apply to the output';
  rsPublishSetTitle = 'Changes the information block, as the desktop''s Info tab does; one undo step.';
  rsPublishTitleEnabled = 'Whether it shows';
  rsPublishTitleField = 'A field to show or hide; shown anew, it prints last';
  rsPublishTitleShown = 'Whether the field shows';
  rsPublishTitleCorner = 'bottomRight, bottomLeft or topRight';
  rsPublishTitleEveryPage = 'A copy on every tile as well as the cover';
  rsPublishTitleNeedsShown = 'Say whether the field is `shown`';
  rsPublishMaterials = 'The Materials tab: how much of each material the layout''s patterns need, as the desktop''s ' +
    'tab works it out.';
  rsPublishMaterialsReturns = '`needs`, each with its `material`, `size` (the material''s, as the tab shows it), ' +
    '`copies` (pieces cut from it), `needed` (how much, as the tab shows it) and `notes`';
  rsPublishX = 'Across, in layout mm';
  rsPublishY = 'Down, in layout mm';

implementation

uses
  StrUtils, Math, Sloper.Core.OutputProfiles, Sloper.Output.MaterialNeeded, Sloper.Core.Note, Sloper.Core.Stamp, Sloper.API.Rpc,
  Sloper.API.Server, Sloper.Core.JSON, Sloper.Core.Geometry,
  Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.TextFields, Sloper.Core.PatternCheck, Sloper.Output.Layout,
  Sloper.Output.Tiling, Sloper.Output.TitleBlock, Sloper.Output.LayoutExport, Sloper.API.Shapes,
  base64;

const
  // The layout methods (Sloper.API.LayoutServer) the page calls as publish_ ones
  LAYOUT_COMMANDS: array[0..3] of string = ('undo', 'redo', 'place_pieces', 'pack');
  // A machine DXF needs the user's machine profiles, which the web has not yet
  WEB_EXPORTS: array[0..2] of TExportFormat = (efPDF, efSVG, efDXF);
  WEB_EXPORT_NAMES: array[0..2] of string = ('pdf', 'svg', 'dxf');

var
  Built: TApiMethodArray = nil;

function PublishMethods: TApiMethodArray;
var
  Index: integer;
begin
  if Length(Built) = 0 then
  begin
    AddApiMethod(Built, 'publish_open', rsPublishOpen, rsPublishStateReturns);
    AddApiParam(Built, 'files', apList, True, rsPublishFiles);
    AddApiParam(Built, 'files[].path', apText, True, rsPublishFilePath);
    AddApiParam(Built, 'files[].text', apText, True, rsPublishFileText);
    AddApiParam(Built, 'layout', apText, False, rsPublishLayout);
    AddApiParam(Built, 'pattern', apText, False, rsPublishPattern);
    AddApiMethod(Built, 'publish_add_files', rsPublishAddFiles, rsPublishStateReturns);
    AddApiParam(Built, 'files', apList, True, rsPublishFiles);
    AddApiParam(Built, 'files[].path', apText, True, rsPublishFilePath);
    AddApiParam(Built, 'files[].text', apText, True, rsPublishFileText);
    AddApiMethod(Built, 'publish_state', rsPublishState, rsPublishStateReturns, True);
    for Index := 0 to High(LAYOUT_COMMANDS) do
      AddApiMethod(Built, PUBLISH_PREFIX + LAYOUT_COMMANDS[Index], Format(rsPublishLayoutMethod, [LAYOUT_COMMANDS[Index]]),
        Format(rsPublishLayoutReturns, [LAYOUT_COMMANDS[Index]]));
    AddApiMethod(Built, 'publish_turn', rsPublishTurn, rsPublishPieceReturns);
    AddApiParam(Built, 'placement', apWhole, True, rsPublishPlacement);
    AddApiMethod(Built, 'publish_flip', rsPublishFlip, rsPublishPieceReturns);
    AddApiParam(Built, 'placement', apWhole, True, rsPublishPlacement);
    AddApiMethod(Built, 'publish_unplace', rsPublishUnplace, rsPublishPieceReturns);
    AddApiParam(Built, 'placement', apWhole, True, rsPublishPlacement);
    AddApiMethod(Built, 'publish_place_copy', rsPublishPlaceCopy, rsPublishPlaceCopyReturns);
    AddApiParam(Built, 'index', apWhole, True, rsPublishTrayIndex);
    AddApiMethod(Built, 'publish_patterns', rsPublishPatterns, rsPublishPatternsReturns, True);
    AddApiMethod(Built, 'publish_add_pattern', rsPublishAddPattern, rsPublishAddPatternReturns);
    AddApiParam(Built, 'path', apText, True, rsPublishPatternPath);
    AddApiParam(Built, 'files', apList, False, rsPublishFiles);
    AddApiParam(Built, 'files[].path', apText, True, rsPublishFilePath);
    AddApiParam(Built, 'files[].text', apText, True, rsPublishFileText);
    AddApiMethod(Built, 'publish_remove_pattern', rsPublishRemovePattern, rsPublishPatternsDone);
    AddApiParam(Built, 'source', apWhole, True, rsPublishSourceId);
    AddApiMethod(Built, 'publish_set_measurements', rsPublishSetMeasurements, rsPublishPatternsDone);
    AddApiParam(Built, 'source', apWhole, True, rsPublishSourceId);
    AddApiParam(Built, 'path', apText, True, rsPublishMeasurementPath);
    AddApiParam(Built, 'files', apList, False, rsPublishFiles);
    AddApiParam(Built, 'files[].path', apText, True, rsPublishFilePath);
    AddApiParam(Built, 'files[].text', apText, True, rsPublishFileText);
    AddApiMethod(Built, 'publish_set_size', rsPublishSetSize, rsPublishPatternsDone);
    AddApiParam(Built, 'source', apWhole, True, rsPublishSourceId);
    AddApiParam(Built, 'size', apText, True, rsPublishSize);
    AddApiMethod(Built, 'publish_output', rsPublishOutput, rsPublishOutputReturns, True);
    AddApiMethod(Built, 'publish_set_output', rsPublishSetOutput, rsPublishSetOutputReturns);
    AddApiParam(Built, 'kind', apChoice, False, rsPublishKind, string.Join(', ', KIND_NAMES));
    AddApiParam(Built, 'paper', apText, False, rsPublishPaper);
    AddApiParam(Built, 'paperWidth', apNumber, False, rsPublishPaperWidth);
    AddApiParam(Built, 'paperHeight', apNumber, False, rsPublishPaperHeight);
    AddApiParam(Built, 'margin', apNumber, False, rsPublishMargin);
    AddApiParam(Built, 'overlap', apNumber, False, rsPublishOverlap);
    AddApiParam(Built, 'rollWidth', apNumber, False, rsPublishRollWidth);
    AddApiParam(Built, 'materialWidth', apNumber, False, rsPublishMaterialWidth);
    AddApiParam(Built, 'materialLength', apNumber, False, rsPublishMaterialLength);
    AddApiParam(Built, 'allowTurns', apFlag, False, rsPublishAllowTurns);
    AddApiParam(Built, 'material', apText, False, rsPublishMaterial);
    AddApiParam(Built, 'marks', apChoice, False, rsPublishMarks, string.Join(', ', MARKS_NAMES));
    AddApiParam(Built, 'fill', apChoice, False, rsPublishFill, string.Join(', ', FILL_NAMES));
    AddApiParam(Built, 'outputProfile', apText, False, rsPublishOutputProfile);
    AddApiMethod(Built, 'publish_toggle_page', rsPublishTogglePage, rsPublishTogglePageReturns);
    AddApiParam(Built, 'x', apNumber, True, rsPublishX);
    AddApiParam(Built, 'y', apNumber, True, rsPublishY);
    AddApiMethod(Built, 'publish_add_note', rsPublishAddNote, rsPublishAddNoteReturns);
    AddApiMethod(Built, 'publish_note', rsPublishNote, rsPublishNoteReturns, True);
    AddApiParam(Built, 'note', apWhole, True, rsPublishNoteIndex);
    AddApiMethod(Built, 'publish_set_note', rsPublishSetNote, rsPublishNoteReturns);
    AddApiParam(Built, 'note', apWhole, True, rsPublishNoteIndex);
    AddApiParam(Built, 'text', apText, False, rsPublishNoteText);
    AddApiParam(Built, 'size', apNumber, False, rsPublishNoteSize);
    AddApiParam(Built, 'align', apChoice, False, rsPublishNoteAlign, string.Join(', ', TEXT_ALIGN_NAMES));
    AddApiParam(Built, 'boxed', apFlag, False, rsPublishNoteBoxed);
    AddApiParam(Built, 'font', apText, False, rsPublishNoteFont);
    AddApiParam(Built, 'bold', apFlag, False, rsPublishNoteBold);
    AddApiParam(Built, 'italic', apFlag, False, rsPublishNoteItalic);
    AddApiMethod(Built, 'publish_delete_note', rsPublishDeleteNote, rsPublishDone);
    AddApiParam(Built, 'note', apWhole, True, rsPublishNoteIndex);
    AddApiMethod(Built, 'publish_materials', rsPublishMaterials, rsPublishMaterialsReturns, True);
    AddApiMethod(Built, 'publish_title', rsPublishTitle, rsPublishTitleReturns, True);
    AddApiMethod(Built, 'publish_set_title', rsPublishSetTitle, rsPublishTitleReturns);
    AddApiParam(Built, 'enabled', apFlag, False, rsPublishTitleEnabled);
    AddApiParam(Built, 'field', apChoice, False, rsPublishTitleField, string.Join(', ', TITLE_FIELDS));
    AddApiParam(Built, 'shown', apFlag, False, rsPublishTitleShown);
    AddApiParam(Built, 'corner', apChoice, False, rsPublishTitleCorner, string.Join(', ', CORNER_NAMES));
    AddApiParam(Built, 'everyPage', apFlag, False, rsPublishTitleEveryPage);
    AddApiMethod(Built, 'publish_save', rsPublishSave, rsPublishSaveReturns);
    AddApiMethod(Built, 'publish_export', rsPublishExport, rsPublishExportReturns, True);
    AddApiParam(Built, 'format', apChoice, True, rsPublishExportFormat, string.Join(', ', WEB_EXPORT_NAMES));
    AddApiMethod(Built, 'publish_scene', rsPublishScene, rsPublishSceneReturns, True);
    AddApiMethod(Built, 'publish_press', rsPublishPress, rsPublishPressReturns);
    AddApiParam(Built, 'x', apNumber, True, rsPublishX);
    AddApiParam(Built, 'y', apNumber, True, rsPublishY);
    AddApiMethod(Built, 'publish_drag', rsPublishDrag, rsPublishDragReturns);
    AddApiParam(Built, 'x', apNumber, True, rsPublishX);
    AddApiParam(Built, 'y', apNumber, True, rsPublishY);
    AddApiMethod(Built, 'publish_release', rsPublishRelease, rsPublishDone);
    AddApiMethod(Built, 'publish_cancel', rsPublishCancel, rsPublishDone);
    AddApiMethod(Built, 'publish_drop_copy', rsPublishDropCopy, rsPublishPlaceCopyReturns);
    AddApiParam(Built, 'index', apWhole, True, rsPublishTrayIndex);
    AddApiParam(Built, 'x', apNumber, True, rsPublishX);
    AddApiParam(Built, 'y', apNumber, True, rsPublishY);
  end;
  Result := Built;
end;

constructor TPublishApiServer.Create;
begin
  inherited Create;
  FDocument := TLayoutDocument.Create;
  FLayoutServer := TLayoutApiServer.Create(FDocument);
  FDrag := TPreviewDrag.Create(FDocument);
end;

destructor TPublishApiServer.Destroy;
begin
  FreeAndNil(FDrag);
  FreeAndNil(FLayoutServer);
  FreeAndNil(FDocument);
  inherited Destroy;
end;

procedure TPublishApiServer.AddFiles(Params: TJSONObject);
var
  Data: TJSONData;
  Item: TJSONObject;
  Index: integer;
  Path, Text: string;
begin
  Data := nil;
  if Assigned(Params) then
    Data := Params.Find('files');
  if not Assigned(Data) or (Data.JSONType <> jtArray) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['files']));
  for Index := 0 to Data.Count - 1 do
  begin
    if Data.Items[Index].JSONType <> jtObject then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['files[]']));
    Item := TJSONObject(Data.Items[Index]);
    if not GetJSONString(Item, 'path', Path) or (Path = '') then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['files[].path']));
    if not GetJSONString(Item, 'text', Text) then
      raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['files[].text']));
    FDocument.SourceFiles.Add(Path, Text);
  end;
end;

function TPublishApiServer.DoOpen(Params: TJSONObject): TJSONData;
var
  LayoutText, PatternPath, Reason: string;
  HasLayout, HasPattern: boolean;
begin
  HasLayout := Assigned(Params) and GetJSONString(Params, 'layout', LayoutText);
  HasPattern := Assigned(Params) and GetJSONString(Params, 'pattern', PatternPath) and (PatternPath <> '');
  if not HasLayout and not HasPattern then
    raise EApiError.Create(RPC_INVALID_PARAMS, rsPublishNeedsSource);
  // A drag left open belongs to the layout open before
  FDrag.Cancel;
  // The files of the layout open before are no use to this one
  FDocument.SourceFiles.Clear;
  AddFiles(Params);
  if HasLayout then
  begin
    if not FDocument.OpenText(LayoutText, Reason) then
      raise EApiError.Create(RPC_REFUSED, Reason);
  end
  else
    FDocument.NewForPattern(PatternPath);
  Result := DoState;
end;

function TPublishApiServer.DoAddFiles(Params: TJSONObject): TJSONData;
begin
  AddFiles(Params);
  FDocument.Reload;
  Result := DoState;
end;

// Each once, as two sources may share a measurement file
function MissingFiles(Document: TLayoutDocument): TStringArray;
var
  Source: TPatternSource;
begin
  Result := nil;
  for Source in Document.Layout.Sources do
    if (Source.MissingFile <> '') and (IndexStr(Source.MissingFile, Result) < 0) then
      Insert(Source.MissingFile, Result, Length(Result));
end;

function TPublishApiServer.DoState: TJSONData;
var
  Answer: TJSONObject;
  Missing, Tray: TJSONArray;
  Path: string;
  Waiting: TUnplacedCopy;
begin
  Answer := TJSONObject(FLayoutServer.CallMethod('layout_state', nil));
  try
    Answer.Add('canUndo', FDocument.CanUndo);
    Answer.Add('canRedo', FDocument.CanRedo);
    Answer.Add('undo', FDocument.UndoDescription);
    Answer.Add('modified', FDocument.Modified);
    Missing := TJSONArray.Create;
    Answer.Add('missing', Missing);
    for Path in MissingFiles(FDocument) do
      Missing.Add(Path);
    Answer.Add('summary', PreviewSummary(FDocument.Layout));
    Tray := TJSONArray.Create;
    Answer.Add('tray', Tray);
    for Waiting in FDocument.Layout.Unplaced do
      Tray.Add(TJSONObject.Create(['caption', Waiting.Caption, 'canPlace', Waiting.CanPlace]));
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function RectJSON(const Area: TRect2): TJSONObject;
begin
  Result := TJSONObject.Create(['minX', ReportFloat(Area.MinX), 'minY', ReportFloat(Area.MinY), 'maxX',
    ReportFloat(Area.MaxX), 'maxY', ReportFloat(Area.MaxY)]);
end;

function PieceJSON(const Shape: TPlacedPiece): TJSONObject;
var
  Lines: TJSONArray;
  Line: TPlacedLine;
begin
  Result := TJSONObject.Create(['placement', Shape.Placement, 'caption', Shape.Caption]);
  if Shape.Look.Filled then
    Result.Add('fillColor', MaterialColorText(Shape.Look.Color))
  else
    Result.Add('fillColor', '');
  Result.Add('cutLine', LineToJSON(Shape.CutLine));
  Result.Add('seamLine', LineToJSON(Shape.SeamLine));
  Result.Add('marks', SegmentsToJSON(Shape.Marks));
  Lines := TJSONArray.Create;
  Result.Add('lines', Lines);
  for Line in Shape.Lines do
    Lines.Add(TJSONObject.Create(['points', LineToJSON(Line.Points), 'dashed', ROLE_DASHES[Line.Role][0] > 0]));
  if Shape.ShowLabel then
    Result.Add('label', TJSONObject.Create(['x', ReportFloat(Shape.LabelAt.X), 'y', ReportFloat(Shape.LabelAt.Y)]))
  else
    Result.Add('label', TJSONNull.Create);
end;

// A rectangle as the design editor's scene gives one: [minX, minY, maxX, maxY]
function SceneRectJSON(const Area: TRect2): TJSONArray;
begin
  Result := TJSONArray.Create([ReportFloat(Area.MinX), ReportFloat(Area.MinY), ReportFloat(Area.MaxX),
    ReportFloat(Area.MaxY)]);
end;

// A note as the preview draws it, as the design editor's scene gives one
// (editor_scene): its lines with fields filled in, its look, where its text
// and frame are, its leader, and a stamp's paths
function SheetNoteJSON(const Note: TSheetNote; const Values: TFieldValues): TJSONObject;
var
  Lines, Stamp: TJSONArray;
  Line: string;
  Frame: TRect2;
  Start: TVec2;
  Path: TStampPath;
begin
  Frame := NoteFrameBounds(Note, Values);
  Result := TJSONObject.Create;
  try
    Lines := TJSONArray.Create;
    Result.Add('lines', Lines);
    if not HasDrawing(Note.Drawing) then
      for Line in TextLines(ExpandFields(Note.Text, Values)) do
        Lines.Add(Line);
    Result.Add('size', ReportFloat(Note.Size));
    Result.Add('lineHeight', ReportFloat(LineHeight(Note.Size)));
    Result.Add('align', TEXT_ALIGN_NAMES[Note.Align]);
    Result.Add('boxed', Note.Boxed);
    Result.Add('font', Note.Style.Font);
    Result.Add('bold', Note.Style.Bold);
    Result.Add('italic', Note.Style.Italic);
    Result.Add('box', SceneRectJSON(NoteBounds(Note, Values)));
    Result.Add('frame', SceneRectJSON(Frame));
    Result.Add('leader', NOTE_LEADER_NAMES[Note.Leader]);
    if (Note.Leader <> nlNone) and LeaderStart(Frame, Note.Tip, Start) then
      Result.Add('leaderStrokes', SegmentsToJSON(LeaderStrokes(Start, Note.Tip, Note.Leader)))
    else
      Result.Add('leaderStrokes', TJSONArray.Create);
    Result.Add('anchorAt', LineToJSON([Note.Tip]));
    Stamp := TJSONArray.Create;
    Result.Add('stamp', Stamp);
    if HasDrawing(Note.Drawing) then
      for Path in Note.Drawing.Paths do
        Stamp.Add(TJSONObject.Create(['d', StampPathData(Path, Vec2(Note.X, Note.Y), Note.Scale), 'fill',
          StampColourText(Path.Fill), 'stroke', StampColourText(Path.Stroke), 'strokeWidth',
          ReportFloat(Path.StrokeWidth * Note.Scale), 'evenOdd', Path.EvenOdd]));
  except
    FreeAndNil(Result);
    raise;
  end;
end;

// As TPreviewCanvas.Refresh works it out and Paint draws it
function TPublishApiServer.DoScene: TJSONData;
var
  Layout: TLayout;
  Shapes: TPlacedPieceArray;
  Pages: TTilePageArray;
  Page: TTilePage;
  Shape: TPlacedPiece;
  Box: TRect2;
  Values: TFieldValues;
  Answer: TJSONObject;
  List: TJSONArray;
  Item: TJSONObject;
  Rows, Columns, Index: integer;
  Tiled: boolean;
  Text: string;
  Note: TSheetNote;
begin
  Layout := FDocument.Layout;
  Shapes := Layout.PlacedPieces;
  Pages := Layout.Pages(Shapes, Rows, Columns);
  Values := Layout.FieldValues('', '');
  Tiled := Layout.Output.Kind = okTiled;
  Answer := TJSONObject.Create(['tiled', Tiled]);
  try
    if Tiled then
      Answer.Add('cover', RectJSON(PreviewCover(Layout, Pages)))
    else
      Answer.Add('cover', TJSONNull.Create);
    List := TJSONArray.Create;
    Answer.Add('pages', List);
    for Page in Pages do
    begin
      Item := RectJSON(Page.Area);
      Item.Add('caption', Page.Caption);
      Item.Add('blank', Page.Blank);
      Item.Add('excluded', Page.Excluded);
      List.Add(Item);
    end;
    List := TJSONArray.Create;
    Answer.Add('pieces', List);
    for Shape in Shapes do
      List.Add(PieceJSON(Shape));
    List := TJSONArray.Create;
    Answer.Add('notes', List);
    for Index := 0 to High(Layout.Notes) do
      List.Add(SheetNoteJSON(Layout.Notes[Index], Values));
    List := TJSONArray.Create;
    Answer.Add('pieceNotes', List);
    for Shape in Shapes do
      for Note in Shape.Notes do
        List.Add(SheetNoteJSON(Note, Values));
    List := TJSONArray.Create;
    Answer.Add('titleBoxes', List);
    for Box in PreviewTitleBoxes(Layout, Pages, Values) do
      List.Add(RectJSON(Box));
    List := TJSONArray.Create;
    for Text in Layout.TitleLines(Values) do
      List.Add(Text);
    Answer.Add('title', TJSONObject.Create(['lines', List, 'size', ReportFloat(TITLE_TEXT_SIZE * POINTS_TO_MM), 'lineHeight',
      ReportFloat(LineHeight(TITLE_TEXT_SIZE)), 'padding', ReportFloat(TITLE_PADDING)]));
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function NumberParam(Params: TJSONObject; const AName: string): double;
begin
  Result := 0;
  if not Assigned(Params) or not OptionalNumber(Params, AName, Result) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
end;

// A list index, refused when it is not a whole number
function IndexParam(Params: TJSONObject; const AName: string): integer;
var
  Value: double;
begin
  Value := NumberParam(Params, AName);
  if (Frac(Value) <> 0) or (Value < 0) or (Value > MaxInt) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [AName]));
  Result := Trunc(Value);
end;

function PointParam(Params: TJSONObject): TVec2;
begin
  Result := Vec2(NumberParam(Params, 'x'), NumberParam(Params, 'y'));
end;

function TPublishApiServer.DoPress(Params: TJSONObject): TJSONData;
begin
  FDrag.Press(FDocument.Layout.PlacedPieces, PointParam(Params));
  Result := TJSONObject.Create(['placement', FDrag.Placement, 'note', FDrag.Note]);
end;

function TPublishApiServer.DoDrag(Params: TJSONObject): TJSONData;
begin
  Result := TJSONObject.Create(['moving', FDrag.MoveTo(PointParam(Params))]);
end;

function TPublishApiServer.DoDropCopy(Params: TJSONObject): TJSONData;
var
  Tray: TUnplacedCopyArray;
  Index, Placed: integer;
  At: TVec2;
begin
  Index := IndexParam(Params, 'index');
  At := PointParam(Params);
  Tray := FDocument.Layout.Unplaced;
  if Index > High(Tray) then
    raise EApiError.Create(RPC_REFUSED, Format(rsPublishNoCopy, [Index]));
  Placed := FDrag.DropCopy(Tray[Index], At);
  if Placed < 0 then
    raise EApiError.Create(RPC_REFUSED, rsLayoutCannotPlace);
  Result := TJSONObject.Create(['placed', Placed]);
end;

// Turn, Flip and Back to tray, for the selected piece
function TPublishApiServer.DoPieceEdit(const Method: string; Params: TJSONObject): TJSONData;
var
  Index: integer;
begin
  Index := IndexParam(Params, 'placement');
  if Index > High(FDocument.Layout.Placements) then
    raise EApiError.Create(RPC_REFUSED, Format(rsLayoutNoPiece, [Index]));
  case Method of
    'publish_turn': FDocument.TurnPiece(Index);
    'publish_flip': FDocument.FlipPiece(Index);
    'publish_unplace': FDocument.UnplacePiece(Index);
  end;
  Result := TJSONObject.Create(['placement', Index]);
end;

function TPublishApiServer.DoPlaceCopy(Params: TJSONObject): TJSONData;
var
  Tray: TUnplacedCopyArray;
  Index: integer;
begin
  Index := IndexParam(Params, 'index');
  Tray := FDocument.Layout.Unplaced;
  if Index > High(Tray) then
    raise EApiError.Create(RPC_REFUSED, Format(rsPublishNoCopy, [Index]));
  if not FDocument.PlaceCopy(Tray[Index]) then
    raise EApiError.Create(RPC_REFUSED, rsLayoutCannotPlace);
  Result := TJSONObject.Create(['placed', High(FDocument.Layout.Placements)]);
end;

function TPublishApiServer.SourceParam(Params: TJSONObject): TPatternSource;
var
  Id: integer;
  Source: TPatternSource;
begin
  Id := IndexParam(Params, 'source');
  for Source in FDocument.Layout.Sources do
    if Source.Id = Id then
      Exit(Source);
  raise EApiError.Create(RPC_REFUSED, Format(rsPublishNoSource, [Id]));
end;

// As the desktop's Patterns tab lists them
function TPublishApiServer.DoPatterns: TJSONData;
var
  Answer, Item: TJSONObject;
  List, Sizes: TJSONArray;
  Source: TPatternSource;
  Caption, SizeName: string;
  Index: integer;
begin
  Answer := TJSONObject.Create;
  try
    List := TJSONArray.Create;
    Answer.Add('patterns', List);
    for Source in FDocument.Layout.Sources do
    begin
      Caption := ExtractFileName(Source.PatternFile);
      SizeName := '';
      Sizes := TJSONArray.Create;
      if Assigned(Source.Measurements) then
      begin
        SizeName := Source.Measurements.SizeName;
        for Index := 0 to Source.Measurements.SizeCount - 1 do
          Sizes.Add(Source.Measurements.Sizes[Index]);
      end;
      if SizeName <> '' then
        Caption := Format(rsLayoutSetAndSize, [Caption, SizeName]);
      Item := TJSONObject.Create(['id', Source.Id, 'caption', Caption, 'pattern', ExtractFileName(Source.PatternFile),
        'measurements', ExtractFileName(SetDirSeparators(Source.MeasurementPath)), 'ownSet', Source.MeasurementFile <> '',
        'size', SizeName, 'sizes', Sizes, 'problem', Source.LoadError]);
      List.Add(Item);
    end;
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function TPublishApiServer.DoAddPattern(Params: TJSONObject): TJSONData;
var
  Path: string;
  Added: integer;
begin
  Path := RequireString(Params, 'path');
  if Assigned(Params.Find('files')) then
    AddFiles(Params);
  Added := FDocument.AddPattern(Path);
  Result := TJSONObject.Create(['added', Added]);
end;

function TPublishApiServer.DoSetMeasurements(Params: TJSONObject): TJSONData;
var
  Source: TPatternSource;
  Path: string;
begin
  Source := SourceParam(Params);
  if not Assigned(Params.Find('path')) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['path']));
  Path := OptionalString(Params, 'path');
  if Assigned(Params.Find('files')) then
    AddFiles(Params);
  FDocument.SetMeasurements(Source, Path);
  Result := DoPatterns;
end;

// One of its file's sizes, so a typing slip is refused rather than read as a problem
function TPublishApiServer.DoSetSize(Params: TJSONObject): TJSONData;
var
  Source: TPatternSource;
  Size: string;
  Index: integer;
  Known: boolean;
begin
  Source := SourceParam(Params);
  Size := RequireString(Params, 'size');
  Known := False;
  if Assigned(Source.Measurements) then
    for Index := 0 to Source.Measurements.SizeCount - 1 do
      Known := Known or (Source.Measurements.Sizes[Index] = Size);
  if not Known then
    raise EApiError.Create(RPC_REFUSED, Format(rsPublishUnknownSize, [Size]));
  FDocument.SetSize(Source, Size);
  Result := DoPatterns;
end;

const
  OUTPUT_SETTING_NAMES: array[TOutputSetting] of string = ('rollWidth', 'materialSize', 'allowTurns', 'paper',
    'paperSize', 'overlap', 'marks', 'fill', 'titlePlace');

function TPublishApiServer.DoOutput: TJSONData;
var
  Layout: TLayout;
  Output: TLayoutOutput;
  Answer, Used: TJSONObject;
  List: TJSONArray;
  Setting: TOutputSetting;
  Source: TPatternSource;
  Profile: TOutputProfile;
  Index: integer;

  procedure AddOnce(const Name: string);
  var
    Item: integer;
  begin
    for Item := 0 to List.Count - 1 do
      if List.Strings[Item] = Name then
        Exit;
    List.Add(Name);
  end;

begin
  Layout := FDocument.Layout;
  Output := Layout.Output;
  Answer := TJSONObject.Create(['kind', KIND_NAMES[Output.Kind], 'paper', Output.Paper, 'paperWidth',
    Output.Tiles.PaperWidth, 'paperHeight', Output.Tiles.PaperHeight, 'margin', Output.Tiles.Margin, 'overlap',
    Output.Tiles.Overlap, 'rollWidth', Output.RollWidth, 'materialWidth', Output.MaterialWidth, 'materialLength',
    Output.MaterialLength, 'allowTurns', Output.AllowTurns, 'material', Output.Material, 'marks',
    MARKS_NAMES[Output.Marks], 'fill', FILL_NAMES[Output.Fill], 'outputProfile', Output.OutputProfile]);
  try
    Used := TJSONObject.Create;
    Answer.Add('used', Used);
    for Setting in TOutputSetting do
      Used.Add(OUTPUT_SETTING_NAMES[Setting], OutputSettingUsed(Output, Setting));
    List := TJSONArray.Create;
    Answer.Add('papers', List);
    for Index := 0 to High(PAPER_NAMES) do
      List.Add(PAPER_NAMES[Index]);
    // Every material in the layout's patterns, each once; a name no pattern
    // has stays listed, so the choice is not lost when a pattern changes
    List := TJSONArray.Create;
    Answer.Add('materials', List);
    for Source in Layout.Sources do
      if Assigned(Source.Pattern) then
        for Index := 0 to Source.Pattern.MaterialCount - 1 do
          AddOnce(Source.Pattern.Materials[Index].Name);
    if Output.Material <> '' then
      AddOnce(Output.Material);
    List := TJSONArray.Create;
    Answer.Add('outputProfiles', List);
    for Profile in AllOutputProfiles(Layout.OutputProfiles) do
      AddOnce(Profile.Name);
    if Output.OutputProfile <> '' then
      AddOnce(Output.OutputProfile);
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function TPublishApiServer.DoSetOutput(Params: TJSONObject): TJSONData;
var
  Output: TLayoutOutput;
  Value: double;
  Reason: string;
begin
  if not Assigned(Params) then
    Exit(DoOutput);
  Output := FDocument.Layout.Output;
  if Assigned(Params.Find('kind')) then
    Output.Kind := TOutputKind(ChoiceParam(Params, 'kind', KIND_NAMES));
  if Assigned(Params.Find('paper')) then
  begin
    Output.Paper := RequireString(Params, 'paper');
    if (Output.Paper <> CUSTOM_PAPER) and not PaperSize(Output.Paper, Output.Tiles.PaperWidth,
      Output.Tiles.PaperHeight) then
      raise EApiError.Create(RPC_REFUSED, Format(rsPublishUnknownPaper, [Output.Paper]));
  end;
  // A paper's own size, unless it is one typed in
  Value := 0;
  if (Output.Paper = CUSTOM_PAPER) and OptionalNumber(Params, 'paperWidth', Value) then
    Output.Tiles.PaperWidth := Value;
  if (Output.Paper = CUSTOM_PAPER) and OptionalNumber(Params, 'paperHeight', Value) then
    Output.Tiles.PaperHeight := Value;
  if OptionalNumber(Params, 'margin', Value) then
    Output.Tiles.Margin := Max(0, Value);
  if OptionalNumber(Params, 'overlap', Value) then
    Output.Tiles.Overlap := Max(0, Value);
  if OptionalNumber(Params, 'rollWidth', Value) then
    Output.RollWidth := Value;
  if OptionalNumber(Params, 'materialWidth', Value) then
    Output.MaterialWidth := Value;
  if OptionalNumber(Params, 'materialLength', Value) then
    Output.MaterialLength := Max(0, Value);
  if Assigned(Params.Find('allowTurns')) then
    Output.AllowTurns := BooleanParam(Params, 'allowTurns');
  if Assigned(Params.Find('material')) then
    Output.Material := OptionalString(Params, 'material');
  if Assigned(Params.Find('marks')) then
    Output.Marks := TLayoutMarks(ChoiceParam(Params, 'marks', MARKS_NAMES));
  if Assigned(Params.Find('fill')) then
    Output.Fill := TLayoutFill(ChoiceParam(Params, 'fill', FILL_NAMES));
  if Assigned(Params.Find('outputProfile')) then
    Output.OutputProfile := OptionalString(Params, 'outputProfile');
  if not FDocument.ChangeOutput(Output, Reason) then
    raise EApiError.Create(RPC_REFUSED, Reason);
  Result := DoOutput;
end;

function TPublishApiServer.DoTogglePage(Params: TJSONObject): TJSONData;
var
  Rows, Columns: integer;
  Caption: string;
begin
  Caption := PageCaptionAt(FDocument.Layout.Pages(FDocument.Layout.PlacedPieces, Rows, Columns), PointParam(Params));
  FDocument.TogglePage(Caption);
  Result := TJSONObject.Create(['page', Caption]);
end;

function TPublishApiServer.NoteParam(Params: TJSONObject): integer;
begin
  Result := IndexParam(Params, 'note');
  if Result > High(FDocument.Layout.Notes) then
    raise EApiError.Create(RPC_REFUSED, Format(rsPublishNoNote, [Result]));
end;

function TPublishApiServer.DoNote(Params: TJSONObject): TJSONData;
var
  Note: TSheetNote;
begin
  Note := FDocument.Layout.Notes[NoteParam(Params)];
  Result := TJSONObject.Create(['text', Note.Text, 'size', ReportFloat(Note.Size), 'align', TEXT_ALIGN_NAMES[Note.Align],
    'boxed', Note.Boxed, 'font', Note.Style.Font, 'bold', Note.Style.Bold, 'italic', Note.Style.Italic]);
end;

// As the desktop's Notes tab changes one
function TPublishApiServer.DoSetNote(Params: TJSONObject): TJSONData;
var
  Index: integer;
  Note: TSheetNote;
  Size: double;
  FontName, Reason: string;
begin
  Index := NoteParam(Params);
  Note := FDocument.Layout.Notes[Index];
  if Assigned(Params.Find('text')) then
    Note.Text := TrimRight(OptionalString(Params, 'text'));
  Size := Note.Size;
  if OptionalNumber(Params, 'size', Size) then
  begin
    if (Size < 1) or (Size > MAX_NOTE_SIZE) then
      raise EApiError.Create(RPC_REFUSED, Format(rsPublishBadNoteSize, [MAX_NOTE_SIZE]));
    Note.Size := Size;
  end;
  if Assigned(Params.Find('align')) then
    Note.Align := TTextAlign(ChoiceParam(Params, 'align', TEXT_ALIGN_NAMES));
  if Assigned(Params.Find('boxed')) then
    Note.Boxed := BooleanParam(Params, 'boxed');
  if Assigned(Params.Find('font')) then
  begin
    if not CheckFontName(OptionalString(Params, 'font'), FontName, Reason) then
      raise EApiError.Create(RPC_REFUSED, Reason);
    Note.Style.Font := FontName;
  end;
  if Assigned(Params.Find('bold')) then
    Note.Style.Bold := BooleanParam(Params, 'bold');
  if Assigned(Params.Find('italic')) then
    Note.Style.Italic := BooleanParam(Params, 'italic');
  FDocument.ChangeNote(Index, Note);
  Result := DoNote(Params);
end;

// As the desktop's Materials tab fills its grid and notes
function TPublishApiServer.DoMaterials: TJSONData;
var
  Need: TMaterialNeed;
  List, Notes: TJSONArray;
  Note: string;
begin
  List := TJSONArray.Create;
  Result := TJSONObject.Create(['needs', List]);
  for Need in LayoutMaterialNeeds(FDocument.Layout) do
  begin
    Notes := TJSONArray.Create;
    for Note in Need.Notes do
      Notes.Add(Note);
    List.Add(TJSONObject.Create(['material', Need.Name, 'size', MaterialNeedSize(Need), 'copies', Need.Copies, 'needed',
      MaterialNeedText(Need), 'notes', Notes]));
  end;
end;

function TPublishApiServer.DoTitle: TJSONData;
var
  Layout: TLayout;
  Shown, Available: TJSONArray;
  Field: string;
begin
  Layout := FDocument.Layout;
  Shown := TJSONArray.Create;
  for Field in Layout.Title.Fields do
    Shown.Add(Field);
  Available := TJSONArray.Create;
  for Field in TITLE_FIELDS do
    Available.Add(Field);
  Result := TJSONObject.Create(['enabled', Layout.Title.Enabled, 'fields', Shown, 'available', Available, 'corner',
    CORNER_NAMES[Layout.Title.Corner], 'everyPage', Layout.Title.EveryPage, 'placeUsed',
    OutputSettingUsed(Layout.Output, osTitlePlace)]);
end;

// As the desktop's Info tab: a field shown anew prints last, the others
// keeping their order
function TPublishApiServer.DoSetTitle(Params: TJSONObject): TJSONData;
var
  Title: TTitleBlock;
begin
  if not Assigned(Params) then
    Exit(DoTitle);
  Title := FDocument.Layout.Title;
  if Assigned(Params.Find('enabled')) then
    Title.Enabled := BooleanParam(Params, 'enabled');
  if Assigned(Params.Find('field')) then
  begin
    if not Assigned(Params.Find('shown')) then
      raise EApiError.Create(RPC_INVALID_PARAMS, rsPublishTitleNeedsShown);
    Title.Fields := TitleFieldsWith(Title.Fields, TITLE_FIELDS[ChoiceParam(Params, 'field', TITLE_FIELDS)],
      BooleanParam(Params, 'shown'));
  end;
  if Assigned(Params.Find('corner')) then
    Title.Corner := TTitleCorner(ChoiceParam(Params, 'corner', CORNER_NAMES));
  if Assigned(Params.Find('everyPage')) then
    Title.EveryPage := BooleanParam(Params, 'everyPage');
  FDocument.ChangeTitle(Title);
  Result := DoTitle;
end;

function TPublishApiServer.DoSave: TJSONData;
begin
  Result := TJSONObject.Create(['text', FDocument.SaveText]);
end;

function TPublishApiServer.DoExport(Params: TJSONObject): TJSONData;
var
  Bytes: rawbytestring;
  Reason: string;
begin
  if not LayoutBytes(FDocument.Layout, WEB_EXPORTS[ChoiceParam(Params, 'format', WEB_EXPORT_NAMES)], Bytes, Reason) then
    raise EApiError.Create(RPC_REFUSED, Reason);
  Result := TJSONObject.Create(['base64', EncodeStringBase64(Bytes)]);
end;

function TPublishApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
var
  Command: string;
begin
  for Command in LAYOUT_COMMANDS do
    if Method = PUBLISH_PREFIX + Command then
      Exit(FLayoutServer.CallMethod(Command, Params));
  case Method of
    'publish_open': Result := DoOpen(Params);
    'publish_add_files': Result := DoAddFiles(Params);
    'publish_state': Result := DoState;
    'publish_scene': Result := DoScene;
    'publish_press': Result := DoPress(Params);
    'publish_drag': Result := DoDrag(Params);
    'publish_release':
    begin
      FDrag.Release;
      Result := TJSONObject.Create;
    end;
    'publish_cancel':
    begin
      FDrag.Cancel;
      Result := TJSONObject.Create;
    end;
    'publish_drop_copy': Result := DoDropCopy(Params);
    'publish_turn', 'publish_flip', 'publish_unplace': Result := DoPieceEdit(Method, Params);
    'publish_place_copy': Result := DoPlaceCopy(Params);
    'publish_patterns': Result := DoPatterns;
    'publish_add_pattern': Result := DoAddPattern(Params);
    'publish_remove_pattern':
    begin
      FDocument.RemovePattern(SourceParam(Params));
      Result := DoPatterns;
    end;
    'publish_set_measurements': Result := DoSetMeasurements(Params);
    'publish_set_size': Result := DoSetSize(Params);
    'publish_output': Result := DoOutput;
    'publish_set_output': Result := DoSetOutput(Params);
    'publish_toggle_page': Result := DoTogglePage(Params);
    'publish_add_note': Result := TJSONObject.Create(['note', FDocument.AddNote]);
    'publish_note': Result := DoNote(Params);
    'publish_set_note': Result := DoSetNote(Params);
    'publish_delete_note':
    begin
      FDocument.DeleteNote(NoteParam(Params));
      Result := TJSONObject.Create;
    end;
    'publish_materials': Result := DoMaterials;
    'publish_title': Result := DoTitle;
    'publish_set_title': Result := DoSetTitle(Params);
    'publish_save': Result := DoSave;
    'publish_export': Result := DoExport(Params);
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
end;

end.
