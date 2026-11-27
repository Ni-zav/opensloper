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


// The web Measurements page's independent measurement document.
unit Sloper.API.MeasurementsServer;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson, Sloper.API.Methods, Sloper.Document.MeasurementDocument;

type
  TMeasurementsApiServer = class
  private
    FDocument: TMeasurementDocument;
    function State: TJSONData;
  public
    constructor Create;
    destructor Destroy; override;
    function CallMethod(const Method: string; Params: TJSONObject): TJSONData;
  end;

const
  MEASUREMENTS_PREFIX = 'measurements_';

function MeasurementsMethods: TApiMethodArray;

implementation

uses
  SysUtils, Sloper.API.Rpc, Sloper.API.Server, Sloper.Core.JSON;

resourcestring
  rsMeasurementsOpen = 'Opens a measurement set supplied by the browser';
  rsMeasurementsText = 'The contents of the .slm file';
  rsMeasurementsState = 'Reads the current measurement set';
  rsMeasurementsStateReturns = 'The current `set`, as in a .slm file';

function MeasurementsMethods: TApiMethodArray;
begin
  Result := nil;
  AddApiMethod(Result, 'measurements_open', rsMeasurementsOpen, rsMeasurementsStateReturns);
  AddApiParam(Result, 'text', apText, True, rsMeasurementsText);
  AddApiMethod(Result, 'measurements_state', rsMeasurementsState, rsMeasurementsStateReturns, True);
end;

constructor TMeasurementsApiServer.Create;
begin
  inherited Create;
  FDocument := TMeasurementDocument.Create;
end;

destructor TMeasurementsApiServer.Destroy;
begin
  FreeAndNil(FDocument);
  inherited Destroy;
end;

function TMeasurementsApiServer.State: TJSONData;
var
  Snapshot: TJSONObject;
  Reason: string;
begin
  if not ParseJSONObject(FDocument.SnapshotText, Snapshot, Reason) then
    raise EApiError.Create(RPC_INTERNAL_ERROR, Reason);
  Result := TJSONObject.Create(['set', Snapshot]);
end;

function TMeasurementsApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
var
  Reason: string;
begin
  case Method of
    'measurements_open':
      if not FDocument.OpenText(RequireString(Params, 'text'), Reason) then
        raise EApiError.Create(RPC_REFUSED, Reason);
    'measurements_state': ;
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
  Result := State;
end;

end.
