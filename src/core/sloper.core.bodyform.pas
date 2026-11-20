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

// The drape app's body: a whole figure sized from a measurement set, so
// sleeves and trousers have arms and legs to go round. A torso from the neck
// to the crotch, lofted through elliptical rings at the measured heights whose
// circumferences match the measurements; legs and arms lofted the same way
// through their own circumferences, the arms hanging a little out from the
// sides; hands, feet pointing forwards, and a head with a nose, so the front
// is plain from any side. Each part is a closed mesh; they overlap where they
// join. A measurement the set lacks is taken from fixed proportions of the
// height, so there is always a whole figure. In the drape frame
// (Sloper.Core.Geometry3): facing -Y, centred on the Z axis, standing on
// Z = 0, in mm. No LCL dependency.
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
    CrotchHeight, KneeHeight, AnkleHeight: double;
    ThighCircumference, KneeCircumference, CalfCircumference, AnkleCircumference: double;
    UpperArmCircumference, ElbowCircumference, WristCircumference: double;
    // From the shoulder tip, along the arm
    ArmLength, ShoulderToElbow: double;
    HeadCircumference, HeadLength: double;
    HandLength, HandWidth, FootLength, FootWidth: double;
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

  // A cross-section of a limb: an ellipse round Centre, with half-axes along
  // the limb's two crosswise directions
  TBodySection = record
    Centre: TVec3;
    HalfU, HalfV: double;
  end;

  TBodySectionArray = array of TBodySection;

  // Closed parts (torso, legs, feet, arms with hands, head, nose), each
  // watertight with outward normals
  TBodyMesh = record
    Vertices: TVec3Array;
    Triangles: TBodyTriangleArray;
  end;

const
  // Points round each ring of the torso
  BODY_RING_SEGMENTS = 48;
  // Points round each section of a limb, the head and the nose
  LIMB_SEGMENTS = 24;
  // How far the arms hang out from straight down, degrees, so sleeves can go
  // round them clear of the body
  ARM_ANGLE = 20;

// A form of standard proportions, as for a set with no measurements
function DefaultBodyMeasures: TBodyMeasures;
// From the set's values for the size at SizeIndex (its selected size when -1);
// a nil set gives the default form
function BodyMeasuresFrom(Measurements: TMeasurementSet; SizeIndex: integer = -1): TBodyMeasures;
// The torso's rings, from the crotch up, ending at the top of the neck
function TorsoRings(const Measures: TBodyMeasures): TBodyRingArray;
// The ring's points, anticlockwise seen from above, the first on +X
function RingPoints(const Ring: TBodyRing; Segments: integer = BODY_RING_SEGMENTS): TVec3Array;
// The perimeter of an ellipse of these half-axes drawn with Segments points
function RingPerimeter(HalfWidth, HalfDepth: double; Segments: integer = BODY_RING_SEGMENTS): double;
function BuildBodyForm(const Measures: TBodyMeasures): TBodyMesh;
// The way an arm hangs from the shoulder: Side is 1 for the body's left (+X),
// -1 for its right
function ArmDirection(Side: integer): TVec3;
// How far the torso's front reaches (mm, towards -Y), for placing pieces
function BodyFrontDepth(const Measures: TBodyMeasures): double;
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
  CROTCH_HEIGHT_SHARE = 0.45;
  KNEE_HEIGHT_SHARE = 0.285;
  ANKLE_HEIGHT_SHARE = 0.045;
  THIGH_SHARE = 0.33;
  KNEE_SHARE = 0.215;
  CALF_SHARE = 0.21;
  ANKLE_SHARE = 0.135;
  UPPER_ARM_SHARE = 0.165;
  ELBOW_SHARE = 0.15;
  WRIST_SHARE = 0.095;
  ARM_LENGTH_SHARE = 0.34;
  SHOULDER_TO_ELBOW_SHARE = 0.2;
  HEAD_SHARE = 0.335;
  HEAD_LENGTH_SHARE = 0.13;
  HAND_LENGTH_SHARE = 0.108;
  HAND_WIDTH_SHARE = 0.05;
  FOOT_LENGTH_SHARE = 0.152;
  FOOT_WIDTH_SHARE = 0.058;
  // The chest above the bust, for a set without high_bust_circumference
  HIGH_BUST_OF_BUST = 0.95;
  // Depth over width of each ring, as a dress form's
  NECK_DEPTH_RATIO = 0.9;
  ARMPIT_DEPTH_RATIO = 0.62;
  BUST_DEPTH_RATIO = 0.7;
  WAIST_DEPTH_RATIO = 0.75;
  HIGH_HIP_DEPTH_RATIO = 0.72;
  HIP_DEPTH_RATIO = 0.7;
  // The shoulders: a share of the shoulder width, the rest being the arms',
  // and a share of the armpit ring's depth
  SHOULDER_WIDTH_USED = 0.85;
  SHOULDER_DEPTH_OF_ARMPIT = 0.75;
  // The neck stands this far (mm) above the neck point, into the head; the
  // torso ends at the crotch, a little narrower than the hip
  NECK_TOP = 70;
  CROTCH_OF_HIP = 0.95;
  // Rings closer than this (mm) are moved apart, so bad heights cannot fold
  // the torso or a leg over itself
  MIN_RING_GAP = 5;
  // Depth over width of a leg's and an arm's sections, and of the head's
  LEG_DEPTH_RATIO = 0.95;
  ARM_DEPTH_RATIO = 0.9;
  HEAD_DEPTH_RATIO = 1.2;
  // The calf is thickest this share of the way from the ankle to the knee
  CALF_POSITION = 0.6;
  // A leg starts this share of the ankle's height above the floor, inside the
  // foot, and goes this far (mm) up into the torso, a little thinner
  LEG_BOTTOM_OF_ANKLE = 0.5;
  LEG_INTO_TORSO = 80;
  LEG_TOP_OF_THIGH = 0.9;
  // The top of the arm sits in from the shoulder tip and down from the
  // shoulder by these shares of the upper arm's half width; it is rounded off
  // above by a narrower section, this share of the half width further up
  ARM_IN_OF_UPPER = 0.7;
  ARM_DOWN_OF_UPPER = 0.8;
  ARM_CAP_OF_UPPER = 0.6;
  ARM_CAP_SIZE = 0.7;
  // The arm at the armhole is this share wider than the upper arm, which is
  // this share of the way to the elbow; the forearm, this share of the way
  // from the elbow to the wrist, is a share of the elbow
  ARMHOLE_OF_UPPER = 1.05;
  UPPER_ARM_POSITION = 0.3;
  FOREARM_POSITION = 0.35;
  FOREARM_OF_ELBOW = 0.97;
  // A head this many rings from chin to crown
  HEAD_RINGS = 12;
  // The nose: how far below the head's middle, its length, width and height
  // as shares of the head's length, and how far it starts inside the face as
  // a share of the head's half depth
  NOSE_DROP = 0.15;
  NOSE_LENGTH = 0.1;
  NOSE_WIDTH = 0.14;
  NOSE_HEIGHT = 0.2;
  NOSE_TIP = 0.45;
  NOSE_INSIDE = 0.85;

  KEY_HEIGHT = 'height';
  KEY_NECK_HEIGHT = 'height_back_neck';
  KEY_SHOULDER_HEIGHT = 'height_shoulder';
  KEY_ARMPIT_HEIGHT = 'height_armpit';
  KEY_BUST_HEIGHT = 'height_bust_point';
  KEY_WAIST_HEIGHT = 'height_waist';
  KEY_BACK_LENGTH = 'neck_back_to_waist';
  KEY_HIP_HEIGHT = 'height_hip';
  KEY_NECK = 'neck_circumference';
  KEY_HIGH_BUST = 'high_bust_circumference';
  KEY_BUST = 'bust_circumference';
  KEY_WAIST = 'waist_circumference';
  KEY_HIGH_HIP = 'high_hip_circumference';
  KEY_HIP = 'hip_circumference';
  KEY_SHOULDER_WIDTH = 'shoulder_width';
  KEY_CROTCH_HEIGHT = 'inside_leg';
  KEY_KNEE_HEIGHT = 'height_knee';
  KEY_ANKLE_HEIGHT = 'height_ankle';
  KEY_THIGH = 'thigh_circumference';
  KEY_KNEE = 'knee_circumference';
  KEY_CALF = 'calf_circumference';
  KEY_ANKLE = 'ankle_circumference';
  KEY_UPPER_ARM = 'upper_arm_circumference';
  KEY_ELBOW = 'elbow_circumference';
  KEY_WRIST = 'wrist_circumference';
  KEY_ARM_LENGTH = 'arm_length';
  KEY_SHOULDER_TO_ELBOW = 'shoulder_to_elbow';
  KEY_HEAD = 'head_circumference';
  KEY_HEAD_LENGTH = 'head_length';
  KEY_HAND_LENGTH = 'hand_length';
  KEY_HAND_WIDTH = 'hand_width';
  KEY_FOOT_LENGTH = 'foot_length';
  KEY_FOOT_WIDTH = 'foot_width';

  // The foot from heel to toe: where each section is along it, as a share of
  // the foot's length forward of the ankle (the heel behind, negative), its
  // half width as a share of the foot's width and its height as a share of
  // the ankle's
  FOOT_SECTIONS: array[0..4] of array[0..2] of double = ((-0.22, 0.3, 0.9), (0, 0.42, 1.3), (0.45, 0.5, 0.8),
    (0.7, 0.45, 0.5), (0.78, 0.25, 0.3));
  // The hand from the wrist: where each section is, as a share of the hand's
  // length, and its half thickness and half width as shares of its width
  HAND_SECTIONS: array[0..2] of array[0..2] of double = ((0.4, 0.18, 0.5), (0.75, 0.15, 0.45), (1, 0.06, 0.2));

function DefaultBodyMeasures: TBodyMeasures;
begin
  Result := BodyMeasuresFrom(nil);
end;

function BodyMeasuresFrom(Measurements: TMeasurementSet; SizeIndex: integer): TBodyMeasures;
var
  Measures: TBodyMeasures;
  BackLength: double;
  HasBackLength, HasWaistHeight: boolean;

// The set's value for Key, when it has one above 0
  function Given(const Key: string; out Found: double): boolean;
  var
    Measurement: TMeasurement;
    Index: integer;
  begin
    Found := 0;
    Measurement := nil;
    if Assigned(Measurements) then
      Measurement := Measurements.Find(Key);
    Index := SizeIndex;
    if Assigned(Measurement) and (Index < 0) then
      Index := Measurements.SizeIndex;
    Result := Assigned(Measurement) and Measurement.HasValueFor(Index) and (Measurement.ValueFor(Index) > 0);
    if Result then
      Found := Measurement.ValueFor(Index);
  end;

  function Value(const Key: string; Fallback: double): double;
  begin
    if not Given(Key, Result) then
    begin
      Result := Fallback;
      Insert(Key, Measures.Estimated, Length(Measures.Estimated));
    end;
  end;

begin
  Measures := Default(TBodyMeasures);
  Measures.Height := Value(KEY_HEIGHT, STANDARD_HEIGHT);
  // The back length, nape to waist, sets one of the two heights from the
  // other when only one is measured, or the waist from the neck's share
  // when neither is: a bodice block's set often has it and no heights. It
  // is measured down the back's curve, so the drop is a little less, which
  // is left out.
  HasBackLength := Given(KEY_BACK_LENGTH, BackLength) and (BackLength < Measures.Height);
  HasWaistHeight := Given(KEY_WAIST_HEIGHT, Measures.WaistHeight);
  if HasBackLength and HasWaistHeight then
    Measures.NeckHeight := Value(KEY_NECK_HEIGHT, Measures.WaistHeight + BackLength)
  else
    Measures.NeckHeight := Value(KEY_NECK_HEIGHT, Measures.Height * NECK_HEIGHT_SHARE);
  Measures.ShoulderHeight := Value(KEY_SHOULDER_HEIGHT, Measures.Height * SHOULDER_HEIGHT_SHARE);
  Measures.ArmpitHeight := Value(KEY_ARMPIT_HEIGHT, Measures.Height * ARMPIT_HEIGHT_SHARE);
  Measures.BustHeight := Value(KEY_BUST_HEIGHT, Measures.Height * BUST_HEIGHT_SHARE);
  if HasBackLength and (BackLength < Measures.NeckHeight) then
    Measures.WaistHeight := Value(KEY_WAIST_HEIGHT, Measures.NeckHeight - BackLength)
  else
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
  Measures.CrotchHeight := Value(KEY_CROTCH_HEIGHT, Measures.Height * CROTCH_HEIGHT_SHARE);
  Measures.KneeHeight := Value(KEY_KNEE_HEIGHT, Measures.Height * KNEE_HEIGHT_SHARE);
  Measures.AnkleHeight := Value(KEY_ANKLE_HEIGHT, Measures.Height * ANKLE_HEIGHT_SHARE);
  Measures.ThighCircumference := Value(KEY_THIGH, Measures.Height * THIGH_SHARE);
  Measures.KneeCircumference := Value(KEY_KNEE, Measures.Height * KNEE_SHARE);
  Measures.CalfCircumference := Value(KEY_CALF, Measures.Height * CALF_SHARE);
  Measures.AnkleCircumference := Value(KEY_ANKLE, Measures.Height * ANKLE_SHARE);
  Measures.UpperArmCircumference := Value(KEY_UPPER_ARM, Measures.Height * UPPER_ARM_SHARE);
  Measures.ElbowCircumference := Value(KEY_ELBOW, Measures.Height * ELBOW_SHARE);
  Measures.WristCircumference := Value(KEY_WRIST, Measures.Height * WRIST_SHARE);
  Measures.ArmLength := Value(KEY_ARM_LENGTH, Measures.Height * ARM_LENGTH_SHARE);
  Measures.ShoulderToElbow := Value(KEY_SHOULDER_TO_ELBOW, Measures.Height * SHOULDER_TO_ELBOW_SHARE);
  Measures.HeadCircumference := Value(KEY_HEAD, Measures.Height * HEAD_SHARE);
  Measures.HeadLength := Value(KEY_HEAD_LENGTH, Measures.Height * HEAD_LENGTH_SHARE);
  Measures.HandLength := Value(KEY_HAND_LENGTH, Measures.Height * HAND_LENGTH_SHARE);
  Measures.HandWidth := Value(KEY_HAND_WIDTH, Measures.Height * HAND_WIDTH_SHARE);
  Measures.FootLength := Value(KEY_FOOT_LENGTH, Measures.Height * FOOT_LENGTH_SHARE);
  Measures.FootWidth := Value(KEY_FOOT_WIDTH, Measures.Height * FOOT_WIDTH_SHARE);
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

// Each ring at least MIN_RING_GAP above the one below
procedure KeepRingsApart(var Rings: TBodyRingArray);
var
  Index: integer;
begin
  for Index := 1 to High(Rings) do
    Rings[Index].Height := Max(Rings[Index].Height, Rings[Index - 1].Height + MIN_RING_GAP);
end;

function TorsoRings(const Measures: TBodyMeasures): TBodyRingArray;
var
  Hip, Armpit, Shoulder: TBodyRing;
begin
  Hip := RingOf(Measures.HipHeight, Measures.HipCircumference, HIP_DEPTH_RATIO);
  Armpit := RingOf(Measures.ArmpitHeight, Measures.HighBustCircumference, ARMPIT_DEPTH_RATIO);
  Shoulder.Height := Measures.ShoulderHeight;
  Shoulder.HalfWidth := Measures.ShoulderWidth * SHOULDER_WIDTH_USED / 2;
  Shoulder.HalfDepth := Armpit.HalfDepth * SHOULDER_DEPTH_OF_ARMPIT;
  Result := nil;
  SetLength(Result, 10);
  Result[0] := RingOf(Min(Measures.CrotchHeight, Measures.HipHeight - MIN_RING_GAP), Measures.HipCircumference * CROTCH_OF_HIP,
    HIP_DEPTH_RATIO);
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
  KeepRingsApart(Result);
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

function Section(const Centre: TVec3; HalfU, HalfV: double): TBodySection;
begin
  Result.Centre := Centre;
  Result.HalfU := HalfU;
  Result.HalfV := HalfV;
end;

// A closed tube through the sections, capped at both ends. AcrossFirst and
// AcrossSecond are the sections' crosswise directions, along which HalfU and
// HalfV go, with AcrossFirst x AcrossSecond the way the tube runs from its
// first section to its last; each section's points then run anticlockwise
// seen from that way, so (first k, next section k, first k+1) faces out.
procedure AddSweep(var Mesh: TBodyMesh; const Sections: array of TBodySection; const AcrossFirst, AcrossSecond: TVec3; Segments: integer);
var
  First, Triangle, SectionIndex, Step, Next, Lower, Upper, Bottom, Top: integer;
  Angle: double;

  procedure Add(CornerA, CornerB, CornerC: integer);
  begin
    Mesh.Triangles[Triangle].First := CornerA;
    Mesh.Triangles[Triangle].Second := CornerB;
    Mesh.Triangles[Triangle].Third := CornerC;
    Inc(Triangle);
  end;

begin
  if Length(Sections) < 2 then
    Exit;
  First := Length(Mesh.Vertices);
  SetLength(Mesh.Vertices, First + Length(Sections) * Segments + 2);
  for SectionIndex := 0 to High(Sections) do
    for Step := 0 to Segments - 1 do
    begin
      Angle := 2 * Pi * Step / Segments;
      Mesh.Vertices[First + SectionIndex * Segments + Step] := Sections[SectionIndex].Centre +
        AcrossFirst * (Sections[SectionIndex].HalfU * Cos(Angle)) + AcrossSecond * (Sections[SectionIndex].HalfV * Sin(Angle));
    end;
  Bottom := First + Length(Sections) * Segments;
  Top := Bottom + 1;
  Mesh.Vertices[Bottom] := Sections[0].Centre;
  Mesh.Vertices[Top] := Sections[High(Sections)].Centre;
  Triangle := Length(Mesh.Triangles);
  SetLength(Mesh.Triangles, Triangle + 2 * Length(Sections) * Segments);
  for SectionIndex := 0 to High(Sections) - 1 do
  begin
    Lower := First + SectionIndex * Segments;
    Upper := Lower + Segments;
    for Step := 0 to Segments - 1 do
    begin
      Next := (Step + 1) mod Segments;
      Add(Lower + Step, Lower + Next, Upper + Step);
      Add(Lower + Next, Upper + Next, Upper + Step);
    end;
  end;
  // The caps: the first faces back along the tube, the last on along it
  Upper := First + High(Sections) * Segments;
  for Step := 0 to Segments - 1 do
  begin
    Next := (Step + 1) mod Segments;
    Add(Bottom, First + Next, First + Step);
    Add(Top, Upper + Step, Upper + Next);
  end;
end;

// Upright rings round the Z axis, from the bottom up
procedure AddRings(var Mesh: TBodyMesh; const Rings: TBodyRingArray; const Offset: TVec3; Segments: integer);
var
  Sections: TBodySectionArray;
  Index: integer;
begin
  Sections := nil;
  SetLength(Sections, Length(Rings));
  for Index := 0 to High(Rings) do
    Sections[Index] := Section(Offset + Vec3(0, 0, Rings[Index].Height), Rings[Index].HalfWidth, Rings[Index].HalfDepth);
  AddSweep(Mesh, Sections, Vec3(1, 0, 0), Vec3(0, 1, 0), Segments);
end;

function LegRings(const Measures: TBodyMeasures): TBodyRingArray;
begin
  Result := nil;
  SetLength(Result, 6);
  Result[0] := RingOf(Measures.AnkleHeight * LEG_BOTTOM_OF_ANKLE, Measures.AnkleCircumference, LEG_DEPTH_RATIO);
  Result[1] := RingOf(Measures.AnkleHeight, Measures.AnkleCircumference, LEG_DEPTH_RATIO);
  Result[2] := RingOf(Measures.AnkleHeight + (Measures.KneeHeight - Measures.AnkleHeight) * CALF_POSITION, Measures.CalfCircumference,
    LEG_DEPTH_RATIO);
  Result[3] := RingOf(Measures.KneeHeight, Measures.KneeCircumference, LEG_DEPTH_RATIO);
  Result[4] := RingOf(Measures.CrotchHeight, Measures.ThighCircumference, LEG_DEPTH_RATIO);
  Result[5] := RingOf(Measures.CrotchHeight + LEG_INTO_TORSO, Measures.ThighCircumference * LEG_TOP_OF_THIGH, LEG_DEPTH_RATIO);
  KeepRingsApart(Result);
end;

// How far each leg's centre line is from the body's: the thighs just touch
function LegOffset(const Measures: TBodyMeasures): double;
begin
  Result := RingOf(0, Measures.ThighCircumference, LEG_DEPTH_RATIO).HalfWidth;
end;

// A foot under the leg at X, pointing forwards (-Y): sections from the heel
// to the toe, each standing on the floor
procedure AddFoot(var Mesh: TBodyMesh; const Measures: TBodyMeasures; X: double);
var
  Sections: TBodySectionArray;
  Index: integer;
  HalfHeight: double;
begin
  Sections := nil;
  SetLength(Sections, Length(FOOT_SECTIONS));
  for Index := 0 to High(FOOT_SECTIONS) do
  begin
    HalfHeight := Measures.AnkleHeight * FOOT_SECTIONS[Index][2] / 2;
    Sections[Index] := Section(Vec3(X, -Measures.FootLength * FOOT_SECTIONS[Index][0], HalfHeight),
      Measures.FootWidth * FOOT_SECTIONS[Index][1], HalfHeight);
  end;
  // Running towards -Y: X x Z = -Y
  AddSweep(Mesh, Sections, Vec3(1, 0, 0), Vec3(0, 0, 1), LIMB_SEGMENTS);
end;

function ArmDirection(Side: integer): TVec3;
begin
  Result := Vec3(Side * Sin(DegToRad(ARM_ANGLE)), 0, -Cos(DegToRad(ARM_ANGLE)));
end;

// An arm and its hand, hanging from the shoulder on Side, palm in
procedure AddArm(var Mesh: TBodyMesh; const Measures: TBodyMeasures; Side: integer);
var
  Sections: TBodySectionArray;
  Upper: TBodyRing;
  Down, Across, Front, Top: TVec3;
  ToWrist, ToElbow: double;
  Index: integer;

  procedure Add(Along: double; const Ring: TBodyRing);
  begin
    Insert(Section(Top + Down * Along, Ring.HalfWidth, Ring.HalfDepth), Sections, Length(Sections));
  end;

begin
  Down := ArmDirection(Side);
  Front := Vec3(0, 1, 0);
  // Across x Front runs down the arm
  Across := Cross3(Front, Down);
  Upper := RingOf(0, Measures.UpperArmCircumference, ARM_DEPTH_RATIO);
  Top := Vec3(Side * (Measures.ShoulderWidth / 2 - Upper.HalfWidth * ARM_IN_OF_UPPER), 0,
    Measures.ShoulderHeight - Upper.HalfWidth * ARM_DOWN_OF_UPPER);
  ToWrist := Max(Measures.ArmLength, MIN_RING_GAP * 4);
  ToElbow := EnsureRange(Measures.ShoulderToElbow, MIN_RING_GAP, ToWrist - MIN_RING_GAP);
  Sections := nil;
  Upper.HalfWidth := Upper.HalfWidth * ARM_CAP_SIZE;
  Upper.HalfDepth := Upper.HalfDepth * ARM_CAP_SIZE;
  Add(-RingOf(0, Measures.UpperArmCircumference, ARM_DEPTH_RATIO).HalfWidth * ARM_CAP_OF_UPPER, Upper);
  Add(0, RingOf(0, Measures.UpperArmCircumference * ARMHOLE_OF_UPPER, ARM_DEPTH_RATIO));
  Add(ToElbow * UPPER_ARM_POSITION, RingOf(0, Measures.UpperArmCircumference, ARM_DEPTH_RATIO));
  Add(ToElbow, RingOf(0, Measures.ElbowCircumference, ARM_DEPTH_RATIO));
  Add(ToElbow + (ToWrist - ToElbow) * FOREARM_POSITION, RingOf(0, Measures.ElbowCircumference * FOREARM_OF_ELBOW, ARM_DEPTH_RATIO));
  Add(ToWrist, RingOf(0, Measures.WristCircumference, ARM_DEPTH_RATIO));
  for Index := 0 to High(HAND_SECTIONS) do
    Insert(Section(Top + Down * (ToWrist + Measures.HandLength * HAND_SECTIONS[Index][0]), Measures.HandWidth * HAND_SECTIONS[Index][1],
      Measures.HandWidth * HAND_SECTIONS[Index][2]), Sections, Length(Sections));
  AddSweep(Mesh, Sections, Across, Front, LIMB_SEGMENTS);
end;

// The head: an ellipsoid from the chin to the crown, and a nose on its front
procedure AddHead(var Mesh: TBodyMesh; const Measures: TBodyMeasures);
var
  Sections: TBodySectionArray;
  Ring: TBodyRing;
  Middle, HalfHeight, Angle, NoseZ: double;
  Index: integer;
begin
  Ring := RingOf(0, Measures.HeadCircumference, HEAD_DEPTH_RATIO);
  HalfHeight := Measures.HeadLength / 2;
  Middle := Measures.Height - HalfHeight;
  Sections := nil;
  SetLength(Sections, HEAD_RINGS - 1);
  for Index := 1 to HEAD_RINGS - 1 do
  begin
    Angle := Pi * Index / HEAD_RINGS;
    Sections[Index - 1] := Section(Vec3(0, 0, Middle - HalfHeight * Cos(Angle)), Ring.HalfWidth * Sin(Angle), Ring.HalfDepth * Sin(Angle));
  end;
  AddSweep(Mesh, Sections, Vec3(1, 0, 0), Vec3(0, 1, 0), LIMB_SEGMENTS);
  NoseZ := Middle - HalfHeight * NOSE_DROP;
  Sections := nil;
  SetLength(Sections, 2);
  Sections[0] := Section(Vec3(0, -Ring.HalfDepth * NOSE_INSIDE, NoseZ), Measures.HeadLength * NOSE_WIDTH / 2,
    Measures.HeadLength * NOSE_HEIGHT / 2);
  Sections[1] := Section(Vec3(0, -Ring.HalfDepth - Measures.HeadLength * NOSE_LENGTH, NoseZ - Measures.HeadLength * NOSE_HEIGHT * NOSE_TIP / 2),
    Sections[0].HalfU * NOSE_TIP, Sections[0].HalfV * NOSE_TIP);
  AddSweep(Mesh, Sections, Vec3(1, 0, 0), Vec3(0, 0, 1), LIMB_SEGMENTS);
end;

function BuildBodyForm(const Measures: TBodyMeasures): TBodyMesh;
var
  Side: integer;
  Offset: double;
  Legs: TBodyRingArray;
const
  SIDES: array[0..1] of integer = (-1, 1);
begin
  Result := Default(TBodyMesh);
  AddRings(Result, TorsoRings(Measures), Vec3(0, 0, 0), BODY_RING_SEGMENTS);
  Legs := LegRings(Measures);
  Offset := LegOffset(Measures);
  for Side in SIDES do
  begin
    AddRings(Result, Legs, Vec3(Side * Offset, 0, 0), LIMB_SEGMENTS);
    AddFoot(Result, Measures, Side * Offset);
    AddArm(Result, Measures, Side);
  end;
  AddHead(Result, Measures);
end;

function BodyFrontDepth(const Measures: TBodyMeasures): double;
var
  Ring: TBodyRing;
begin
  Result := 0;
  for Ring in TorsoRings(Measures) do
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
