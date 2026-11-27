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
    function State(AUnit: TMeasureUnit): TJSONObject;
    // The measurement with the key given, refused when there is none
    function KeyIndex(Params: TJSONObject): integer;
    function DoSet(Params: TJSONObject; AUnit: TMeasureUnit): TJSONObject;
    function DoAdd(AUnit: TMeasureUnit): TJSONObject;
    function DoMove(Params: TJSONObject): boolean;
    // The size given by its index, refused when there is none
    function SizeIndex(Params: TJSONObject; const Name: string): integer;
    procedure DoSizeEdit(const Method: string; Params: TJSONObject);
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
  rsMeasurementsSet = 'A cell of the table as typed: a key renames the measurement, a value is a number in ' +
    '`unit`, or blank to clear it in a size table, and a description is kept as typed; one undo step. A refused ' +
    'edit answers `done` false with the `reason`';
  rsMeasurementsSetReturns = '`done`, `reason`, the measurement''s `key` afterwards, and the state, as ' +
    'measurements_state';
  rsMeasurementsKey = 'The measurement, by its key';
  rsMeasurementsColumn = 'Which cell: key, value or description';
  rsMeasurementsSize = 'For a value, the size by its index; 0 in a set without sizes';
  rsMeasurementsCellText = 'The cell''s text as typed';
  rsMeasurementsAdd = 'Adds a measurement at the end with a free key and no description, for its key to be typed; ' +
    'one undo step';
  rsMeasurementsAddReturns = 'Its `key`, and the state, as measurements_state';
  rsMeasurementsDelete = 'Deletes a measurement; one undo step. Patterns using it show it as missing';
  rsMeasurementsMove = 'Moves a measurement to another place in the table; one undo step';
  rsMeasurementsIndex = 'Its place afterwards, from 0';
  rsMeasurementsUndo = 'Undoes the last change to the set';
  rsMeasurementsRedo = 'Makes the change undone again';
  rsMeasurementsEditReturns = 'The state, as measurements_state';
  rsMeasurementsAddSize = 'Adds a size at the end of the table: a set without sizes becomes a size table, its ' +
    'values the new size''s; one undo step';
  rsMeasurementsSizeName = 'The size''s name, such as 12 or M';
  rsMeasurementsRenameSize = 'Renames a size; one undo step';
  rsMeasurementsDeleteSize = 'Deletes a size and its values; one undo step. The last size cannot be deleted';
  rsMeasurementsMoveSize = 'Moves a size to another column; one undo step';
  rsMeasurementsSizeIndex = 'The size, by its index from 0';
  rsMeasurementsSizePlace = 'Its index afterwards, from 0';
  rsMeasurementsNoKey = 'There is no measurement @%s';
  rsMeasurementsNothingToUndo = 'There is nothing to undo';
  rsMeasurementsNothingToRedo = 'There is nothing to redo';
  rsMeasurementsStateReturns = 'The current `set`, as in a .slm file, and the table as the page shows it: `unit`, ' +
    '`sizes` (none for a set without sizes) and `rows`, each with `key`, `values` (one for each size, or the one ' +
    'value, as text in the unit, empty where there is none) and `description`; `modified`, `canUndo`, `canRedo` ' +
    'and `undo`, the name of the step Undo would take';

function MeasurementsMethods: TApiMethodArray;
begin
  Result := nil;
  AddApiMethod(Result, 'measurements_open', rsMeasurementsOpen, rsMeasurementsStateReturns);
  AddApiParam(Result, 'text', apText, True, rsMeasurementsText);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_state', rsMeasurementsState, rsMeasurementsStateReturns, True);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_set', rsMeasurementsSet, rsMeasurementsSetReturns);
  AddApiParam(Result, 'key', apText, True, rsMeasurementsKey);
  AddApiParam(Result, 'column', apChoice, True, rsMeasurementsColumn, 'key, value, description');
  AddApiParam(Result, 'size', apNumber, False, rsMeasurementsSize);
  AddApiParam(Result, 'text', apText, True, rsMeasurementsCellText);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_add', rsMeasurementsAdd, rsMeasurementsAddReturns);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_delete', rsMeasurementsDelete, rsMeasurementsEditReturns);
  AddApiParam(Result, 'key', apText, True, rsMeasurementsKey);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_move', rsMeasurementsMove, rsMeasurementsEditReturns);
  AddApiParam(Result, 'key', apText, True, rsMeasurementsKey);
  AddApiParam(Result, 'index', apNumber, True, rsMeasurementsIndex);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_add_size', rsMeasurementsAddSize, rsMeasurementsEditReturns);
  AddApiParam(Result, 'name', apText, True, rsMeasurementsSizeName);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_rename_size', rsMeasurementsRenameSize, rsMeasurementsEditReturns);
  AddApiParam(Result, 'size', apNumber, True, rsMeasurementsSizeIndex);
  AddApiParam(Result, 'name', apText, True, rsMeasurementsSizeName);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_delete_size', rsMeasurementsDeleteSize, rsMeasurementsEditReturns);
  AddApiParam(Result, 'size', apNumber, True, rsMeasurementsSizeIndex);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_move_size', rsMeasurementsMoveSize, rsMeasurementsEditReturns);
  AddApiParam(Result, 'size', apNumber, True, rsMeasurementsSizeIndex);
  AddApiParam(Result, 'index', apNumber, True, rsMeasurementsSizePlace);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_undo', rsMeasurementsUndo, rsMeasurementsEditReturns);
  AddApiParam(Result, 'unit', apChoice, False, rsMeasurementsUnit, string.Join(', ', MEASURE_UNIT_NAMES));
  AddApiMethod(Result, 'measurements_redo', rsMeasurementsRedo, rsMeasurementsEditReturns);
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
function TMeasurementsApiServer.State(AUnit: TMeasureUnit): TJSONObject;
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
    Answer.Add('modified', FDocument.Modified);
    Answer.Add('canUndo', FDocument.CanUndo);
    Answer.Add('canRedo', FDocument.CanRedo);
    Answer.Add('undo', FDocument.UndoDescription);
    Result := Answer;
  except
    FreeAndNil(Answer);
    raise;
  end;
end;

function TMeasurementsApiServer.KeyIndex(Params: TJSONObject): integer;
var
  Key: string;
begin
  Key := RequireString(Params, 'key');
  Result := FDocument.Measurements.IndexOf(Key);
  if Result < 0 then
    raise EApiError.Create(RPC_REFUSED, Format(rsMeasurementsNoKey, [Key]));
end;

// As the desktop window commits a cell: a key trimmed, a value through
// SetValueText in the unit the table shows, a description as typed
function TMeasurementsApiServer.DoSet(Params: TJSONObject; AUnit: TMeasureUnit): TJSONObject;
var
  Index, Size: integer;
  Text, Reason: string;
  Done: boolean;
  SizeNumber: double;
begin
  Index := KeyIndex(Params);
  Text := RequireString(Params, 'text');
  Reason := '';
  case ChoiceParam(Params, 'column', ['key', 'value', 'description']) of
    0: Done := FDocument.RenameKey(Index, Trim(Text), Reason);
    1:
    begin
      SizeNumber := 0;
      OptionalNumber(Params, 'size', SizeNumber);
      Size := Round(SizeNumber);
      if (Size < 0) or (Size >= Max(FDocument.Measurements.SizeCount, 1)) then
        raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['size']));
      Done := FDocument.SetValueText(Index, Size, Text, AUnit, Reason);
    end;
    else
    begin
      FDocument.SetDescription(Index, Text);
      Done := True;
    end;
  end;
  Result := State(AUnit);
  Result.Add('done', Done);
  Result.Add('reason', Reason);
  Result.Add('key', FDocument.Measurements[Index].Key);
end;

function TMeasurementsApiServer.DoAdd(AUnit: TMeasureUnit): TJSONObject;
var
  Key: string;
begin
  Key := FDocument.AddMeasurement.Key;
  Result := State(AUnit);
  Result.Add('key', Key);
end;

// False when the place is outside the table
function TMeasurementsApiServer.DoMove(Params: TJSONObject): boolean;
var
  Index: integer;
  Place: double;
begin
  Index := KeyIndex(Params);
  Place := -1;
  OptionalNumber(Params, 'index', Place);
  Result := (Round(Place) >= 0) and (Round(Place) < FDocument.Measurements.Count);
  if Result and (Round(Place) <> Index) then
    FDocument.MoveMeasurement(Index, Round(Place));
end;

function TMeasurementsApiServer.SizeIndex(Params: TJSONObject; const Name: string): integer;
var
  Number: double;
begin
  Number := -1;
  OptionalNumber(Params, Name, Number);
  Result := Round(Number);
  if (Result < 0) or (Result >= FDocument.Measurements.SizeCount) then
    raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, [Name]));
end;

// As the desktop's size buttons: a name refused, or the last size, says why
procedure TMeasurementsApiServer.DoSizeEdit(const Method: string; Params: TJSONObject);
var
  Index: integer;
  Done: boolean;
  Reason: string;
begin
  Reason := '';
  Done := True;
  case Method of
    'measurements_add_size': Done := FDocument.AddSize(RequireString(Params, 'name'), Reason);
    'measurements_rename_size':
    begin
      Index := SizeIndex(Params, 'size');
      Done := FDocument.RenameSize(Index, RequireString(Params, 'name'), Reason);
    end;
    'measurements_delete_size': Done := FDocument.DeleteSize(SizeIndex(Params, 'size'), Reason);
    else
    begin
      Index := SizeIndex(Params, 'size');
      if SizeIndex(Params, 'index') <> Index then
        FDocument.MoveSize(Index, SizeIndex(Params, 'index'));
    end;
  end;
  if not Done then
    raise EApiError.Create(RPC_REFUSED, Reason);
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
    'measurements_set': Exit(DoSet(Params, AUnit));
    'measurements_add': Exit(DoAdd(AUnit));
    'measurements_delete': FDocument.DeleteMeasurement(KeyIndex(Params));
    'measurements_move':
      if not DoMove(Params) then
        raise EApiError.Create(RPC_INVALID_PARAMS, Format(rsApiMissingParam, ['index']));
    'measurements_add_size', 'measurements_rename_size', 'measurements_delete_size', 'measurements_move_size':
      DoSizeEdit(Method, Params);
    'measurements_undo':
    begin
      if not FDocument.CanUndo then
        raise EApiError.Create(RPC_REFUSED, rsMeasurementsNothingToUndo);
      FDocument.Undo;
    end;
    'measurements_redo':
    begin
      if not FDocument.CanRedo then
        raise EApiError.Create(RPC_REFUSED, rsMeasurementsNothingToRedo);
      FDocument.Redo;
    end;
    else
      raise EApiError.Create(RPC_METHOD_NOT_FOUND, Format(rsApiNoMethod, [Method]));
  end;
  Result := State(AUnit);
end;

end.
