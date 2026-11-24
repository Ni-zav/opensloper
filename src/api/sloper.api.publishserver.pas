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

// The web Publish app runs the layout commands with files supplied as text.
unit Sloper.API.PublishServer;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson, Sloper.API.LayoutServer, Sloper.Output.LayoutDocument, Sloper.Output.Layout;

type
  TPublishApiServer = class
  private
    FDocument: TLayoutDocument;
    FCommands: TLayoutApiServer;
    FFiles: TJSONObject;
    procedure LoadSources(Layout: TLayout);
    procedure OpenFiles(Params: TJSONObject);
    function State: TJSONObject;
    function ExportLayout(const Kind: string): TJSONData;
  public
    constructor Create;
    destructor Destroy; override;
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData;
  end;

implementation

uses
  SysUtils, base64, Sloper.API.Rpc, Sloper.API.Server, Sloper.Core.PatternSources, Sloper.Output.LayoutPDF,
  Sloper.Output.LayoutSVG;

resourcestring
  rsSelectInputFiles = 'Choose pattern files or a layout with its sources';
  rsInvalidInputFiles = 'The selected files need distinct names and text contents';
  rsExtraLayout = 'Choose only one layout file';
  rsNeedSource = 'Choose the layout''s source file %s with it';

constructor TPublishApiServer.Create;
begin
  inherited Create;
  FDocument := TLayoutDocument.Create;
  FDocument.OnLoadSources := @LoadSources;
  FCommands := TLayoutApiServer.Create(FDocument);
end;

destructor TPublishApiServer.Destroy;
begin
  FreeAndNil(FCommands);
  FreeAndNil(FDocument);
  FreeAndNil(FFiles);
  inherited Destroy;
end;

function FileLeaf(const Path: string): string;
begin
  Result := ExtractFileName(SetDirSeparators(Path));
end;

procedure TPublishApiServer.LoadSources(Layout: TLayout);
var
  Source: TPatternSource;
  PatternFile, PatternText, Measurements, MeasurementText: string;
  Data: TJSONData;
begin
  for Source in Layout.Sources do
  begin
    PatternFile := FileLeaf(Source.PatternFile);
    Data := FFiles.Find(PatternFile);
    if not Assigned(Data) then
      raise EApiError.Create(RPC_REFUSED, Format(rsNeedSource, [PatternFile]));
    PatternText := Data.AsString;
    Measurements := Source.MeasurementFile;
    if Measurements = '' then
    begin
      Layout.LoadSourceText(Source, PatternText, '');
      // LoadText can report a missing size until the measurement text arrives.
      // The parsed pattern still tells us which set it is linked to.
      if Assigned(Source.Pattern) then
        Measurements := Source.Pattern.MeasurementFile;
    end;
    if Measurements <> '' then
    begin
      Measurements := FileLeaf(Measurements);
      Data := FFiles.Find(Measurements);
      if not Assigned(Data) then
        raise EApiError.Create(RPC_REFUSED, Format(rsNeedSource, [Measurements]));
      MeasurementText := Data.AsString;
      Layout.LoadSourceText(Source, PatternText, MeasurementText);
    end;
    if Source.LoadError <> '' then
      raise EApiError.Create(RPC_REFUSED, Source.LoadError);
  end;
end;

procedure TPublishApiServer.OpenFiles(Params: TJSONObject);
var
  Data, FileText: TJSONData;
  Incoming, Previous: TJSONObject;
  Layout: TLayout;
  Index: integer;
  Key, Extension, LayoutName, Text, Error: string;
begin
  Data := Params.Find('files');
  if not (Data is TJSONObject) then
    raise EApiError.Create(RPC_INVALID_PARAMS, rsInvalidInputFiles);
  Incoming := TJSONObject(Data.Clone);
  Previous := FFiles;
  FFiles := Incoming;
  Layout := nil;
  try
    try
      Layout := TLayout.Create;
      LayoutName := '';
      Text := '';
      for Index := 0 to Incoming.Count - 1 do
      begin
        Key := Incoming.Names[Index];
        FileText := Incoming.Items[Index];
        if (Key = '') or (FileLeaf(Key) <> Key) or (FileText.JSONType <> jtString) then
          raise EApiError.Create(RPC_INVALID_PARAMS, rsInvalidInputFiles);
        Extension := LowerCase(ExtractFileExt(Key));
        case Extension of
          '.sloper': Layout.AddSource(Key, '', '');
          LAYOUT_EXTENSION:
          begin
            if LayoutName <> '' then
              raise EApiError.Create(RPC_INVALID_PARAMS, rsExtraLayout);
            LayoutName := Key;
            Text := FileText.AsString;
          end;
        end;
      end;
      if LayoutName = '' then
      begin
        if Layout.Sources.Count = 0 then
          raise EApiError.Create(RPC_INVALID_PARAMS, rsSelectInputFiles);
        Layout.Name := ChangeFileExt(Layout.Sources[0].PatternFile, '');
        LoadSources(Layout);
        Layout.PlaceNewPieces;
        Layout.UseDefaultTitle;
        Text := Layout.SaveToText;
      end;
      if not FDocument.OpenText(Text, Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
      FreeAndNil(Previous);
    except
      FFiles := Previous;
      FreeAndNil(Incoming);
      raise;
    end;
  finally
    FreeAndNil(Layout);
  end;
end;

function TPublishApiServer.State: TJSONObject;
begin
  Result := TJSONObject(FCommands.CallMethod('layout_state', nil));
  Result.Add('canUndo', FDocument.CanUndo);
  Result.Add('canRedo', FDocument.CanRedo);
  Result.Add('text', FDocument.Layout.SaveToText);
end;

function TPublishApiServer.ExportLayout(const Kind: string): TJSONData;
var
  Refusal: string;
begin
  Refusal := FDocument.Layout.Refusal;
  if Refusal <> '' then
    raise EApiError.Create(RPC_REFUSED, Refusal);
  if Kind = 'pdf' then
    Result := TJSONObject.Create(['pdf', EncodeStringBase64(LayoutToPDF(FDocument.Layout))])
  else
    Result := TJSONObject.Create(['svg', LayoutToSVG(FDocument.Layout)]);
end;

function TPublishApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
begin
  case Method of
    'open':
    begin
      OpenFiles(Params);
      Result := State;
    end;
    'state': Result := State;
    'preview': Result := TJSONObject.Create(['svg', LayoutToSVG(FDocument.Layout)]);
    'export_pdf': Result := ExportLayout('pdf');
    'export_svg': Result := ExportLayout('svg');
    'list_pieces', 'place_pieces', 'set_placement', 'remove_piece', 'pack', 'set_output', 'undo', 'redo':
      Result := FCommands.CallMethod(Method, Params);
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
end;

end.
