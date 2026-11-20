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

// A drape exported for Blender's cloth simulation: the scene file
// (NAME.blender.json) lists each placed copy as an object with its placement,
// material and colour, and the pairs of vertices each seam sews; the meshes
// are OBJ files beside it, the pieces' (NAME.pieces.obj) and the body's
// (NAME.body.obj). Each piece's mesh is in its own frame, its anchor at the
// origin (Sloper.Core.DrapePlacement), so its placement sets the Blender
// object's location and rotation_euler as they are; a mirrored copy is
// mirrored in its mesh, its triangles turned round so they face the right
// side of the fabric. The body is in the drape's frame. Everything is in mm,
// with Blender's axes; the texture coordinates are the piece's own, in metres.
// The script that drapes them in Blender (data/blender/drape.py) is copied
// beside them as NAME.blender.py. Described in the design document under "Drape app and Blender export".
unit Sloper.Output.DrapeExport;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Mesher, Sloper.Core.BodyForm, Sloper.Core.DrapeFile, Sloper.Core.DrapeMesh;

const
  // The mesh spacing allowed, in mm
  MIN_DRAPE_SPACING = 2;
  MAX_DRAPE_SPACING = 100;

type
  // The files of an export, all in one folder
  TDrapeExportFiles = record
    Scene, Pieces, Body, Script: string;
    // What the script saves once it has run
    Blend: string;
  end;

  // What is written: the drape meshed and paired, the items that become
  // objects, in order, and the body when there is one
  TDrapeExport = record
    Meshing: TDrapeMeshing;
    // The drape's item for each object
    ObjectItems: array of integer;
    HasBody: boolean;
    Body: TBodyMesh;
    // The drape's problems, then the meshing's: what is left out or left open
    Problems: TDrapeProblemArray;
  end;

// The scene file a drape file is exported to by default: NAME.blender.json
function DrapeExportTarget(const DrapeFile: string): string;
// The meshes' files beside the scene file
function DrapeExportFiles(const SceneFile: string): TDrapeExportFiles;
function BuildDrapeExport(Drape: TDrape; Spacing: double = DEFAULT_MESH_SPACING): TDrapeExport;
// Each object's name, as in both the scene and the pieces' OBJ
function DrapeObjectName(Drape: TDrape; Item: integer): string;
// The scene file's text; PiecesFile and BodyFile are the meshes' file names,
// relative to its folder
function DrapeSceneText(Drape: TDrape; const Exported: TDrapeExport; const PiecesFile, BodyFile: string; Spacing: double): string;
function DrapePiecesOBJ(Drape: TDrape; const Exported: TDrapeExport): string;
function BodyOBJ(const Mesh: TBodyMesh): string;
// Writes the scene and its meshes, the body's only when there is one, and a
// copy of ScriptSource, the Blender script; with none (or '') the script is
// left out, with a problem. False, with a message, when a file cannot be
// written.
function ExportDrape(Drape: TDrape; const SceneFile: string; Spacing: double; const ScriptSource: string; out Problems: TDrapeProblemArray;
  out ErrorMessage: string): boolean;

resourcestring
  rsDrapeExportNoScript = 'The Blender script is missing from the program''s data folder, so %s was not written';
  rsDrapeExportNotMeshed = '%s: %s (copy %d) could not be meshed, so it is left out';

implementation

uses
  fpjson, Generics.Collections, Sloper.Core.JSON, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.EvalTypes, Sloper.Core.Evaluator,
  Sloper.Core.Piece, Sloper.Core.Seam,
  Sloper.Core.Materials, Sloper.Core.Garment, Sloper.Core.PatternSources, Sloper.Core.DrapePlacement;

const
  // Decimals of a coordinate in an OBJ file: mm to a thousandth
  OBJ_DECIMALS = 3;
  // Texture coordinates are in metres, so a texture can be made to the
  // fabric's real size
  UV_PER_MM = 0.001;
  UV_DECIMALS = 6;
  BLEND_EXTENSION = '.blend';
  OBJ_HEADER = '# OpenSloper drape export, in mm with Blender''s axes (x left of the body, y to its back, z up)';

function DrapeExportTarget(const DrapeFile: string): string;
begin
  Result := ChangeFileExt(DrapeFile, BLENDER_EXTENSION);
end;

function DrapeExportFiles(const SceneFile: string): TDrapeExportFiles;
var
  Base: string;
begin
  Base := SceneFile;
  if Base.EndsWith(BLENDER_EXTENSION, True) then
    SetLength(Base, Length(Base) - Length(BLENDER_EXTENSION))
  else
    Base := ChangeFileExt(Base, '');
  Result.Scene := SceneFile;
  Result.Pieces := Base + BLENDER_PIECES_EXTENSION;
  Result.Body := Base + BLENDER_BODY_EXTENSION;
  Result.Script := Base + BLENDER_SCRIPT_EXTENSION;
  Result.Blend := Base + BLEND_EXTENSION;
end;

function ObjNumber(Value: double; Decimals: integer): string;
var
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  Settings.ThousandSeparator := #0;
  Result := FloatToStrF(Value, ffFixed, 15, Decimals, Settings);
  // Trailing zeros, then a bare point, go; -0 is 0
  if Pos('.', Result) > 0 then
  begin
    while Result.EndsWith('0') do
      SetLength(Result, Length(Result) - 1);
    if Result.EndsWith('.') then
      SetLength(Result, Length(Result) - 1);
  end;
  if Result = '-0' then
    Result := '0';
end;

function BuildDrapeExport(Drape: TDrape; Spacing: double): TDrapeExport;
var
  Item: integer;
  Measures: TBodyMeasures;
  Piece: TPieceObject;
  Problem: TDrapeProblem;
begin
  Result := Default(TDrapeExport);
  Result.Problems := Drape.Problems;
  Result.Meshing := MeshDrape(Drape, Spacing);
  for Item := 0 to High(Drape.Items) do
    if Length(Result.Meshing.Meshes[Item].Triangles) > 0 then
      Insert(Item, Result.ObjectItems, Length(Result.ObjectItems))
    // A piece that is gone or failing is already a problem of the drape's
    else if Drape.FindPiece(Drape.Items[Item].Piece, Piece) and (Piece.State = esValid) then
    begin
      Problem.Text := Format(rsDrapeExportNotMeshed, [ExtractFileName(Drape.FindSource(Drape.Items[Item].Piece.SourceId).PatternFile),
        Piece.DisplayName, Drape.Items[Item].Piece.Copy]);
      Problem.Item := Item;
      Insert(Problem, Result.Problems, Length(Result.Problems));
    end;
  for Problem in Result.Meshing.Problems do
    Insert(Problem, Result.Problems, Length(Result.Problems));
  Result.HasBody := Drape.BodyMeasures(Measures);
  if Result.HasBody then
    Result.Body := BuildBodyForm(Measures);
end;

function DrapeObjectName(Drape: TDrape; Item: integer): string;
var
  Piece: TPieceObject;
  Source: TPatternSource;
  PieceName: string;
begin
  Source := Drape.FindSource(Drape.Items[Item].Piece.SourceId);
  if Drape.FindPiece(Drape.Items[Item].Piece, Piece) then
    PieceName := Piece.DisplayName
  else
    PieceName := Drape.Items[Item].Piece.PieceKey;
  Result := Format('%s %s %d', [ChangeFileExt(ExtractFileName(Source.PatternFile), ''), PieceName, Drape.Items[Item].Piece.Copy]);
end;

function Vec3ToJSON(const Value: TVec3): TJSONArray;
begin
  Result := TJSONArray.Create;
  Result.Add(JSONFloat(Value.X));
  Result.Add(JSONFloat(Value.Y));
  Result.Add(JSONFloat(Value.Z));
end;

// The object each item becomes, -1 for one left out
function ObjectIndexes(Drape: TDrape; const Exported: TDrapeExport): TMeshIndexArray;
var
  Index: integer;
begin
  Result := nil;
  SetLength(Result, Length(Drape.Items));
  for Index := 0 to High(Result) do
    Result[Index] := -1;
  for Index := 0 to High(Exported.ObjectItems) do
    Result[Exported.ObjectItems[Index]] := Index;
end;

function SceneObject(Drape: TDrape; const Exported: TDrapeExport; Item: integer): TJSONObject;
var
  Piece: TPieceObject;
  Source: TPatternSource;
  Material: TPatternMaterial;
  Entry: TDrapeItem;
begin
  Entry := Drape.Items[Item];
  Drape.FindPiece(Entry.Piece, Piece);
  Source := Drape.FindSource(Entry.Piece.SourceId);
  Result := TJSONObject.Create;
  Result.Add('name', DrapeObjectName(Drape, Item));
  Result.Add('source', Entry.Piece.SourceId);
  Result.Add('piece', StrToInt(Entry.Piece.PieceKey));
  Result.Add('copy', Entry.Piece.Copy);
  Result.Add('mirrored', CopyIsMirrored(Piece, Entry.Piece.Copy));
  Material := Source.Pattern.MaterialOf(Piece);
  if Assigned(Material) then
    Result.Add('material', Material.Name);
  Result.Add('color', MaterialColorText(GarmentBaseColor(Source.Pattern.PieceLook(Piece))));
  Result.Add('vertices', Length(Exported.Meshing.Meshes[Item].Points));
  Result.Add('position', Vec3ToJSON(Entry.Placement.Position));
  Result.Add('rotation', Vec3ToJSON(Entry.Placement.Rotation));
end;

function SceneSeams(Drape: TDrape; const Exported: TDrapeExport): TJSONArray;
type
  TSeamIndex = specialize TDictionary<string, TJSONArray>;
var
  ObjectOf: TMeshIndexArray;
  Seams: TSeamIndex;
  Pair: TDrapeSeamPair;
  SeamKey: string;
  Pairs: TJSONArray;
  Seam: TJSONObject;
  Sewn: TJSONObject;
  Found: TEvalNode;
begin
  ObjectOf := ObjectIndexes(Drape, Exported);
  Result := TJSONArray.Create;
  Seams := TSeamIndex.Create;
  try
    for Pair in Exported.Meshing.Pairs do
    begin
      if (ObjectOf[Pair.FirstItem] < 0) or (ObjectOf[Pair.SecondItem] < 0) then
        Continue;
      SeamKey := Format('%d:%s', [Pair.SourceId, Pair.SeamKey]);
      if not Seams.TryGetValue(SeamKey, Pairs) then
      begin
        Seam := TJSONObject.Create;
        Result.Add(Seam);
        Seam.Add('source', Pair.SourceId);
        Seam.Add('seam', StrToInt(Pair.SeamKey));
        Found := Drape.FindSource(Pair.SourceId).Pattern.FindNode(Pair.SeamKey);
        if Found is TSeamObject then
          Seam.Add('name', TSeamObject(Found).DisplayName);
        Pairs := TJSONArray.Create;
        Seam.Add('pairs', Pairs);
        Seams.Add(SeamKey, Pairs);
      end;
      Sewn := TJSONObject.Create;
      Pairs.Add(Sewn);
      Sewn.Add('first', ObjectOf[Pair.FirstItem]);
      Sewn.Add('firstVertex', Pair.FirstVertex);
      Sewn.Add('second', ObjectOf[Pair.SecondItem]);
      Sewn.Add('secondVertex', Pair.SecondVertex);
    end;
  finally
    FreeAndNil(Seams);
  end;
end;

function DrapeSceneText(Drape: TDrape; const Exported: TDrapeExport; const PiecesFile, BodyFile: string; Spacing: double): string;
var
  Root: TJSONObject;
  Objects: TJSONArray;
  Item: integer;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', BLENDER_FORMAT);
    Root.Add('version', BLENDER_VERSION);
    Root.Add('units', 'mm');
    Root.Add('name', Drape.Name);
    Root.Add('pieces', PiecesFile);
    if Exported.HasBody then
      Root.Add('body', BodyFile);
    Root.Add('spacing', JSONFloat(Spacing));
    Objects := TJSONArray.Create;
    Root.Add('objects', Objects);
    for Item in Exported.ObjectItems do
      Objects.Add(SceneObject(Drape, Exported, Item));
    Root.Add('seams', SceneSeams(Drape, Exported));
    Result := JSONToText(Root);
  finally
    FreeAndNil(Root);
  end;
end;

function ObjVertex(const Point: TVec3): string;
begin
  Result := 'v ' + ObjNumber(Point.X, OBJ_DECIMALS) + ' ' + ObjNumber(Point.Y, OBJ_DECIMALS) + ' ' + ObjNumber(Point.Z, OBJ_DECIMALS);
end;

function DrapePiecesOBJ(Drape: TDrape; const Exported: TDrapeExport): string;
var
  Lines: TStringBuilder;
  Item, Index, Base, First, Third: integer;
  Piece: TPieceObject;
  Mesh: TFlatMesh;
  Anchor: TVec2;
  Mirrored: boolean;
  Frame: TVec3Array;
  Triangle: TMeshTriangle;
begin
  Lines := TStringBuilder.Create;
  try
    Lines.Append(OBJ_HEADER).Append(#10);
    Lines.Append('# Each piece in its own frame; its placement is in the scene file').Append(#10);
    // OBJ counts vertices from 1 across the whole file
    Base := 1;
    for Item in Exported.ObjectItems do
    begin
      Drape.FindPiece(Drape.Items[Item].Piece, Piece);
      Mesh := Exported.Meshing.Meshes[Item];
      Anchor := PieceAnchor(Piece);
      Mirrored := CopyIsMirrored(Piece, Drape.Items[Item].Piece.Copy);
      Lines.Append('o ').Append(DrapeObjectName(Drape, Item)).Append(#10);
      Frame := nil;
      SetLength(Frame, Length(Mesh.Points));
      for Index := 0 to High(Mesh.Points) do
      begin
        Frame[Index] := PieceFramePoint(Mesh.Points[Index], Anchor, Mirrored);
        Lines.Append(ObjVertex(Frame[Index])).Append(#10);
      end;
      // Seen from the right side of the fabric, as it would be worn
      for Index := 0 to High(Frame) do
        Lines.Append('vt ').Append(ObjNumber(Frame[Index].X * UV_PER_MM, UV_DECIMALS)).Append(' ').Append(
          ObjNumber(Frame[Index].Z * UV_PER_MM, UV_DECIMALS)).Append(#10);
      for Triangle in Mesh.Triangles do
      begin
        First := Triangle.First;
        Third := Triangle.Third;
        // The right side faces -Y in the piece's frame: anticlockwise seen from there
        if Cross3(Frame[Triangle.Second] - Frame[First], Frame[Third] - Frame[First]).Y > 0 then
        begin
          First := Triangle.Third;
          Third := Triangle.First;
        end;
        Lines.Append(Format('f %0:d/%0:d %1:d/%1:d %2:d/%2:d', [Base + First, Base + Triangle.Second, Base + Third])).Append(#10);
      end;
      Inc(Base, Length(Mesh.Points));
    end;
    Result := Lines.ToString;
  finally
    FreeAndNil(Lines);
  end;
end;

function BodyOBJ(const Mesh: TBodyMesh): string;
var
  Lines: TStringBuilder;
  Point: TVec3;
  Triangle: TBodyTriangle;
begin
  Lines := TStringBuilder.Create;
  try
    Lines.Append(OBJ_HEADER).Append(#10);
    Lines.Append('o body').Append(#10);
    for Point in Mesh.Vertices do
      Lines.Append(ObjVertex(Point)).Append(#10);
    for Triangle in Mesh.Triangles do
      Lines.Append(Format('f %d %d %d', [Triangle.First + 1, Triangle.Second + 1, Triangle.Third + 1])).Append(#10);
    Result := Lines.ToString;
  finally
    FreeAndNil(Lines);
  end;
end;

function ExportDrape(Drape: TDrape; const SceneFile: string; Spacing: double; const ScriptSource: string; out Problems: TDrapeProblemArray;
  out ErrorMessage: string): boolean;
var
  Files: TDrapeExportFiles;
  Exported: TDrapeExport;
  Script: string;
  Problem: TDrapeProblem;
begin
  Files := DrapeExportFiles(SceneFile);
  Exported := BuildDrapeExport(Drape, Spacing);
  Problems := Exported.Problems;
  ErrorMessage := '';
  Result := WriteTextFile(Files.Pieces, DrapePiecesOBJ(Drape, Exported), ErrorMessage) and
    (not Exported.HasBody or WriteTextFile(Files.Body, BodyOBJ(Exported.Body), ErrorMessage)) and
    WriteTextFile(Files.Scene, DrapeSceneText(Drape, Exported, ExtractFileName(Files.Pieces), ExtractFileName(Files.Body), Spacing),
    ErrorMessage);
  if not Result then
    Exit;
  if (ScriptSource = '') or not FileExists(ScriptSource) then
  begin
    Problem.Text := Format(rsDrapeExportNoScript, [ExtractFileName(Files.Script)]);
    Problem.Item := -1;
    Insert(Problem, Problems, Length(Problems));
  end
  else
    Result := ReadTextFile(ScriptSource, Script, ErrorMessage) and WriteTextFile(Files.Script, Script, ErrorMessage);
end;

end.
