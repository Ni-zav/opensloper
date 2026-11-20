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

// Placing flat pieces round a body in 3D, for the drape app: a piece's frame
// and anchor, its placement (a move and a turn), mirrored copies and the
// camera that draws the scene. The frame has Blender's axes (see
// Sloper.Core.Geometry3): the body faces -Y, stands on Z = 0 and its centre
// line is the Z axis. Described in the design document under "Drape app and
// Blender export". No LCL dependency.
unit Sloper.Core.DrapePlacement;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.Piece;

type
  // A rigid move of a piece's frame into the body's: Rotation is turned first
  // (XYZ Euler angles in degrees, as Blender's rotation_euler), then the
  // anchor goes to Position (mm)
  TDrapePlacement = record
    Position: TVec3;
    Rotation: TVec3;
  end;

  // tvFront looks at the body's front (along +Y); tvLeft at its left side,
  // which is +X; tvThreeQuarter from the front and a little to its right
  TDrapeView = (tvFront, tvBack, tvLeft, tvRight, tvTop, tvThreeQuarter);

  // An orbit camera round Target. Yaw turns it about Z (turntable, so up stays
  // up), 0 in front of the body; Pitch raises it, 90 looking straight down.
  // Scale is screen pixels per mm. Distance, in mm from Target, is used only
  // with Perspective.
  TDrapeCamera = record
    Target: TVec3;
    Yaw, Pitch: double;
    Scale: double;
    Perspective: boolean;
    Distance: double;
    // Unit vectors of the screen's right and up, and the way the camera looks
    function Right: TVec3;
    function Up: TVec3;
    function Forward: TVec3;
    // Where a point falls on screen, relative to the middle of the view, x
    // right and y down, in pixels. Depth is mm along Forward from Target:
    // larger is farther away, for drawing back to front. False when a
    // perspective camera has the point behind it.
    function Project(const Point: TVec3; out Screen: TVec2; out Depth: double): boolean;
    // The move in the plane facing the camera, through Target, that a drag of
    // Delta pixels on screen makes
    function ScreenToWorld(const Delta: TVec2): TVec3;
  end;

// The piece's anchor in drafted coordinates: the middle of its grainline, else
// the middle of its seam line's extent. Computed, so a placement survives
// measurement changes.
function PieceAnchor(Piece: TPieceObject): TVec2;
// The seam line as the piece is placed: for a piece on a fold, opened out, the
// half as drafted followed by its mirror image across the fold
function PlacedSeamLine(Piece: TPieceObject): TVec2Array;
// For a piece on a fold, where PlacedSeamLine starts in its Outline: the end of
// the fold edge, which runs from the point before it. Of the Outline's Count
// points, point I is PlacedSeamLine's (I - Start) mod Count, and in mirror
// image Count - 1 + (Start - 1 - I) mod Count, but for the two fold ends,
// which it lists once. -1 when the piece is not on a fold.
function PlacedFoldStart(Piece: TPieceObject): integer;
// A drafted point in the piece's own frame: x along X, y (down) along -Z, the
// anchor at the origin and the right side of the fabric facing -Y. Mirrored
// (a second copy cut mirrored) turns x round, giving the left of a pair.
function PieceFramePoint(const Point, Anchor: TVec2; Mirrored: boolean): TVec3;
function PlacementMatrix(const Placement: TDrapePlacement): TMat3;
// A drafted point placed on the body
function PlacePoint(const Point, Anchor: TVec2; Mirrored: boolean; const Placement: TDrapePlacement): TVec3;
function PlacePoints(const Points: TVec2Array; const Anchor: TVec2; Mirrored: boolean; const Placement: TDrapePlacement): TVec3Array;
// The way the right side of the fabric faces once placed
function PlacedNormal(const Placement: TDrapePlacement): TVec3;
// The mirror image across the YZ plane, for the other copy of a mirrored pair
// placed as its partner's left or right
function MirroredPlacement(const Placement: TDrapePlacement): TDrapePlacement;
// The placement turned about Axis through its anchor, which stays put
function TurnedPlacement(const Placement: TDrapePlacement; const Axis: TVec3; AngleDeg: double): TDrapePlacement;
// The placement taken round the body's centre line (the Z axis) by AngleDeg,
// keeping its distance and height and turning with it, so a piece facing out
// keeps facing out
function RoundBodyPlacement(const Placement: TDrapePlacement; AngleDeg: double): TDrapePlacement;
// The angle to the nearest multiple of Step
function SnappedAngle(AngleDeg, Step: double): double;
// A placement standing upright in front of the body, facing the viewer
function UprightPlacement(const Position: TVec3): TDrapePlacement;
// The middle of a polygon's area; the middle of its extent when it has none
function PolygonMiddle(const Points: TVec2Array): TVec2;
// Where a piece goes to be sewn along a placed partner: its side of the seam,
// from EdgeStart to EdgeEnd as drafted, lies along the partner's, from
// PartnerStart to PartnerEnd as placed, Gap away from it. Flat, the piece lies
// beside its partner across the seam, as the two would lie sewn and opened
// out; Folded turns it over about the seam, onto the partner's side. Inside
// and PartnerInside are points inside each piece (drafted, and placed), which
// tell the two sides of the seam apart.
function AlignedPlacement(const PartnerStart, PartnerEnd, PartnerInside, PartnerNormal: TVec3;
  const EdgeStart, EdgeEnd, Inside, Anchor: TVec2; Mirrored: boolean; Gap: double; Folded: boolean): TDrapePlacement;
function DefaultDrapeCamera: TDrapeCamera;
// The camera turned to a view, keeping its target, scale and distance
function CameraForView(const Camera: TDrapeCamera; View: TDrapeView): TDrapeCamera;

implementation

uses
  Math;

const
  // A point this close (in mm) to the fold line is on it
  FOLD_TOLERANCE = 0.01;
  // Pixels per mm of a new camera
  DEFAULT_CAMERA_SCALE = 0.4;
  // mm from the target of a new perspective camera
  DEFAULT_CAMERA_DISTANCE = 3000;
  // Height (mm) a new camera looks at: about a body's middle
  DEFAULT_CAMERA_HEIGHT = 1000;
  // A perspective camera draws nothing closer than this, in mm
  NEAR_PLANE = 10;
  // Turns of the three-quarter view, in degrees
  THREE_QUARTER_YAW = -35;
  THREE_QUARTER_PITCH = 15;
  TOP_PITCH = 90;
  SIDE_YAW = 90;
  BACK_YAW = 180;

function PieceAnchor(Piece: TPieceObject): TVec2;
var
  Bounds: TRect2;
  Point: TVec2;
begin
  if (Piece.GrainKind <> gkNone) and (Piece.Grainline.Length > EPSILON) then
    Exit(Piece.Grainline.PointAt(0.5));
  Result := Vec2(0, 0);
  if Length(Piece.Outline) = 0 then
    Exit;
  Bounds.MinX := Infinity;
  Bounds.MinY := Infinity;
  Bounds.MaxX := -Infinity;
  Bounds.MaxY := -Infinity;
  for Point in Piece.Outline do
  begin
    Bounds.MinX := Min(Bounds.MinX, Point.X);
    Bounds.MinY := Min(Bounds.MinY, Point.Y);
    Bounds.MaxX := Max(Bounds.MaxX, Point.X);
    Bounds.MaxY := Max(Bounds.MaxY, Point.Y);
  end;
  Result := Vec2((Bounds.MinX + Bounds.MaxX) / 2, (Bounds.MinY + Bounds.MaxY) / 2);
end;

function OnLine(const Point: TVec2; const Line: TLine2): boolean;
begin
  Result := Distance(Point, Line.ClosestPoint(Point, True)) <= FOLD_TOLERANCE;
end;

function PlacedFoldStart(Piece: TPieceObject): integer;
var
  Outline: TVec2Array;
  Count, Index: integer;
  Fold: TLine2;
begin
  Result := -1;
  Outline := Piece.Outline;
  Count := Length(Outline);
  if not Piece.OnFold or (Count < 3) then
    Exit;
  Fold := Piece.FoldLine;
  for Index := 0 to Count - 1 do
    if OnLine(Outline[Index], Fold) and OnLine(Outline[(Index + 1) mod Count], Fold) then
      Exit((Index + 1) mod Count);
end;

function PlacedSeamLine(Piece: TPieceObject): TVec2Array;
var
  Outline: TVec2Array;
  Count, Start, Step: integer;
  Fold: TLine2;
begin
  Outline := Piece.Outline;
  Result := Copy(Outline);
  Count := Length(Outline);
  // The fold edge runs from Outline[Start - 1] to Outline[Start]; the half
  // goes from its end round to its start, then back in mirror image
  Start := PlacedFoldStart(Piece);
  if Start < 0 then
    Exit;
  Fold := Piece.FoldLine;
  Result := nil;
  SetLength(Result, 2 * Count - 2);
  for Step := 0 to Count - 1 do
    Result[Step] := Outline[(Start + Step) mod Count];
  // Back along the half in mirror image, leaving out the two fold ends
  for Step := 1 to Count - 2 do
    Result[Count - 1 + Step] := MirrorPoint(Outline[(Start + Count - 1 - Step) mod Count], Fold.P1, Fold.P2);
end;

function PieceFramePoint(const Point, Anchor: TVec2; Mirrored: boolean): TVec3;
begin
  Result := Vec3(Point.X - Anchor.X, 0, Anchor.Y - Point.Y);
  if Mirrored then
    Result.X := -Result.X;
end;

function PlacementMatrix(const Placement: TDrapePlacement): TMat3;
begin
  Result := EulerToMat3(Placement.Rotation);
end;

function PlacePoint(const Point, Anchor: TVec2; Mirrored: boolean; const Placement: TDrapePlacement): TVec3;
begin
  Result := PlacementMatrix(Placement).Apply(PieceFramePoint(Point, Anchor, Mirrored)) + Placement.Position;
end;

function PlacePoints(const Points: TVec2Array; const Anchor: TVec2; Mirrored: boolean; const Placement: TDrapePlacement): TVec3Array;
var
  Turn: TMat3;
  Index: integer;
begin
  Turn := PlacementMatrix(Placement);
  Result := nil;
  SetLength(Result, Length(Points));
  for Index := 0 to High(Points) do
    Result[Index] := Turn.Apply(PieceFramePoint(Points[Index], Anchor, Mirrored)) + Placement.Position;
end;

function PlacedNormal(const Placement: TDrapePlacement): TVec3;
begin
  Result := PlacementMatrix(Placement).Apply(Vec3(0, -1, 0));
end;

// With M the mirror across YZ, the copy's point is M (R l + P) for the
// original's frame point l, and the copy's frame point is M l, so its turn is
// M R M: turns about X stay, turns about Y and Z change sign
function MirroredPlacement(const Placement: TDrapePlacement): TDrapePlacement;
begin
  Result.Position := Vec3(-Placement.Position.X, Placement.Position.Y, Placement.Position.Z);
  Result.Rotation := Vec3(Placement.Rotation.X, -Placement.Rotation.Y, -Placement.Rotation.Z);
end;

function TurnedPlacement(const Placement: TDrapePlacement; const Axis: TVec3; AngleDeg: double): TDrapePlacement;
begin
  Result.Position := Placement.Position;
  Result.Rotation := Mat3ToEuler(Mat3Then(Mat3TurnAbout(Axis, AngleDeg), PlacementMatrix(Placement)));
end;

function RoundBodyPlacement(const Placement: TDrapePlacement; AngleDeg: double): TDrapePlacement;
var
  Turn: TMat3;
begin
  Turn := Mat3TurnZ(AngleDeg);
  Result.Position := Turn.Apply(Placement.Position);
  Result.Rotation := Mat3ToEuler(Mat3Then(Turn, PlacementMatrix(Placement)));
end;

function SnappedAngle(AngleDeg, Step: double): double;
begin
  Result := AngleDeg;
  if Step > 0 then
    Result := Round(AngleDeg / Step) * Step;
end;

function UprightPlacement(const Position: TVec3): TDrapePlacement;
begin
  Result.Position := Position;
  Result.Rotation := Vec3(0, 0, 0);
end;

function PolygonMiddle(const Points: TVec2Array): TVec2;
var
  Index: integer;
  Area, Step: double;
  Sum, Current, Following: TVec2;
begin
  Area := 0;
  Sum := Vec2(0, 0);
  for Index := 0 to High(Points) do
  begin
    Current := Points[Index];
    Following := Points[(Index + 1) mod Length(Points)];
    Step := Cross(Current, Following);
    Area := Area + Step;
    Sum := Sum + (Current + Following) * Step;
  end;
  if Abs(Area) > EPSILON then
    Exit(Sum * (1 / (3 * Area)));
  Result := Vec2(0, 0);
  if Length(Points) > 0 then
    Result := (Points[0] + Points[High(Points)]) * 0.5;
end;

// The part of Direction square to Along, with length 1
function SquareTo(const Direction, Along: TVec3): TVec3;
begin
  Result := (Direction - Along * Dot3(Direction, Along)).Normalized;
end;

function MatrixOfColumns(const First, Second, Third: TVec3): TMat3;
begin
  Result.M[0, 0] := First.X;
  Result.M[1, 0] := First.Y;
  Result.M[2, 0] := First.Z;
  Result.M[0, 1] := Second.X;
  Result.M[1, 1] := Second.Y;
  Result.M[2, 1] := Second.Z;
  Result.M[0, 2] := Third.X;
  Result.M[1, 2] := Third.Y;
  Result.M[2, 2] := Third.Z;
end;

// The rotation taking the right-handed basis (A1, A2, A1 x A2) to (B1, B2,
// B1 x B2); the A and B pairs are each square and of length 1
function BasisTurn(const A1, A2, B1, B2: TVec3): TMat3;
begin
  Result := Mat3Then(MatrixOfColumns(B1, B2, Cross3(B1, B2)), MatrixOfColumns(A1, A2, Cross3(A1, A2)).Transposed);
end;

function AlignedPlacement(const PartnerStart, PartnerEnd, PartnerInside, PartnerNormal: TVec3;
  const EdgeStart, EdgeEnd, Inside, Anchor: TVec2; Mirrored: boolean; Gap: double; Folded: boolean): TDrapePlacement;
var
  FrameStart, FrameEnd, FrameMiddle, FrameAlong, FrameInward: TVec3;
  SeamMiddle, Along, PartnerInward, Outward, Target: TVec3;
  Turn: TMat3;
begin
  // The moving piece's seam and the way into it, in its own frame
  FrameStart := PieceFramePoint(EdgeStart, Anchor, Mirrored);
  FrameEnd := PieceFramePoint(EdgeEnd, Anchor, Mirrored);
  FrameMiddle := (FrameStart + FrameEnd) * 0.5;
  FrameAlong := (FrameEnd - FrameStart).Normalized;
  FrameInward := SquareTo(PieceFramePoint(Inside, Anchor, Mirrored) - FrameMiddle, FrameAlong);
  // The partner's seam and the way into it, kept in the partner's plane
  SeamMiddle := (PartnerStart + PartnerEnd) * 0.5;
  Along := (PartnerEnd - PartnerStart).Normalized;
  PartnerInward := SquareTo(PartnerInside - SeamMiddle - PartnerNormal.Normalized * Dot3(PartnerInside - SeamMiddle,
    PartnerNormal.Normalized), Along);
  if Folded then
    Outward := PartnerInward
  else
    Outward := -PartnerInward;
  // Flat, the piece runs on away from the partner; folded, back over it
  Turn := BasisTurn(FrameAlong, FrameInward, Along, Outward);
  Target := SeamMiddle + Outward * Gap;
  if Folded then
    Target := SeamMiddle + Turn.Apply(Vec3(0, -1, 0)) * Gap;
  Result.Position := Target - Turn.Apply(FrameMiddle);
  Result.Rotation := Mat3ToEuler(Turn);
end;

{ TDrapeCamera }

function TDrapeCamera.Right: TVec3;
var
  SinYaw, CosYaw: double;
begin
  SinCos(DegToRad(Yaw), SinYaw, CosYaw);
  Result := Vec3(CosYaw, SinYaw, 0);
end;

function TDrapeCamera.Up: TVec3;
var
  SinYaw, CosYaw, SinPitch, CosPitch: double;
begin
  SinCos(DegToRad(Yaw), SinYaw, CosYaw);
  SinCos(DegToRad(Pitch), SinPitch, CosPitch);
  Result := Vec3(-SinYaw * SinPitch, CosYaw * SinPitch, CosPitch);
end;

function TDrapeCamera.Forward: TVec3;
var
  SinYaw, CosYaw, SinPitch, CosPitch: double;
begin
  SinCos(DegToRad(Yaw), SinYaw, CosYaw);
  SinCos(DegToRad(Pitch), SinPitch, CosPitch);
  Result := Vec3(-SinYaw * CosPitch, CosYaw * CosPitch, -SinPitch);
end;

function TDrapeCamera.Project(const Point: TVec3; out Screen: TVec2; out Depth: double): boolean;
var
  Offset: TVec3;
  Factor: double;
begin
  Offset := Point - Target;
  Depth := Dot3(Offset, Forward);
  Factor := Scale;
  Result := True;
  if Perspective then
  begin
    Result := Distance + Depth >= NEAR_PLANE;
    Factor := Scale * Distance / Max(Distance + Depth, NEAR_PLANE);
  end;
  Screen := Vec2(Dot3(Offset, Right) * Factor, -Dot3(Offset, Up) * Factor);
end;

function TDrapeCamera.ScreenToWorld(const Delta: TVec2): TVec3;
begin
  Result := (Right * Delta.X - Up * Delta.Y) * (1 / Scale);
end;

function DefaultDrapeCamera: TDrapeCamera;
begin
  Result := Default(TDrapeCamera);
  Result.Target := Vec3(0, 0, DEFAULT_CAMERA_HEIGHT);
  Result.Scale := DEFAULT_CAMERA_SCALE;
  Result.Distance := DEFAULT_CAMERA_DISTANCE;
end;

function CameraForView(const Camera: TDrapeCamera; View: TDrapeView): TDrapeCamera;
begin
  Result := Camera;
  Result.Pitch := 0;
  case View of
    tvFront:
      Result.Yaw := 0;
    tvBack:
      Result.Yaw := BACK_YAW;
    tvLeft:
      Result.Yaw := SIDE_YAW;
    tvRight:
      Result.Yaw := -SIDE_YAW;
    tvTop:
    begin
      Result.Yaw := 0;
      Result.Pitch := TOP_PITCH;
    end;
    tvThreeQuarter:
    begin
      Result.Yaw := THREE_QUARTER_YAW;
      Result.Pitch := THREE_QUARTER_PITCH;
    end;
  end;
end;

end.
