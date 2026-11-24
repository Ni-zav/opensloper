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

// What the Garment tab marks for the canvas's selection: selected pieces are
// outlined, and a selected seam is marked on both its sides, wherever they
// are, with the stitch line of a dart it closes. The desktop's tab draws
// these marks and the web editor gets them as lines (editor_garment_marks).
unit Sloper.Editor.Garment;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Garment, Sloper.Core.Pattern;

// The marks of the selection, by key; HoverPiece is left empty
function GarmentSelectionMarks(Pattern: TPattern; const Selection: TStringArray): TGarmentMarks;
// The lines of the scene a selected seam marks, in drawing order
function GarmentMarkedLines(const Scene: TGarmentScene; const Marks: TGarmentMarks): TPolylineArray;

implementation

uses
  Sloper.Core.Evaluator, Sloper.Core.Piece, Sloper.Core.Seam;

function GarmentSelectionMarks(Pattern: TPattern; const Selection: TStringArray): TGarmentMarks;
var
  Key: string;
  Node: TEvalNode;
  Seam: TSeamObject;
  Entry: TSeamEntry;
begin
  Result := Default(TGarmentMarks);
  for Key in Selection do
  begin
    Node := Pattern.FindNode(Key);
    if Node is TPieceObject then
      Insert(Key, Result.SelectedPieces, Length(Result.SelectedPieces))
    else if Node is TSeamObject then
    begin
      Seam := TSeamObject(Node);
      Insert(Seam.Key, Result.SeamKeys, Length(Result.SeamKeys));
      for Entry in Seam.SideA do
        Insert(Entry.PieceKey + ':' + Entry.EdgeKey, Result.SeamEdges, Length(Result.SeamEdges));
      for Entry in Seam.SideB do
        Insert(Entry.PieceKey + ':' + Entry.EdgeKey, Result.SeamEdges, Length(Result.SeamEdges));
    end;
  end;
end;

function GarmentMarkedLines(const Scene: TGarmentScene; const Marks: TGarmentMarks): TPolylineArray;
var
  Piece: TGarmentPiece;
  Line: TGarmentLine;
begin
  Result := nil;
  for Piece in Scene.Pieces do
  begin
    for Line in Piece.Edges do
      if GarmentEdgeMarked(Marks, Piece, Line) then
        Insert(Line.Points, Result, Length(Result));
    for Line in Piece.Stitches do
      if GarmentStitchMarked(Marks, Line) then
        Insert(Line.Points, Result, Length(Result));
  end;
end;

end.
