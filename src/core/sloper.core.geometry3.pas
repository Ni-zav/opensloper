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

// Basic 3D geometry for the drape app: vectors, rotation matrices and Euler
// angles. The axes are Blender's: X to the right, Y away from the viewer, Z up,
// in mm, right-handed. A turn about an axis is anticlockwise in degrees as seen
// looking from the positive end of that axis towards the origin, as in Blender.
// Unlike the 2D units this is not screen space. No LCL dependency.
unit Sloper.Core.Geometry3;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}

interface

type
  TVec3 = record
    X, Y, Z: double;
    function Length: double;
    // The same direction with length 1; a zero vector stays zero
    function Normalized: TVec3;
    class operator +(const A, B: TVec3): TVec3;
    class operator -(const A, B: TVec3): TVec3;
    class operator -(const A: TVec3): TVec3;
    class operator *(const A: TVec3; S: double): TVec3;
  end;

  TVec3Array = array of TVec3;

  // Rows of a 3 by 3 matrix: applied to a column vector, X' = M[0] . V
  TMat3 = record
    M: array[0..2, 0..2] of double;
    function Apply(const V: TVec3): TVec3;
    function Transposed: TMat3;
  end;

function Vec3(AX, AY, AZ: double): TVec3; inline;
function Dot3(const A, B: TVec3): double; inline;
function Cross3(const A, B: TVec3): TVec3;
function Distance3(const A, B: TVec3): double;
function PointsNear3(const A, B: TVec3; Tolerance: double): boolean;

function Mat3Identity: TMat3;
// A first, then B
function Mat3Then(const B, A: TMat3): TMat3;
function Mat3TurnX(AngleDeg: double): TMat3;
function Mat3TurnY(AngleDeg: double): TMat3;
function Mat3TurnZ(AngleDeg: double): TMat3;
// A turn about an axis through the origin, anticlockwise looking from the
// axis's head towards the origin; a zero axis gives no turn
function Mat3TurnAbout(const Axis: TVec3; AngleDeg: double): TMat3;
// Turns about X, then Y, then Z, each about the fixed axes: Blender's XYZ
// Euler order, so the same three numbers set rotation_euler there
function EulerToMat3(const Angles: TVec3): TMat3;
// The XYZ Euler angles of a rotation matrix, each in (-180, 180]; at gimbal
// lock (Y at +-90) X is 0
function Mat3ToEuler(const R: TMat3): TVec3;

implementation

uses
  Math, Sloper.Core.Geometry;

const
  // Below this cos(Y) is treated as gimbal lock
  GIMBAL_EPSILON = 1e-9;

function Vec3(AX, AY, AZ: double): TVec3;
begin
  Result.X := AX;
  Result.Y := AY;
  Result.Z := AZ;
end;

function TVec3.Length: double;
begin
  Result := Sqrt(X * X + Y * Y + Z * Z);
end;

function TVec3.Normalized: TVec3;
var
  L: double;
begin
  L := Length;
  if L < EPSILON then
    Result := Self
  else
    Result := Vec3(X / L, Y / L, Z / L);
end;

class operator TVec3.+(const A, B: TVec3): TVec3;
begin
  Result := Vec3(A.X + B.X, A.Y + B.Y, A.Z + B.Z);
end;

class operator TVec3.-(const A, B: TVec3): TVec3;
begin
  Result := Vec3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

class operator TVec3.-(const A: TVec3): TVec3;
begin
  Result := Vec3(-A.X, -A.Y, -A.Z);
end;

class operator TVec3.*(const A: TVec3; S: double): TVec3;
begin
  Result := Vec3(A.X * S, A.Y * S, A.Z * S);
end;

function TMat3.Apply(const V: TVec3): TVec3;
begin
  Result.X := M[0, 0] * V.X + M[0, 1] * V.Y + M[0, 2] * V.Z;
  Result.Y := M[1, 0] * V.X + M[1, 1] * V.Y + M[1, 2] * V.Z;
  Result.Z := M[2, 0] * V.X + M[2, 1] * V.Y + M[2, 2] * V.Z;
end;

function TMat3.Transposed: TMat3;
var
  Row, Col: integer;
begin
  for Row := 0 to 2 do
    for Col := 0 to 2 do
      Result.M[Row, Col] := M[Col, Row];
end;

function Dot3(const A, B: TVec3): double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function Cross3(const A, B: TVec3): TVec3;
begin
  Result := Vec3(A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
end;

function Distance3(const A, B: TVec3): double;
begin
  Result := (A - B).Length;
end;

function PointsNear3(const A, B: TVec3; Tolerance: double): boolean;
begin
  Result := Distance3(A, B) <= Tolerance;
end;

function Mat3Identity: TMat3;
var
  Row, Col: integer;
begin
  for Row := 0 to 2 do
    for Col := 0 to 2 do
      Result.M[Row, Col] := Ord(Row = Col);
end;

function Mat3Then(const B, A: TMat3): TMat3;
var
  Row, Col, K: integer;
begin
  for Row := 0 to 2 do
    for Col := 0 to 2 do
    begin
      Result.M[Row, Col] := 0;
      for K := 0 to 2 do
        Result.M[Row, Col] := Result.M[Row, Col] + B.M[Row, K] * A.M[K, Col];
    end;
end;

function Mat3TurnX(AngleDeg: double): TMat3;
var
  C, S: double;
begin
  SinCos(DegToRad(AngleDeg), S, C);
  Result := Mat3Identity;
  Result.M[1, 1] := C;
  Result.M[1, 2] := -S;
  Result.M[2, 1] := S;
  Result.M[2, 2] := C;
end;

function Mat3TurnY(AngleDeg: double): TMat3;
var
  C, S: double;
begin
  SinCos(DegToRad(AngleDeg), S, C);
  Result := Mat3Identity;
  Result.M[0, 0] := C;
  Result.M[0, 2] := S;
  Result.M[2, 0] := -S;
  Result.M[2, 2] := C;
end;

function Mat3TurnZ(AngleDeg: double): TMat3;
var
  C, S: double;
begin
  SinCos(DegToRad(AngleDeg), S, C);
  Result := Mat3Identity;
  Result.M[0, 0] := C;
  Result.M[0, 1] := -S;
  Result.M[1, 0] := S;
  Result.M[1, 1] := C;
end;

// Rodrigues' formula: R = I cos + (1 - cos) a aᵀ + sin [a]x
function Mat3TurnAbout(const Axis: TVec3; AngleDeg: double): TMat3;
var
  A: TVec3;
  C, S, T: double;
begin
  A := Axis.Normalized;
  if A.Length < EPSILON then
    Exit(Mat3Identity);
  SinCos(DegToRad(AngleDeg), S, C);
  T := 1 - C;
  Result.M[0, 0] := C + T * A.X * A.X;
  Result.M[0, 1] := T * A.X * A.Y - S * A.Z;
  Result.M[0, 2] := T * A.X * A.Z + S * A.Y;
  Result.M[1, 0] := T * A.Y * A.X + S * A.Z;
  Result.M[1, 1] := C + T * A.Y * A.Y;
  Result.M[1, 2] := T * A.Y * A.Z - S * A.X;
  Result.M[2, 0] := T * A.Z * A.X - S * A.Y;
  Result.M[2, 1] := T * A.Z * A.Y + S * A.X;
  Result.M[2, 2] := C + T * A.Z * A.Z;
end;

function EulerToMat3(const Angles: TVec3): TMat3;
begin
  Result := Mat3Then(Mat3TurnZ(Angles.Z), Mat3Then(Mat3TurnY(Angles.Y), Mat3TurnX(Angles.X)));
end;

// R = Rz Ry Rx gives R[2,0] = -sin(y), R[2,1] = cos(y) sin(x),
// R[2,2] = cos(y) cos(x), R[1,0] = cos(y) sin(z), R[0,0] = cos(y) cos(z)
function Mat3ToEuler(const R: TMat3): TVec3;
var
  CosY: double;
begin
  CosY := Sqrt(Sqr(R.M[0, 0]) + Sqr(R.M[1, 0]));
  Result.Y := RadToDeg(ArcTan2(-R.M[2, 0], CosY));
  if CosY > GIMBAL_EPSILON then
  begin
    Result.X := RadToDeg(ArcTan2(R.M[2, 1], R.M[2, 2]));
    Result.Z := RadToDeg(ArcTan2(R.M[1, 0], R.M[0, 0]));
  end
  else
  begin
    // Only X - Z (Y at +90) or X + Z (Y at -90) is fixed: put it all in Z
    Result.X := 0;
    Result.Z := RadToDeg(ArcTan2(-R.M[0, 1], R.M[1, 1]));
  end;
end;

end.
