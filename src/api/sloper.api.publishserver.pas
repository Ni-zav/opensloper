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
  SysUtils, fpjson, Sloper.API.Methods, Sloper.API.LayoutServer, Sloper.Output.LayoutDocument;

const
  PUBLISH_PREFIX = 'publish_';

type
  TPublishApiServer = class
  private
    FDocument: TLayoutDocument;
    FLayoutServer: TLayoutApiServer;
    procedure AddFiles(Params: TJSONObject);
    function DoOpen(Params: TJSONObject): TJSONData;
    function DoAddFiles(Params: TJSONObject): TJSONData;
    function DoState: TJSONData;
    function DoScene: TJSONData;
    function DoAt(Params: TJSONObject): TJSONData;
    function DoPieceEdit(const Method: string; Params: TJSONObject): TJSONData;
    function DoPlaceCopy(Params: TJSONObject): TJSONData;
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
    'need and were not given; and `tray`: the copies waiting to be placed, each with its `caption` and whether it ' +
    '`canPlace`';
  rsPublishNeedsSource = 'Give a layout, or the pattern to start one for';
  rsPublishScene = 'What the preview shows, in layout mm with y down, as the desktop''s preview draws it.';
  rsPublishSceneReturns = '`tiled`, true for tiled pages; `cover`, the tiled print''s cover (minX, minY, maxX, maxY) or ' +
    'null; `pages`, each with its `caption`, its area and whether it is `blank` or `excluded`; `pieces`, each with ' +
    'its `placement` index, `caption`, `fillColor` (empty when not filled), `cutLine` and `seamLine` (flat lists of ' +
    'x, y), `marks` (flat segments), `lines` (each with flat `points` and `dashed`) and `label` (x, y), or null when ' +
    'labels are left out; `titleBoxes`, the information block''s boxes; `title`, its `lines`, text `size`, ' +
    '`lineHeight` and `padding` in mm';
  rsPublishAt = 'The placed piece at a point of the layout, the smallest where they overlap.';
  rsPublishAtReturns = '`placement`, the piece''s placement index, or -1 for none';
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
  rsPublishPlacement = 'The piece''s placement index, as publish_at gives it';
  rsPublishPieceReturns = '`placement`, the piece''s index';
  rsPublishPlaceCopy = 'Places one copy waiting in the tray, in the rows below the others; one undo step. Refused when ' +
    'its piece has a problem in the pattern.';
  rsPublishTrayIndex = 'The copy''s index in publish_state''s `tray`';
  rsPublishPlaceCopyReturns = '`placed`, the new placement''s index';
  rsPublishNoCopy = 'There is no copy %d in the tray';
  rsPublishX = 'Across, in layout mm';
  rsPublishY = 'Down, in layout mm';

implementation

uses
  StrUtils, Sloper.API.Rpc, Sloper.API.Server, Sloper.Core.JSON, Sloper.Core.PatternSources, Sloper.Core.Geometry,
  Sloper.Core.Draft, Sloper.Core.Materials, Sloper.Core.TextFields, Sloper.Core.PatternCheck, Sloper.Output.Layout,
  Sloper.Output.Tiling, Sloper.Output.TitleBlock, Sloper.Output.Preview, Sloper.Output.LayoutExport, Sloper.API.Shapes,
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
    AddApiMethod(Built, 'publish_save', rsPublishSave, rsPublishSaveReturns);
    AddApiMethod(Built, 'publish_export', rsPublishExport, rsPublishExportReturns, True);
    AddApiParam(Built, 'format', apChoice, True, rsPublishExportFormat, string.Join(', ', WEB_EXPORT_NAMES));
    AddApiMethod(Built, 'publish_scene', rsPublishScene, rsPublishSceneReturns, True);
    AddApiMethod(Built, 'publish_at', rsPublishAt, rsPublishAtReturns, True);
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
end;

destructor TPublishApiServer.Destroy;
begin
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
  Rows, Columns: integer;
  Tiled: boolean;
  Text: string;
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

function TPublishApiServer.DoAt(Params: TJSONObject): TJSONData;
var
  Shapes: TPlacedPieceArray;
  At: TVec2;
  Index: integer;
begin
  At := Vec2(NumberParam(Params, 'x'), NumberParam(Params, 'y'));
  Shapes := FDocument.Layout.PlacedPieces;
  Index := ShapeAt(Shapes, At);
  if Index >= 0 then
    Index := Shapes[Index].Placement;
  Result := TJSONObject.Create(['placement', Index]);
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
    'publish_at': Result := DoAt(Params);
    'publish_turn', 'publish_flip', 'publish_unplace': Result := DoPieceEdit(Method, Params);
    'publish_place_copy': Result := DoPlaceCopy(Params);
    'publish_save': Result := DoSave;
    'publish_export': Result := DoExport(Params);
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
end;

end.
