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
    'need and were not given';
  rsPublishNeedsSource = 'Give a layout, or the pattern to start one for';

implementation

uses
  StrUtils, Sloper.API.Rpc, Sloper.API.Server, Sloper.Core.JSON, Sloper.Core.PatternSources;

var
  Built: TApiMethodArray = nil;

function PublishMethods: TApiMethodArray;
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
  Missing: TJSONArray;
  Path: string;
begin
  Answer := TJSONObject(FLayoutServer.CallMethod('layout_state', nil));
  try
    Missing := TJSONArray.Create;
    Answer.Add('missing', Missing);
    for Path in MissingFiles(FDocument) do
      Missing.Add(Path);
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function TPublishApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'publish_open': Result := DoOpen(Params);
    'publish_add_files': Result := DoAddFiles(Params);
    'publish_state': Result := DoState;
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
end;

end.
