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
  fpjson, Sloper.API.Methods, Sloper.Core.Units, Sloper.Document.MeasurementDocument;

type
  TMeasurementsApiServer = class
  private
    FDocument: TMeasurementDocument;
    // The set as its file holds it, and as the table shows it in AUnit
    function State(AUnit: TMeasureUnit): TJSONData;
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
  SysUtils, Math, Sloper.API.Rpc, Sloper.API.Server, Sloper.Core.JSON, Sloper.Core.Measurements;

resourcestring
  rsMeasurementsOpen = 'Opens a measurement set supplied by the browser';
  rsMeasurementsText = 'The contents of the .slm file';
  rsMeasurementsUnit = 'The unit the table shows values in: mm (the default), cm or in';
  rsMeasurementsState = 'Reads the current measurement set';
  rsMeasurementsStateReturns = 'The current `set`, as in a .slm file, and the table as the page shows it: `unit`, ' +
    '`sizes` (none for a set without sizes) and `rows`, each with `key`, `values` (one for each size, or the one ' +
    'value, as text in the unit, empty where there is none) and `description`';

function MeasurementsMethods: TApiMethodArray;
begin
  Result := nil;
  AddApiMethod(Result, 'measurements_open', rsMeasurementsOpen, rsMeasurementsStateReturns);
  AddApiParam(Result, 'text', apText, True, rsMeasurementsText);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_state', rsMeasurementsState, rsMeasurementsStateReturns, True);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
end;

// The unit asked for, else mm, as the desktop's Show in box starts
function TableUnit(Params: TJSONObject): TMeasureUnit;
begin
  Result := muMillimetre;
  if Assigned(Params) and Assigned(Params.Find('unit')) then
    Result := TMeasureUnit(ChoiceParam(Params, 'unit', MEASURE_UNIT_NAMES));
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

// A row's values as the desktop's grid shows them: one a size, or the one
// value of a set without sizes, in AUnit
function TMeasurementsApiServer.State(AUnit: TMeasureUnit): TJSONData;
var
  Snapshot, Answer, Row: TJSONObject;
  Sizes, Rows, Values: TJSONArray;
  Table: TMeasurementSet;
  Index, Size: integer;
  Reason: string;
begin
  if not ParseJSONObject(FDocument.SnapshotText, Snapshot, Reason) then
    raise EApiError.Create(RPC_INTERNAL_ERROR, Reason);
  Answer := TJSONObject.Create(['set', Snapshot, 'unit', MEASURE_UNIT_NAMES[AUnit]]);
  try
    Table := FDocument.Measurements;
    Sizes := TJSONArray.Create;
    Answer.Add('sizes', Sizes);
    for Size := 0 to Table.SizeCount - 1 do
      Sizes.Add(Table.Sizes[Size]);
    Rows := TJSONArray.Create;
    Answer.Add('rows', Rows);
    for Index := 0 to Table.Count - 1 do
    begin
      Values := TJSONArray.Create;
      for Size := 0 to Max(Table.SizeCount, 1) - 1 do
        if Table[Index].HasValueFor(Size) then
          Values.Add(FormatMeasure(Table[Index].ValueFor(Size), AUnit))
        else
          Values.Add('');
      Row := TJSONObject.Create(['key', Table[Index].Key, 'values', Values, 'description', Table[Index].Description]);
      Rows.Add(Row);
    end;
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function TMeasurementsApiServer.CallMethod(const Method: string; Params: TJSONObject): TJSONData;
var
  Reason: string;
  AUnit: TMeasureUnit;
begin
  // A bad unit is refused before the set changes
  AUnit := TableUnit(Params);
  case Method of
    'measurements_open':
      if not FDocument.OpenText(RequireString(Params, 'text'), Reason) then
        raise EApiError.Create(RPC_REFUSED, Reason);
    'measurements_state': ;
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
  Result := State(AUnit);
end;

end.
