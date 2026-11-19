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

// Features: sewing details applied to a pattern in one step, such as a zip
// in a seam. Each is made of ordinary objects, points, split edges,
// allowances, notches and lines, which the user can then change as if they
// had drawn them. Nothing here is saved as a feature.
unit Sloper.Core.Features;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Pattern;

type
  TFeatureKind = (fkZip);

  // Centred: topstitched either side of the seam. Invisible: sewn from the
  // inside, so nothing shows.
  TZipStyle = (zsCentred, zsInvisible);

  TZipSpec = record
    // An edge of one or more pieces, along which the zip opens
    EdgeKey: string;
    // The zip runs from the edge's end rather than its start
    FromEnd: boolean;
    // Formulas in the pattern's unit, with names: the zip's length, the
    // allowance along the opening, and how far the topstitching is from it
    Length, Allowance, StitchDistance: string;
    Style: TZipStyle;
  end;

  TZipMade = record
    // The point where the zip stops
    StopKey: string;
    // The edge's parts: along the zip, and the rest of the seam
    OpeningKey, RestKey: string;
    // The pieces the zip went into, and its topstitching on each
    PieceKeys, StitchKeys: array of string;
    // The edge is in a seam with another piece's edge, which needs a zip too
    OtherSide: boolean;
  end;

const
  ZIP_LENGTH_VARIABLE = 'zip_length';
  ZIP_STOP_NAME = 'ZipStop';

// A zip on the edge with the starting lengths in the pattern's unit, its
// length the zip_length variable, which InsertZip adds when it is missing
function DefaultZip(Pattern: TPattern; const EdgeKey: string): TZipSpec;
// Adds the zip's objects and evaluates. False, with the reason in
// Pattern.LastError, when it cannot go there; objects may have been added
// by then, so call it inside a document change and cancel that on failure.
function InsertZip(Pattern: TPattern; const Spec: TZipSpec; out Made: TZipMade): boolean;

resourcestring
  rsFeatureZip = 'Zip';
  rsFeatureZipLength = 'The length of the zip';
  rsFeatureNoEdge = 'Choose an edge of a piece for the zip';
  rsFeatureNotInPiece = '%s is in no piece; a zip goes along a piece''s edge';
  rsFeatureZipTooLong = 'The zip, %s long, does not fit along %s, which is %s';

implementation

uses
  SysUtils, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.EvalTypes, Sloper.Core.Units,
  Sloper.Core.Geometry;

function DefaultZip(Pattern: TPattern; const EdgeKey: string): TZipSpec;
begin
  Result := Default(TZipSpec);
  Result.EdgeKey := EdgeKey;
  Result.Length := '#' + ZIP_LENGTH_VARIABLE;
  Result.Allowance := STARTING_LENGTHS[slZipAllowance, Pattern.Units];
  Result.StitchDistance := STARTING_LENGTHS[slZipStitch, Pattern.Units];
  Result.Style := zsCentred;
end;

// The pieces whose outline runs along the edge
function PiecesOn(Pattern: TPattern; const EdgeKey: string): TPieceObjectArray;
var
  Index: integer;
begin
  Result := nil;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if (Pattern.Objects[Index] is TPieceObject) and (TPieceObject(Pattern.Objects[Index]).PathIndexOf(EdgeKey) >= 0) then
      Insert(TPieceObject(Pattern.Objects[Index]), Result, Length(Result));
end;

// Whether a seam joins the edge to an edge it is not
function SeamedToAnother(Pattern: TPattern; const EdgeKey: string): boolean;
var
  Index: integer;
  Seam: TSeamObject;
  Entry: TSeamEntry;
  OnA, OnB: boolean;
begin
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TSeamObject then
    begin
      Seam := TSeamObject(Pattern.Objects[Index]);
      OnA := False;
      OnB := False;
      for Entry in Seam.SideA do
        OnA := OnA or (Entry.EdgeKey = EdgeKey);
      for Entry in Seam.SideB do
        OnB := OnB or (Entry.EdgeKey = EdgeKey);
      if OnA <> OnB then
        Exit(True);
    end;
  Result := False;
end;

function StopName(Pattern: TPattern): string;
var
  Number: integer;
begin
  Result := ZIP_STOP_NAME;
  Number := 1;
  while Assigned(Pattern.FindObject(Result)) do
  begin
    Inc(Number);
    Result := ZIP_STOP_NAME + IntToStr(Number);
  end;
end;

// The zip_length variable the starting formula names, when it is missing
function AddLengthVariable(Pattern: TPattern; const Spec: TZipSpec): boolean;
begin
  Result := True;
  if (Pos(LowerCase('#' + ZIP_LENGTH_VARIABLE), LowerCase(Spec.Length)) > 0) and not Assigned(Pattern.FindVariable(ZIP_LENGTH_VARIABLE)) then
    Result := Assigned(Pattern.AddVariable(ZIP_LENGTH_VARIABLE, STARTING_LENGTHS[slZipLength, Pattern.Units], rsFeatureZipLength));
end;

// The zip's stop, checked to lie inside the edge rather than at or past an end
function AddStop(Pattern: TPattern; Edge: TEdgeObject; const Spec: TZipSpec; out Stop: TDraftObject): boolean;
var
  Value: double;
begin
  Stop := Pattern.AddAlongEdgePoint(StopName(Pattern), Edge.Key, Spec.FromEnd, amLength, Spec.Length);
  if not Assigned(Stop) then
    Exit(False);
  Pattern.Evaluate;
  if not Pattern.EvaluateText(Spec.Length, Value) then
    Exit(False);
  Value := Value * MILLIMETRES_PER_UNIT[Pattern.Units];
  if (Stop.State <> esValid) or (Value <= DEFAULT_TOLERANCE) or (Value >= Edge.Length - DEFAULT_TOLERANCE) then
    Exit(Pattern.Refuse(Format(rsFeatureZipTooLong, [LengthWithUnit(Value, Pattern.Units), Edge.DisplayName,
      LengthWithUnit(Edge.Length, Pattern.Units)])));
  Result := True;
end;

// On each piece: the opening's allowance, a notch at the stop, and for a
// centred zip the topstitching inside the piece
function FinishPieces(Pattern: TPattern; const Pieces: TPieceObjectArray; const Spec: TZipSpec; var Made: TZipMade): boolean;
var
  Piece: TPieceObject;
  Run: TRunEdgeArray;
  Side: TOffsetSide;
  Stitch: TOffsetEdge;
begin
  for Piece in Pieces do
  begin
    Insert(Piece.Key, Made.PieceKeys, Length(Made.PieceKeys));
    if (Spec.Allowance <> '') and not Pattern.SetEdgeAllowance(Piece, Piece.PathIndexOf(Made.OpeningKey), Spec.Allowance) then
      Exit(False);
    if not Pattern.AddPointNotch(Piece, Made.StopKey) then
      Exit(False);
    if (Spec.Style = zsCentred) and (Spec.StitchDistance <> '') then
    begin
      if not Pattern.PieceRun(Piece, [Made.OpeningKey], True, Run, Side) then
        Exit(False);
      // The side is the run's, which may go against the way the edge was drawn
      Stitch := Pattern.AddOffsetRun(Run, Spec.StitchDistance, Side, erStitch);
      if not Assigned(Stitch) then
        Exit(False);
      Insert(Stitch.Key, Made.StitchKeys, Length(Made.StitchKeys));
    end;
  end;
  Result := True;
end;

function InsertZip(Pattern: TPattern; const Spec: TZipSpec; out Made: TZipMade): boolean;
var
  Node: TObject;
  Edge: TEdgeObject;
  Pieces: TPieceObjectArray;
  Stop: TDraftObject;
  First, Second: TSplitPart;
begin
  Made := Default(TZipMade);
  Node := Pattern.FindNode(Spec.EdgeKey);
  if not (Node is TEdgeObject) then
    Exit(Pattern.Refuse(rsFeatureNoEdge));
  Edge := TEdgeObject(Node);
  Pieces := PiecesOn(Pattern, Edge.Key);
  if Length(Pieces) = 0 then
    Exit(Pattern.Refuse(Format(rsFeatureNotInPiece, [Edge.DisplayName])));
  Made.OtherSide := SeamedToAnother(Pattern, Edge.Key);
  if not AddLengthVariable(Pattern, Spec) or not AddStop(Pattern, Edge, Spec, Stop) then
    Exit(False);
  Made.StopKey := Stop.Key;
  if not Pattern.SplitEdge(Edge.Key, Stop.Key, First, Second) then
    Exit(False);
  if Spec.FromEnd then
  begin
    Made.OpeningKey := Second.Key;
    Made.RestKey := First.Key;
  end
  else
  begin
    Made.OpeningKey := First.Key;
    Made.RestKey := Second.Key;
  end;
  Pattern.Evaluate;
  Result := FinishPieces(Pattern, Pieces, Spec, Made);
  Pattern.Evaluate;
end;

end.
