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

// The browser measurements app's document and its file-free editing commands.
unit Sloper.API.MeasurementServer;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson, Sloper.Document.MeasurementDocument;

type
  TMeasurementApiServer = class
  private
    FDocument: TMeasurementDocument;
    procedure EditRow(const Method: string; Params: TJSONObject);
    procedure EditSize(const Method: string; Params: TJSONObject);
  public
    constructor Create;
    destructor Destroy; override;
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData;
  end;

implementation

uses
  SysUtils, Math, Sloper.API.Rpc, Sloper.API.Server, Sloper.Core.JSON, Sloper.Core.Measurements;

resourcestring
  rsInvalidValue = 'Enter a finite measurement value';
  rsIndexOutOfRange = '%s is out of range';

function IndexParam(Params: TJSONObject; const Name: string; Count: integer): integer;
begin
  if not GetJSONInteger(Params, Name, Result) or (Result < 0) or (Result >= Count) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsIndexOutOfRange, [Name]));
end;

constructor TMeasurementApiServer.Create;
begin
  inherited Create;
  FDocument := TMeasurementDocument.Create;
end;

destructor TMeasurementApiServer.Destroy;
begin
  FreeAndNil(FDocument);
  inherited Destroy;
end;

procedure TMeasurementApiServer.EditRow(const Method: string; Params: TJSONObject);
var
  Row, Column, Count: integer;
  Value: double;
  Error: string;
begin
  Count := FDocument.Measurements.Count;
  Row := IndexParam(Params, 'row', Count);
  case Method of
    'measure_rename_row': if not FDocument.RenameKey(Row, RequireString(Params, 'text'), Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_describe_row': FDocument.SetDescription(Row, RequireString(Params, 'text'));
    'measure_delete_row': FDocument.DeleteMeasurement(Row);
    'measure_move_row': FDocument.MoveMeasurement(Row, IndexParam(Params, 'target', Count));
    'measure_set_value':
    begin
      Column := IndexParam(Params, 'column', Max(1, FDocument.Measurements.SizeCount));
      if OptionalNumber(Params, 'value', Value) then
      begin
        if IsNan(Value) or IsInfinite(Value) then
          raise EApiError.Create(RPC_INVALID_PARAMS, rsInvalidValue);
        FDocument.SetValue(Row, Column, Value);
      end
      else if not FDocument.ClearValue(Row, Column, Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    end;
  end;
end;

procedure TMeasurementApiServer.EditSize(const Method: string; Params: TJSONObject);
var
  Column, Count: integer;
  Error: string;
begin
  Count := FDocument.Measurements.SizeCount;
  Column := IndexParam(Params, 'column', Count);
  case Method of
    'measure_rename_size': if not FDocument.RenameSize(Column, RequireString(Params, 'text'), Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_delete_size': if not FDocument.DeleteSize(Column, Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_move_size': FDocument.MoveSize(Column, IndexParam(Params, 'target', Count));
  end;
end;

function TMeasurementApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
var
  Error, Size: string;
  Missing: TMissingMeasurement;
  List, Sizes: TJSONArray;
  Answer: TJSONObject;
begin
  case Method of
    'measure_state': ;
    'measure_new': FDocument.New;
    'measure_open': if not FDocument.OpenText(RequireString(Params, 'text'), Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_undo': FDocument.Undo;
    'measure_redo': FDocument.Redo;
    'measure_name': FDocument.SetName(RequireString(Params, 'text'));
    'measure_notes': FDocument.SetNotes(RequireString(Params, 'text'));
    'measure_add_row': FDocument.AddMeasurement;
    'measure_add_known':
      if not FDocument.AddKnown(RequireString(Params, 'key'), RequireString(Params, 'description'), Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_check_pattern':
      if not FDocument.UsePatternText(RequireString(Params, 'text'), Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_clear_pattern': FDocument.UsePattern('', Error);
    'measure_add_size': if not FDocument.AddSize(RequireString(Params, 'text'), Error) then
        raise EApiError.Create(RPC_REFUSED, Error);
    'measure_rename_row', 'measure_describe_row', 'measure_delete_row', 'measure_move_row', 'measure_set_value':
      EditRow(Method, Params);
    'measure_rename_size', 'measure_delete_size', 'measure_move_size': EditSize(Method, Params);
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Method);
  end;
  Answer := TJSONObject.Create(['text', FDocument.SnapshotText, 'canUndo', FDocument.CanUndo, 'canRedo', FDocument.CanRedo]);
  try
    List := TJSONArray.Create;
    Answer.Add('missing', List);
    for Missing in FDocument.Missing do
    begin
      Sizes := TJSONArray.Create;
      List.Add(TJSONObject.Create(['key', Missing.Key, 'sizes', Sizes]));
      for Size in Missing.Sizes do
        Sizes.Add(Size);
    end;
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

end.
