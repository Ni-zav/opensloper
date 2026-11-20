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

// What the drape app's 3D view draws: the body's triangles and the placed
// pieces, projected by the camera, shaded and in order from back to front, so
// the view only fills polygons. No OpenGL: the pieces are flat and the body is
// one mesh. Pieces go in order of their middles' depth; each of the body's
// triangles goes after every piece whose plane it lies on the viewer's side
// of, which is exact for a piece clear of the body. Pieces that cross each
// other or the body may draw in the wrong order, which a placing tool can live
// with. No LCL dependency.
unit Sloper.Core.DrapeScene;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.Materials, Sloper.Core.DrapePlacement, Sloper.Core.DrapeFile,
  Sloper.Core.BodyForm;

type
  TDrapeFace = record
    // On screen, relative to the middle of the view, in pixels
    Points: TVec2Array;
    // The middle's distance along the camera's view, for the order
    Depth: double;
    Color: TMaterialColor;
    // The drape item a piece face shows; -1 for the body
    Item: integer;
    // A piece seen from its wrong side, drawn paler
    WrongSide: boolean;
  end;

  TDrapeFaceArray = array of TDrapeFace;

  // A seam's line between its sides, on screen as the faces are
  TDrapeLine = record
    From, Onto: TVec2;
  end;

  TDrapeLineArray = array of TDrapeLine;

// The scene from back to front. A drape with no body (or bkNone) draws only
// its pieces.
function BuildDrapeScene(Drape: TDrape; const Camera: TDrapeCamera): TDrapeFaceArray;
// The drape's seam links on screen, to draw over the faces
function DrapeSceneLines(Drape: TDrape; const Camera: TDrapeCamera): TDrapeLineArray;
// The index of the frontmost piece face under Point, or -1; the body is never
// picked
function DrapePieceAt(const Faces: TDrapeFaceArray; const Point: TVec2): integer;

implementation

uses
  Math, Sloper.Core.Piece, Sloper.Core.PatternSources, Sloper.Core.Garment;

const
  BODY_COLOR: TMaterialColor = (Red: 226; Green: 214; Blue: 196);
  // How bright a face is when it faces away from the light and towards it
  AMBIENT = 0.35;
  DIFFUSE = 0.65;
  // A piece seen from its wrong side goes this share of the way to white
  WRONG_SIDE_FADE = 0.55;
  // How far back (mm) an orthographic camera is taken to be, for telling which
  // side of a piece is nearer: further than anything is placed
  ORTHOGRAPHIC_VIEWER = 1e6;

function Shaded(const Color: TMaterialColor; Light: double): TMaterialColor;
begin
  Light := EnsureRange(Light, 0, 1);
  Result.Red := Round(Color.Red * Light);
  Result.Green := Round(Color.Green * Light);
  Result.Blue := Round(Color.Blue * Light);
end;

function Faded(const Color: TMaterialColor; Share: double): TMaterialColor;
begin
  Result.Red := Round(Color.Red + (255 - Color.Red) * Share);
  Result.Green := Round(Color.Green + (255 - Color.Green) * Share);
  Result.Blue := Round(Color.Blue + (255 - Color.Blue) * Share);
end;

type
  // A face with where it is in 3D: a body triangle's middle, or a piece's
  // plane through Middle facing Normal
  TSceneFace = record
    Face: TDrapeFace;
    Middle, Normal: TVec3;
  end;

  TSceneFaceArray = array of TSceneFace;

// Projects the points; False when any falls behind a perspective camera
function ProjectAll(const Camera: TDrapeCamera; const Points: array of TVec3; out Face: TDrapeFace): boolean;
var
  Index: integer;
  Depth, Total: double;
begin
  Face := Default(TDrapeFace);
  SetLength(Face.Points, Length(Points));
  Total := 0;
  for Index := 0 to High(Points) do
  begin
    if not Camera.Project(Points[Index], Face.Points[Index], Depth) then
      Exit(False);
    Total := Total + Depth;
  end;
  if Length(Points) > 0 then
    Face.Depth := Total / Length(Points);
  Result := True;
end;

function MiddleOf(const Points: array of TVec3): TVec3;
var
  Point: TVec3;
begin
  Result := Vec3(0, 0, 0);
  for Point in Points do
    Result := Result + Point;
  if Length(Points) > 0 then
    Result := Result * (1 / Length(Points));
end;

// Where the viewer is, for telling which side of a plane is nearer: far back
// along the view for an orthographic camera
function ViewerAt(const Camera: TDrapeCamera): TVec3;
begin
  if Camera.Perspective then
    Result := Camera.Target - Camera.Forward * Camera.Distance
  else
    Result := Camera.Target - Camera.Forward * ORTHOGRAPHIC_VIEWER;
end;

// The light comes from the camera, so what faces the viewer is brightest
function BodyFaces(Drape: TDrape; const Camera: TDrapeCamera): TSceneFaceArray;
var
  Measures: TBodyMeasures;
  Mesh: TBodyMesh;
  Triangle: TBodyTriangle;
  Normal, Toward: TVec3;
  Scene: TSceneFace;
  Corners: array[0..2] of TVec3;
begin
  Result := nil;
  if not Drape.BodyMeasures(Measures) then
    Exit;
  Mesh := BuildDressForm(Measures);
  Toward := -Camera.Forward;
  for Triangle in Mesh.Triangles do
  begin
    Corners[0] := Mesh.Vertices[Triangle.First];
    Corners[1] := Mesh.Vertices[Triangle.Second];
    Corners[2] := Mesh.Vertices[Triangle.Third];
    Normal := Cross3(Corners[1] - Corners[0], Corners[2] - Corners[0]).Normalized;
    // The mesh is closed, so its back faces are always hidden
    if Dot3(Normal, Toward) <= 0 then
      Continue;
    if not ProjectAll(Camera, Corners, Scene.Face) then
      Continue;
    Scene.Face.Item := -1;
    Scene.Face.Color := Shaded(BODY_COLOR, AMBIENT + DIFFUSE * Dot3(Normal, Toward));
    Scene.Middle := MiddleOf(Corners);
    Scene.Normal := Normal;
    Insert(Scene, Result, Length(Result));
  end;
end;

function PieceFaces(Drape: TDrape; const Camera: TDrapeCamera): TSceneFaceArray;
var
  Index: integer;
  Points: TVec3Array;
  Scene: TSceneFace;
  Piece: TPieceObject;
  Source: TPatternSource;
  Facing: double;
begin
  Result := nil;
  for Index := 0 to High(Drape.Items) do
  begin
    if not Drape.PlacedOutline(Drape.Items[Index].Piece, Points) or (Length(Points) < 3) then
      Continue;
    if not ProjectAll(Camera, Points, Scene.Face) then
      Continue;
    Drape.FindPiece(Drape.Items[Index].Piece, Piece);
    Source := Drape.FindSource(Drape.Items[Index].Piece.SourceId);
    Scene.Face.Item := Index;
    Scene.Normal := PlacedNormal(Drape.Items[Index].Placement);
    Scene.Middle := Drape.Items[Index].Placement.Position;
    Facing := -Dot3(Scene.Normal, Camera.Forward);
    Scene.Face.WrongSide := Facing < 0;
    Scene.Face.Color := Shaded(GarmentBaseColor(Source.Pattern.PieceLook(Piece)), AMBIENT + DIFFUSE * Abs(Facing));
    if Scene.Face.WrongSide then
      Scene.Face.Color := Faded(Scene.Face.Color, WRONG_SIDE_FADE);
    Insert(Scene, Result, Length(Result));
  end;
end;

procedure SortBackToFront(var Faces: TSceneFaceArray);

  procedure Sort(Low, High: integer);
  var
    Left, Right: integer;
    Pivot: double;
    Swap: TSceneFace;
  begin
    Left := Low;
    Right := High;
    Pivot := Faces[(Low + High) div 2].Face.Depth;
    repeat
      while Faces[Left].Face.Depth > Pivot do
        Inc(Left);
      while Faces[Right].Face.Depth < Pivot do
        Dec(Right);
      if Left <= Right then
      begin
        Swap := Faces[Left];
        Faces[Left] := Faces[Right];
        Faces[Right] := Swap;
        Inc(Left);
        Dec(Right);
      end;
    until Left > Right;
    if Low < Right then
      Sort(Low, Right);
    if Left < High then
      Sort(Left, High);
  end;

begin
  if Length(Faces) > 1 then
    Sort(0, High(Faces));
end;

function BuildDrapeScene(Drape: TDrape; const Camera: TDrapeCamera): TDrapeFaceArray;
var
  Body, Pieces: TSceneFaceArray;
  // Slots[k] is the body's triangles drawn after k pieces
  Slots: array of TSceneFaceArray;
  Viewer: TVec3;
  Index, PieceIndex, Slot: integer;
  Scene: TSceneFace;
begin
  Result := nil;
  Body := BodyFaces(Drape, Camera);
  Pieces := PieceFaces(Drape, Camera);
  SortBackToFront(Body);
  SortBackToFront(Pieces);
  Viewer := ViewerAt(Camera);
  Slots := nil;
  SetLength(Slots, Length(Pieces) + 1);
  for Scene in Body do
  begin
    Slot := 0;
    for PieceIndex := 0 to High(Pieces) do
      if Dot3(Scene.Middle - Pieces[PieceIndex].Middle, Pieces[PieceIndex].Normal) * Dot3(Viewer - Pieces[PieceIndex].Middle,
        Pieces[PieceIndex].Normal) > 0 then
        Slot := PieceIndex + 1;
    // Body is already back to front, so each slot stays in order
    Insert(Scene, Slots[Slot], Length(Slots[Slot]));
  end;
  for Index := 0 to High(Slots) do
  begin
    for Scene in Slots[Index] do
      Insert(Scene.Face, Result, Length(Result));
    if Index <= High(Pieces) then
      Insert(Pieces[Index].Face, Result, Length(Result));
  end;
end;

function DrapeSceneLines(Drape: TDrape; const Camera: TDrapeCamera): TDrapeLineArray;
var
  Link: TDrapeSeamLink;
  Line: TDrapeLine;
  Depth: double;
begin
  Result := nil;
  for Link in Drape.SeamLinks do
    if Camera.Project(Link.From, Line.From, Depth) and Camera.Project(Link.Onto, Line.Onto, Depth) then
      Insert(Line, Result, Length(Result));
end;

function DrapePieceAt(const Faces: TDrapeFaceArray; const Point: TVec2): integer;
var
  Index: integer;
begin
  for Index := High(Faces) downto 0 do
    if (Faces[Index].Item >= 0) and PointInPolygon(Point, Faces[Index].Points) then
      Exit(Faces[Index].Item);
  Result := -1;
end;

end.
