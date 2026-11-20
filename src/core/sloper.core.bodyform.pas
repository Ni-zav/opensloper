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

// The drape app's body: a tailor's dress form sized from a measurement set,
// as in the apps' icons. A torso from the neck to below the hips, lofted
// through elliptical rings at the measured heights whose circumferences match
// the measurements, on a pole and a round base; no head, arms or legs. A
// measurement the set lacks is taken from fixed proportions of the height, so
// there is always a whole form. In the drape frame (Sloper.Core.Geometry3):
// facing -Y, centred on the Z axis, the base on Z = 0, in mm. No LCL
// dependency.
unit Sloper.Core.BodyForm;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry3, Sloper.Core.Measurements;

type
  // The measurements the form is built from, in mm
  TBodyMeasures = record
    Height: double;
    NeckHeight, ShoulderHeight, ArmpitHeight, BustHeight, WaistHeight, HighHipHeight, HipHeight: double;
    NeckCircumference, HighBustCircumference, BustCircumference, WaistCircumference, HighHipCircumference, HipCircumference: double;
    ShoulderWidth: double;
    // The catalogue keys that were not in the set, so were estimated
    Estimated: TStringArray;
  end;

  // A horizontal ellipse of the torso: centred on the Z axis at Height, with
  // half-axes across (X) and front to back (Y)
  TBodyRing = record
    Height, HalfWidth, HalfDepth: double;
  end;

  TBodyRingArray = array of TBodyRing;

  // Indexes into the mesh's vertices, anticlockwise seen from outside
  TBodyTriangle = record
    First, Second, Third: integer;
  end;

  TBodyTriangleArray = array of TBodyTriangle;

  // Closed parts (torso, pole, base), each watertight with outward normals
  TBodyMesh = record
    Vertices: TVec3Array;
    Triangles: TBodyTriangleArray;
  end;

const
  // Points round each ring of the form
  BODY_RING_SEGMENTS = 48;

// A form of standard proportions, as for a set with no measurements
function DefaultBodyMeasures: TBodyMeasures;
// From the set's values for the size at SizeIndex (its selected size when -1);
// a nil set gives the default form
function BodyMeasuresFrom(Measurements: TMeasurementSet; SizeIndex: integer = -1): TBodyMeasures;
// The torso's rings, from the bottom up, ending at the top of the neck
function DressFormRings(const Measures: TBodyMeasures): TBodyRingArray;
// The ring's points, anticlockwise seen from above, the first on +X
function RingPoints(const Ring: TBodyRing; Segments: integer = BODY_RING_SEGMENTS): TVec3Array;
// The perimeter of an ellipse of these half-axes drawn with Segments points
function RingPerimeter(HalfWidth, HalfDepth: double; Segments: integer = BODY_RING_SEGMENTS): double;
function BuildDressForm(const Measures: TBodyMeasures): TBodyMesh;
// How far the form's front reaches (mm, towards -Y), for placing pieces
function DressFormFrontDepth(const Measures: TBodyMeasures): double;
// The volume a closed mesh encloses: positive when its normals point out
function MeshVolume(const Mesh: TBodyMesh): double;

implementation

uses
  Math;

const
  // A body with no height given: about an average adult's, in mm
  STANDARD_HEIGHT = 1680;
  // Shares of the height, for measurements a set does not give
  NECK_HEIGHT_SHARE = 0.845;
  SHOULDER_HEIGHT_SHARE = 0.82;
  ARMPIT_HEIGHT_SHARE = 0.74;
  BUST_HEIGHT_SHARE = 0.72;
  WAIST_HEIGHT_SHARE = 0.62;
  HIP_HEIGHT_SHARE = 0.52;
  NECK_SHARE = 0.215;
  BUST_SHARE = 0.54;
  WAIST_SHARE = 0.43;
  HIP_SHARE = 0.58;
  SHOULDER_WIDTH_SHARE = 0.235;
  // The chest above the bust, for a set without high_bust_circumference
  HIGH_BUST_OF_BUST = 0.95;
  // Depth over width of each ring, as a dress form's
  NECK_DEPTH_RATIO = 0.9;
  ARMPIT_DEPTH_RATIO = 0.62;
  BUST_DEPTH_RATIO = 0.7;
  WAIST_DEPTH_RATIO = 0.75;
  HIGH_HIP_DEPTH_RATIO = 0.72;
  HIP_DEPTH_RATIO = 0.7;
  // The shoulders: a share of the shoulder width (the form has no arms) and
  // a share of the armpit ring's depth
  SHOULDER_WIDTH_USED = 0.85;
  SHOULDER_DEPTH_OF_ARMPIT = 0.75;
  // The neck stands this far (mm) above the neck point; the torso ends this
  // far below the hip, a little narrower
  NECK_TOP = 70;
  HEM_BELOW_HIP = 80;
  HEM_OF_HIP = 0.95;
  // Rings closer than this (mm) are moved apart, so bad heights cannot fold
  // the torso over itself
  MIN_RING_GAP = 5;
  // The stand: a pole of this radius down to a round base
  POLE_RADIUS = 15;
  BASE_RADIUS = 250;
  BASE_THICKNESS = 20;
  POLE_SEGMENTS = 16;

  KEY_HEIGHT = 'height';
  KEY_NECK_HEIGHT = 'height_back_neck';
  KEY_SHOULDER_HEIGHT = 'height_shoulder';
  KEY_ARMPIT_HEIGHT = 'height_armpit';
  KEY_BUST_HEIGHT = 'height_bust_point';
  KEY_WAIST_HEIGHT = 'height_waist';
  KEY_HIP_HEIGHT = 'height_hip';
  KEY_NECK = 'neck_circumference';
  KEY_HIGH_BUST = 'high_bust_circumference';
  KEY_BUST = 'bust_circumference';
  KEY_WAIST = 'waist_circumference';
  KEY_HIGH_HIP = 'high_hip_circumference';
  KEY_HIP = 'hip_circumference';
  KEY_SHOULDER_WIDTH = 'shoulder_width';

function DefaultBodyMeasures: TBodyMeasures;
begin
  Result := BodyMeasuresFrom(nil);
end;

function BodyMeasuresFrom(Measurements: TMeasurementSet; SizeIndex: integer): TBodyMeasures;
var
  Measures: TBodyMeasures;

  function Value(const Key: string; Fallback: double): double;
  var
    Measurement: TMeasurement;
    Index: integer;
  begin
    Result := Fallback;
    Measurement := nil;
    if Assigned(Measurements) then
      Measurement := Measurements.Find(Key);
    Index := SizeIndex;
    if Assigned(Measurement) and (Index < 0) then
      Index := Measurements.SizeIndex;
    if Assigned(Measurement) and Measurement.HasValueFor(Index) and (Measurement.ValueFor(Index) > 0) then
      Result := Measurement.ValueFor(Index)
    else
      Insert(Key, Measures.Estimated, Length(Measures.Estimated));
  end;

begin
  Measures := Default(TBodyMeasures);
  Measures.Height := Value(KEY_HEIGHT, STANDARD_HEIGHT);
  Measures.NeckHeight := Value(KEY_NECK_HEIGHT, Measures.Height * NECK_HEIGHT_SHARE);
  Measures.ShoulderHeight := Value(KEY_SHOULDER_HEIGHT, Measures.Height * SHOULDER_HEIGHT_SHARE);
  Measures.ArmpitHeight := Value(KEY_ARMPIT_HEIGHT, Measures.Height * ARMPIT_HEIGHT_SHARE);
  Measures.BustHeight := Value(KEY_BUST_HEIGHT, Measures.Height * BUST_HEIGHT_SHARE);
  Measures.WaistHeight := Value(KEY_WAIST_HEIGHT, Measures.Height * WAIST_HEIGHT_SHARE);
  Measures.HipHeight := Value(KEY_HIP_HEIGHT, Measures.Height * HIP_HEIGHT_SHARE);
  // The catalogue has no height for the high hip: halfway down
  Measures.HighHipHeight := (Measures.WaistHeight + Measures.HipHeight) / 2;
  Measures.NeckCircumference := Value(KEY_NECK, Measures.Height * NECK_SHARE);
  Measures.BustCircumference := Value(KEY_BUST, Measures.Height * BUST_SHARE);
  Measures.HighBustCircumference := Value(KEY_HIGH_BUST, Measures.BustCircumference * HIGH_BUST_OF_BUST);
  Measures.WaistCircumference := Value(KEY_WAIST, Measures.Height * WAIST_SHARE);
  Measures.HipCircumference := Value(KEY_HIP, Measures.Height * HIP_SHARE);
  Measures.HighHipCircumference := Value(KEY_HIGH_HIP, (Measures.WaistCircumference + Measures.HipCircumference) / 2);
  Measures.ShoulderWidth := Value(KEY_SHOULDER_WIDTH, Measures.Height * SHOULDER_WIDTH_SHARE);
  Result := Measures;
end;

function RingPerimeter(HalfWidth, HalfDepth: double; Segments: integer): double;
var
  Index: integer;
  Angle: double;
  Previous, Current: TVec3;
begin
  Result := 0;
  Previous := Vec3(HalfWidth, 0, 0);
  for Index := 1 to Segments do
  begin
    Angle := 2 * Pi * Index / Segments;
    Current := Vec3(HalfWidth * Cos(Angle), HalfDepth * Sin(Angle), 0);
    Result := Result + Distance3(Previous, Current);
    Previous := Current;
  end;
end;

// The ring whose drawn perimeter is the circumference, at this depth ratio
function RingOf(AHeight, Circumference, DepthRatio: double): TBodyRing;
begin
  Result.Height := AHeight;
  Result.HalfWidth := Circumference / RingPerimeter(1, DepthRatio);
  Result.HalfDepth := Result.HalfWidth * DepthRatio;
end;

function DressFormRings(const Measures: TBodyMeasures): TBodyRingArray;
var
  Hip, Armpit, Shoulder: TBodyRing;
  Index: integer;
begin
  Hip := RingOf(Measures.HipHeight, Measures.HipCircumference, HIP_DEPTH_RATIO);
  Armpit := RingOf(Measures.ArmpitHeight, Measures.HighBustCircumference, ARMPIT_DEPTH_RATIO);
  Shoulder.Height := Measures.ShoulderHeight;
  Shoulder.HalfWidth := Measures.ShoulderWidth * SHOULDER_WIDTH_USED / 2;
  Shoulder.HalfDepth := Armpit.HalfDepth * SHOULDER_DEPTH_OF_ARMPIT;
  Result := nil;
  SetLength(Result, 10);
  Result[0] := RingOf(Measures.HipHeight - HEM_BELOW_HIP, Measures.HipCircumference * HEM_OF_HIP, HIP_DEPTH_RATIO);
  Result[1] := Hip;
  Result[2] := RingOf(Measures.HighHipHeight, Measures.HighHipCircumference, HIGH_HIP_DEPTH_RATIO);
  Result[3] := RingOf(Measures.WaistHeight, Measures.WaistCircumference, WAIST_DEPTH_RATIO);
  Result[4] := RingOf(Measures.BustHeight, Measures.BustCircumference, BUST_DEPTH_RATIO);
  Result[5] := Armpit;
  Result[6] := Shoulder;
  Result[7] := RingOf(Measures.NeckHeight, Measures.NeckCircumference, NECK_DEPTH_RATIO);
  Result[8] := Result[7];
  Result[8].Height := Measures.NeckHeight + NECK_TOP / 2;
  Result[9] := Result[7];
  Result[9].Height := Measures.NeckHeight + NECK_TOP;
  for Index := 1 to High(Result) do
    Result[Index].Height := Max(Result[Index].Height, Result[Index - 1].Height + MIN_RING_GAP);
end;

function RingPoints(const Ring: TBodyRing; Segments: integer): TVec3Array;
var
  Index: integer;
  Angle: double;
begin
  Result := nil;
  SetLength(Result, Segments);
  for Index := 0 to Segments - 1 do
  begin
    Angle := 2 * Pi * Index / Segments;
    Result[Index] := Vec3(Ring.HalfWidth * Cos(Angle), Ring.HalfDepth * Sin(Angle), Ring.Height);
  end;
end;

procedure AddTriangle(var Mesh: TBodyMesh; First, Second, Third: integer);
var
  Triangle: TBodyTriangle;
begin
  Triangle.First := First;
  Triangle.Second := Second;
  Triangle.Third := Third;
  Insert(Triangle, Mesh.Triangles, Length(Mesh.Triangles));
end;

function AddVertex(var Mesh: TBodyMesh; const Point: TVec3): integer;
begin
  Result := Length(Mesh.Vertices);
  Insert(Point, Mesh.Vertices, Result);
end;

// A closed tube through the rings, from the bottom up, capped at both ends.
// Rings run anticlockwise seen from above, so going up the side between two
// rings, (lower k, upper k, lower k+1) faces out.
procedure AddTube(var Mesh: TBodyMesh; const Rings: TBodyRingArray; Segments: integer);
var
  First, RingIndex, Step, Next, Lower, Upper, Bottom, Top: integer;
  Point: TVec3;
begin
  First := Length(Mesh.Vertices);
  for RingIndex := 0 to High(Rings) do
    for Point in RingPoints(Rings[RingIndex], Segments) do
      AddVertex(Mesh, Point);
  for RingIndex := 0 to High(Rings) - 1 do
  begin
    Lower := First + RingIndex * Segments;
    Upper := Lower + Segments;
    for Step := 0 to Segments - 1 do
    begin
      Next := (Step + 1) mod Segments;
      AddTriangle(Mesh, Lower + Step, Lower + Next, Upper + Step);
      AddTriangle(Mesh, Lower + Next, Upper + Next, Upper + Step);
    end;
  end;
  // The caps: the bottom faces down, the top up
  Bottom := AddVertex(Mesh, Vec3(0, 0, Rings[0].Height));
  Top := AddVertex(Mesh, Vec3(0, 0, Rings[High(Rings)].Height));
  Upper := First + High(Rings) * Segments;
  for Step := 0 to Segments - 1 do
  begin
    Next := (Step + 1) mod Segments;
    AddTriangle(Mesh, Bottom, First + Next, First + Step);
    AddTriangle(Mesh, Top, Upper + Step, Upper + Next);
  end;
end;

function Cylinder(Bottom, Top, Radius: double): TBodyRingArray;
begin
  Result := nil;
  SetLength(Result, 2);
  Result[0].Height := Bottom;
  Result[0].HalfWidth := Radius;
  Result[0].HalfDepth := Radius;
  Result[1] := Result[0];
  Result[1].Height := Top;
end;

function BuildDressForm(const Measures: TBodyMeasures): TBodyMesh;
var
  Rings: TBodyRingArray;
begin
  Result := Default(TBodyMesh);
  Rings := DressFormRings(Measures);
  AddTube(Result, Rings, BODY_RING_SEGMENTS);
  AddTube(Result, Cylinder(BASE_THICKNESS, Rings[0].Height, POLE_RADIUS), POLE_SEGMENTS);
  AddTube(Result, Cylinder(0, BASE_THICKNESS, BASE_RADIUS), BODY_RING_SEGMENTS);
end;

function DressFormFrontDepth(const Measures: TBodyMeasures): double;
var
  Ring: TBodyRing;
begin
  Result := 0;
  for Ring in DressFormRings(Measures) do
    Result := Max(Result, Ring.HalfDepth);
end;

function MeshVolume(const Mesh: TBodyMesh): double;
var
  Triangle: TBodyTriangle;
begin
  Result := 0;
  for Triangle in Mesh.Triangles do
    Result := Result + Dot3(Mesh.Vertices[Triangle.First], Cross3(Mesh.Vertices[Triangle.Second], Mesh.Vertices[Triangle.Third])) / 6;
end;

end.
