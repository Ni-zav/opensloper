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

// Cubic Bézier curves: evaluation, length, splitting, bounds, closest point,
// transforms and intersections. Units are mm, angles degrees. No LCL dependency.
unit Sloper.Core.Bezier;

{$mode ObjFPC}{$H+}
{$modeswitch advancedrecords}
{$modeswitch nestedprocvars}

interface

uses
  Sloper.Core.Geometry, Sloper.Core.Numeric;

const
  // Flattening tolerance used to find intersections before refining, in mm
  COARSE_FLATNESS = 0.05;

type
  TCurveSample = record
    T: double;
    Point: TVec2;
  end;

  TCurveSampleArray = array of TCurveSample;

  // Start P0, control points P1 and P2, end P3; parameter T runs 0 to 1
  TCubicBezier = record
    P0, P1, P2, P3: TVec2;
    function PointAt(T: double): TVec2;
    function DerivativeAt(T: double): TVec2;
    // The direction the curve runs at T, not normalised. At an end with a
    // handle of zero length, where the derivative is zero, it is the limit:
    // towards the next control point that is not on that end. Zero only when
    // the whole curve is one point.
    function TangentAt(T: double): TVec2;
    function SecondDerivativeAt(T: double): TVec2;
    function Length: double;
    function LengthBetween(T0, T1: double): double;
    // Parameter at arc length S from the start, clamped to the curve
    function ParamAtLength(S: double): double;
    function PointAtLength(S: double): TVec2;
    // Direction of the start handle (angle1) and end handle (angle2)
    function StartAngle: double;
    function EndAngle: double;
    procedure Split(T: double; out First, Second: TCubicBezier);
    function Bounds: TRect2;
    // Polyline whose points lie on the curve, within Tolerance of it
    function Flatten(Tolerance: double): TCurveSampleArray;
    // Parameter of the nearest point on the curve to P
    function ClosestParam(const P: TVec2): double;
    // Where (B(t) - P) . B'(t) changes sign or is zero, in order: where the
    // distance from P turns, nearest and farthest. Two turns closer than a
    // sixty-fourth of the curve may be missed, which only a curve grazing
    // the circle round P has.
    function SquareParams(const P: TVec2): TDoubleArray;
    // Every parameter where the line from P is square to the curve, nearest
    // or not, in order; the ends only where the curve is square there too
    function PerpendicularParams(const P: TVec2): TDoubleArray;
    function Reversed: TCubicBezier;
    function Translated(const D: TVec2): TCubicBezier;
    function Rotated(const Pivot: TVec2; AngleDeg: double): TCubicBezier;
    function Mirrored(const A, B: TVec2): TCubicBezier;
  end;

function CubicBezier(const P0, P1, P2, P3: TVec2): TCubicBezier;
// Curve from Start to Finish whose handles leave Start at Angle1 with length
// Length1 and leave Finish at Angle2 with length Length2
function BezierFromHandles(const Start: TVec2; Angle1, Length1: double; const Finish: TVec2; Angle2, Length2: double): TCubicBezier;

// Crossings of a curve with a line, sorted by curve parameter (T1); T2 is the
// line parameter. Empty when the curve lies along the line.
function IntersectBezierLine(const C: TCubicBezier; const L: TLine2; ExtendLine: boolean): TIntersectionArray;
// Crossings of two curves, sorted by the first curve's parameter
function IntersectBeziers(const A, B: TCubicBezier): TIntersectionArray;
// Crossings of a curve with a circle, sorted by curve parameter
function IntersectBezierCircle(const C: TCubicBezier; const Centre: TVec2; Radius: double): TIntersectionArray;

implementation

uses
  Math;

const
  LENGTH_TOLERANCE = 1e-9;
  MAX_FLATTEN_DEPTH = 18;
  NEWTON_ITERATIONS = 30;
  // Parameter tolerance when merging duplicate crossings
  MERGE_PARAM_TOLERANCE = 1e-7;

  { TCubicBezier }

function TCubicBezier.PointAt(T: double): TVec2;
var
  U, B0, B1, B2, B3: double;
begin
  U := 1 - T;
  B0 := U * U * U;
  B1 := 3 * U * U * T;
  B2 := 3 * U * T * T;
  B3 := T * T * T;
  Result := Vec2(B0 * P0.X + B1 * P1.X + B2 * P2.X + B3 * P3.X, B0 * P0.Y + B1 * P1.Y + B2 * P2.Y + B3 * P3.Y);
end;

function TCubicBezier.DerivativeAt(T: double): TVec2;
var
  U: double;
begin
  U := 1 - T;
  Result := (P1 - P0) * (3 * U * U) + (P2 - P1) * (6 * U * T) + (P3 - P2) * (3 * T * T);
end;

function TCubicBezier.TangentAt(T: double): TVec2;
begin
  Result := DerivativeAt(T);
  if (Result.X <> 0) or (Result.Y <> 0) then
    Exit;
  if T <= 0 then
  begin
    Result := P2 - P0;
    if (Result.X = 0) and (Result.Y = 0) then
      Result := P3 - P0;
  end
  else if T >= 1 then
  begin
    Result := P3 - P1;
    if (Result.X = 0) and (Result.Y = 0) then
      Result := P3 - P0;
  end;
end;

function TCubicBezier.SecondDerivativeAt(T: double): TVec2;
begin
  Result := (P2 - P1 * 2 + P0) * (6 * (1 - T)) + (P3 - P2 * 2 + P1) * (6 * T);
end;

function TCubicBezier.Length: double;
begin
  Result := LengthBetween(0, 1);
end;

function TCubicBezier.LengthBetween(T0, T1: double): double;

  function Speed(T: double): double;
  begin
    Result := DerivativeAt(T).Length;
  end;

begin
  Result := Integrate(@Speed, T0, T1, LENGTH_TOLERANCE);
end;

function TCubicBezier.ParamAtLength(S: double): double;
var
  Total, Lo, Hi, T, F, D, Next, KnownT, KnownLength: double;
  I: integer;
begin
  Total := Length;
  if (S <= 0) or (Total < EPSILON) then
    Exit(0);
  if S >= Total then
    Exit(1);
  Lo := 0;
  Hi := 1;
  T := S / Total;
  // The length to the last guess is kept, so each step integrates only from
  // there to the next guess, not from the start
  KnownT := 0;
  KnownLength := 0;
  for I := 1 to NEWTON_ITERATIONS do
  begin
    if T >= KnownT then
      KnownLength := KnownLength + LengthBetween(KnownT, T)
    else
      KnownLength := KnownLength - LengthBetween(T, KnownT);
    KnownT := T;
    F := KnownLength - S;
    if Abs(F) <= LENGTH_TOLERANCE * 10 then
      Break;
    if F > 0 then
      Hi := T
    else
      Lo := T;
    // Newton step on arc length, falling back to bisection
    D := DerivativeAt(T).Length;
    if D > EPSILON then
      Next := T - F / D
    else
      Next := (Lo + Hi) / 2;
    if (Next <= Lo) or (Next >= Hi) then
      Next := (Lo + Hi) / 2;
    T := Next;
  end;
  Result := T;
end;

function TCubicBezier.PointAtLength(S: double): TVec2;
begin
  Result := PointAt(ParamAtLength(S));
end;

function TCubicBezier.StartAngle: double;
begin
  // A zero-length handle has no direction; use the next control point
  if not PointsNear(P1, P0, EPSILON) then
    Result := AngleBetween(P0, P1)
  else if not PointsNear(P2, P0, EPSILON) then
    Result := AngleBetween(P0, P2)
  else
    Result := AngleBetween(P0, P3);
end;

function TCubicBezier.EndAngle: double;
begin
  if not PointsNear(P2, P3, EPSILON) then
    Result := AngleBetween(P3, P2)
  else if not PointsNear(P1, P3, EPSILON) then
    Result := AngleBetween(P3, P1)
  else
    Result := AngleBetween(P3, P0);
end;

procedure TCubicBezier.Split(T: double; out First, Second: TCubicBezier);
var
  A, B, C, AB, BC, Mid: TVec2;
begin
  // de Casteljau
  A := Lerp(P0, P1, T);
  B := Lerp(P1, P2, T);
  C := Lerp(P2, P3, T);
  AB := Lerp(A, B, T);
  BC := Lerp(B, C, T);
  Mid := Lerp(AB, BC, T);
  First := CubicBezier(P0, A, AB, Mid);
  Second := CubicBezier(Mid, BC, C, P3);
end;

function TCubicBezier.Bounds: TRect2;

  procedure Include(const P: TVec2);
  begin
    Result.MinX := Min(Result.MinX, P.X);
    Result.MinY := Min(Result.MinY, P.Y);
    Result.MaxX := Max(Result.MaxX, P.X);
    Result.MaxY := Max(Result.MaxY, P.Y);
  end;

  // Extremes along one axis are where the derivative is zero
  procedure IncludeExtremes(C0, C1, C2, C3: double);
  var
    E, F, G: double;
    Roots: TDoubleArray;
    T: double;
  begin
    E := C1 - C0;
    F := C2 - C1;
    G := C3 - C2;
    Roots := SolveQuadratic(E - 2 * F + G, 2 * (F - E), E);
    for T in Roots do
      if (T > 0) and (T < 1) then
        Include(PointAt(T));
  end;

begin
  Result.MinX := Min(P0.X, P3.X);
  Result.MinY := Min(P0.Y, P3.Y);
  Result.MaxX := Max(P0.X, P3.X);
  Result.MaxY := Max(P0.Y, P3.Y);
  IncludeExtremes(P0.X, P1.X, P2.X, P3.X);
  IncludeExtremes(P0.Y, P1.Y, P2.Y, P3.Y);
end;

function TCubicBezier.Flatten(Tolerance: double): TCurveSampleArray;
var
  Count: integer;

  procedure Add(T: double; const P: TVec2);
  begin
    if Count = System.Length(Result) then
      SetLength(Result, Count * 2 + 16);
    Result[Count].T := T;
    Result[Count].Point := P;
    Inc(Count);
  end;

  // Adds the end of the piece; its start is already in the list
  procedure Subdivide(const C: TCubicBezier; T0, T1: double; Depth: integer);
  var
    Chord: TLine2;
    Flat: boolean;
    First, Second: TCubicBezier;
  begin
    Chord := Line2(C.P0, C.P3);
    Flat := (Distance(Chord.ClosestPoint(C.P1, False), C.P1) <= Tolerance) and (Distance(Chord.ClosestPoint(C.P2, False), C.P2) <= Tolerance);
    if Flat or (Depth >= MAX_FLATTEN_DEPTH) then
      Add(T1, C.P3)
    else
    begin
      C.Split(0.5, First, Second);
      Subdivide(First, T0, (T0 + T1) / 2, Depth + 1);
      Subdivide(Second, (T0 + T1) / 2, T1, Depth + 1);
    end;
  end;

begin
  Result := nil;
  Count := 0;
  Add(0, P0);
  Subdivide(Self, 0, 1, 0);
  SetLength(Result, Count);
end;

function TCubicBezier.SquareParams(const P: TVec2): TDoubleArray;
const
  // (B(t) - P) . B'(t) has degree five, so at most five roots
  SAMPLES = 64;
  BISECTIONS = 60;
var
  Index, Step: integer;
  Lo, Hi, FLo, FHi, Mid: double;

  function Squareness(T: double): double;
  begin
    Result := Dot(PointAt(T) - P, DerivativeAt(T));
  end;

begin
  Result := nil;
  FLo := Squareness(0);
  if FLo = 0 then
    Insert(0.0, Result, System.Length(Result));
  for Index := 1 to SAMPLES do
  begin
    Lo := (Index - 1) / SAMPLES;
    Hi := Index / SAMPLES;
    FHi := Squareness(Hi);
    if FHi = 0 then
      Insert(Hi, Result, System.Length(Result))
    else if (FLo <> 0) and ((FLo < 0) <> (FHi < 0)) then
    begin
      for Step := 1 to BISECTIONS do
      begin
        Mid := (Lo + Hi) / 2;
        if (Squareness(Mid) < 0) = (FLo < 0) then
          Lo := Mid
        else
          Hi := Mid;
      end;
      Insert((Lo + Hi) / 2, Result, System.Length(Result));
    end;
    FLo := FHi;
  end;
end;

function TCubicBezier.PerpendicularParams(const P: TVec2): TDoubleArray;
var
  T: double;

// Kept in order, once, and only where it is square to within
// DEFAULT_TOLERANCE, which a sign change at a cusp need not be
  procedure Add(T: double);
  var
    Foot, Tangent: TVec2;
    Slot: integer;
  begin
    Foot := PointAt(T);
    Tangent := TangentAt(T);
    if (Tangent.Length <= EPSILON) or (Abs(Dot(P - Foot, Tangent * (1 / Tangent.Length))) > DEFAULT_TOLERANCE) then
      Exit;
    Slot := System.Length(Result);
    while (Slot > 0) and (Result[Slot - 1] > T) do
      Dec(Slot);
    if ((Slot > 0) and (T - Result[Slot - 1] <= MERGE_PARAM_TOLERANCE)) or
      ((Slot < System.Length(Result)) and (Result[Slot] - T <= MERGE_PARAM_TOLERANCE)) then
      Exit;
    Insert(T, Result, Slot);
  end;

begin
  Result := nil;
  for T in SquareParams(P) do
    Add(T);
  // A grazing foot, two turns too close for the samples to part
  Add(ClosestParam(P));
end;

function TCubicBezier.ClosestParam(const P: TVec2): double;
var
  Samples: TCurveSampleArray;
  I, J: integer;
  BestT, BestDist, T, Dist, F, DF: double;
  Seg: TLine2;
  Q, D1: TVec2;
begin
  Samples := Flatten(COARSE_FLATNESS);
  BestT := 0;
  BestDist := Distance(P, P0);
  for I := 1 to High(Samples) do
  begin
    Seg := Line2(Samples[I - 1].Point, Samples[I].Point);
    T := EnsureRange(Seg.ParamOf(P), 0, 1);
    Dist := Distance(P, Seg.PointAt(T));
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestT := Samples[I - 1].T + (Samples[I].T - Samples[I - 1].T) * T;
    end;
  end;

  // Newton on (B(t) - P) . B'(t) = 0
  T := BestT;
  for J := 1 to NEWTON_ITERATIONS do
  begin
    Q := PointAt(T) - P;
    D1 := DerivativeAt(T);
    F := Dot(Q, D1);
    DF := Dot(D1, D1) + Dot(Q, SecondDerivativeAt(T));
    if Abs(DF) < EPSILON then
      Break;
    T := EnsureRange(T - F / DF, 0, 1);
    if Abs(F / DF) < 1e-12 then
      Break;
  end;
  if Distance(PointAt(T), P) <= Distance(PointAt(BestT), P) then
    Result := T
  else
    Result := BestT;
end;

function TCubicBezier.Reversed: TCubicBezier;
begin
  Result := CubicBezier(P3, P2, P1, P0);
end;

function TCubicBezier.Translated(const D: TVec2): TCubicBezier;
begin
  Result := CubicBezier(P0 + D, P1 + D, P2 + D, P3 + D);
end;

function TCubicBezier.Rotated(const Pivot: TVec2; AngleDeg: double): TCubicBezier;
begin
  Result := CubicBezier(RotatePoint(P0, Pivot, AngleDeg), RotatePoint(P1, Pivot, AngleDeg), RotatePoint(P2, Pivot, AngleDeg), RotatePoint(P3, Pivot, AngleDeg));
end;

function TCubicBezier.Mirrored(const A, B: TVec2): TCubicBezier;
begin
  Result := CubicBezier(MirrorPoint(P0, A, B), MirrorPoint(P1, A, B), MirrorPoint(P2, A, B), MirrorPoint(P3, A, B));
end;

{ Functions }

function CubicBezier(const P0, P1, P2, P3: TVec2): TCubicBezier;
begin
  Result.P0 := P0;
  Result.P1 := P1;
  Result.P2 := P2;
  Result.P3 := P3;
end;

function BezierFromHandles(const Start: TVec2; Angle1, Length1: double; const Finish: TVec2; Angle2, Length2: double): TCubicBezier;
begin
  Result := CubicBezier(Start, PolarPoint(Start, Length1, Angle1), PolarPoint(Finish, Length2, Angle2), Finish);
end;

// Sorts by T1 and drops crossings that are the same point found twice, for
// example where two flattened segments share an end
procedure MergeIntersections(var Hits: TIntersectionArray);
var
  I, N: integer;
  DT: double;
  Duplicate: boolean;
begin
  SortIntersections(Hits);
  N := 0;
  for I := 0 to High(Hits) do
  begin
    Duplicate := False;
    if N > 0 then
    begin
      // A curve can pass through the same point twice at different
      // parameters, so a near point alone is not a duplicate
      DT := Abs(Hits[I].T1 - Hits[N - 1].T1);
      Duplicate := (DT <= MERGE_PARAM_TOLERANCE) or ((DT <= 1e-4) and PointsNear(Hits[I].Point, Hits[N - 1].Point, DEFAULT_TOLERANCE / 10));
    end;
    if not Duplicate then
    begin
      Hits[N] := Hits[I];
      Inc(N);
    end;
  end;
  SetLength(Hits, N);
end;

function IntersectBezierLine(const C: TCubicBezier; const L: TLine2; ExtendLine: boolean): TIntersectionArray;
var
  Dir: TVec2;
  D0, D1, D2, D3, T, LineT, CurveTol, LineTol: double;
  Roots: TDoubleArray;
  P: TVec2;
begin
  Result := nil;
  Dir := L.P2 - L.P1;
  if Dir.Length < EPSILON then
    Exit;
  Dir := Dir * (1 / Dir.Length);
  // Signed distances of the control points from the line; the curve's own
  // distance is the Bézier with these values, a cubic in t
  D0 := Cross(Dir, C.P0 - L.P1);
  D1 := Cross(Dir, C.P1 - L.P1);
  D2 := Cross(Dir, C.P2 - L.P1);
  D3 := Cross(Dir, C.P3 - L.P1);
  if Max(Max(Abs(D0), Abs(D1)), Max(Abs(D2), Abs(D3))) < EPSILON then
    Exit; // the curve lies along the line
  Roots := SolveCubic(-D0 + 3 * D1 - 3 * D2 + D3, 3 * D0 - 6 * D1 + 3 * D2, -3 * D0 + 3 * D1, D0);

  CurveTol := DEFAULT_TOLERANCE / Max(C.Length, EPSILON);
  LineTol := DEFAULT_TOLERANCE / L.Length;
  for T in Roots do
  begin
    if (T < -CurveTol) or (T > 1 + CurveTol) then
      Continue;
    P := C.PointAt(EnsureRange(T, 0, 1));
    LineT := L.ParamOf(P);
    if ExtendLine or ((LineT >= -LineTol) and (LineT <= 1 + LineTol)) then
      AddIntersection(Result, P, EnsureRange(T, 0, 1), LineT);
  end;
  MergeIntersections(Result);
end;

// Newton on A(s) - B(t) = 0. False if it does not converge inside both curves.
function RefineCurveCrossing(const A, B: TCubicBezier; var S, T: double): boolean;
var
  I: integer;
  F, DA, DB, NegF, NegDB: TVec2;
  Det, DS, DT: double;
begin
  for I := 1 to NEWTON_ITERATIONS do
  begin
    F := A.PointAt(S) - B.PointAt(T);
    if F.Length < 1e-10 then
      Break;
    DA := A.DerivativeAt(S);
    DB := B.DerivativeAt(T);
    NegF := -F;
    NegDB := -DB;
    // Solve DA*dS - DB*dT = -F by Cramer's rule
    Det := Cross(DA, NegDB);
    if Abs(Det) < EPSILON then
      Exit(False);
    DS := Cross(NegF, NegDB) / Det;
    DT := Cross(DA, NegF) / Det;
    S := S + DS;
    T := T + DT;
    if (S < -0.5) or (S > 1.5) or (T < -0.5) or (T > 1.5) then
      Exit(False);
  end;
  Result := (S >= -MERGE_PARAM_TOLERANCE) and (S <= 1 + MERGE_PARAM_TOLERANCE) and (T >= -MERGE_PARAM_TOLERANCE) and
    (T <= 1 + MERGE_PARAM_TOLERANCE) and (Distance(A.PointAt(EnsureRange(S, 0, 1)), B.PointAt(EnsureRange(T, 0, 1))) <= DEFAULT_TOLERANCE / 10);
  S := EnsureRange(S, 0, 1);
  T := EnsureRange(T, 0, 1);
end;

// Newton towards the nearest approach of A at S and B at T, where the
// gradient of half the squared distance between them is zero
procedure RefineClosestApproach(const A, B: TCubicBezier; var S, T: double);
var
  I: integer;
  F, DA, DB: TVec2;
  G1, G2, H11, H12, H22, Det, DS, DT: double;
begin
  for I := 1 to NEWTON_ITERATIONS do
  begin
    F := A.PointAt(S) - B.PointAt(T);
    DA := A.DerivativeAt(S);
    DB := B.DerivativeAt(T);
    G1 := Dot(F, DA);
    G2 := -Dot(F, DB);
    H11 := Dot(DA, DA) + Dot(F, A.SecondDerivativeAt(S));
    H12 := -Dot(DA, DB);
    H22 := Dot(DB, DB) - Dot(F, B.SecondDerivativeAt(T));
    Det := H11 * H22 - H12 * H12;
    if Abs(Det) < EPSILON then
      Break;
    DS := (G1 * H22 - G2 * H12) / Det;
    DT := (G2 * H11 - G1 * H12) / Det;
    S := EnsureRange(S - DS, 0, 1);
    T := EnsureRange(T - DT, 0, 1);
    if (Abs(DS) < 1e-12) and (Abs(DT) < 1e-12) then
      Break;
  end;
end;

// How far a curve can stray from its chord: no further than its handles do
function ChordBend(const C: TCubicBezier): double;
var
  Chord: TLine2;
begin
  Chord := Line2(C.P0, C.P3);
  Result := Max(Distance(C.P1, Chord.ClosestPoint(C.P1, False)), Distance(C.P2, Chord.ClosestPoint(C.P2, False)));
end;

// The least distance between two segments, and where on each it is
function ChordGap(const First, Second: TLine2; out OnFirst, OnSecond: double): double;
var
  Hit: TIntersection;
  Candidate: double;
begin
  if IntersectLines(First, Second, False, False, Hit) then
  begin
    OnFirst := EnsureRange(Hit.T1, 0, 1);
    OnSecond := EnsureRange(Hit.T2, 0, 1);
    Exit(0);
  end;
  OnFirst := 0;
  OnSecond := EnsureRange(Second.ParamOf(First.P1), 0, 1);
  Result := Distance(First.P1, Second.PointAt(OnSecond));
  Candidate := Distance(First.P2, Second.ClosestPoint(First.P2, False));
  if Candidate < Result then
  begin
    Result := Candidate;
    OnFirst := 1;
    OnSecond := EnsureRange(Second.ParamOf(First.P2), 0, 1);
  end;
  Candidate := Distance(Second.P1, First.ClosestPoint(Second.P1, False));
  if Candidate < Result then
  begin
    Result := Candidate;
    OnFirst := EnsureRange(First.ParamOf(Second.P1), 0, 1);
    OnSecond := 0;
  end;
  Candidate := Distance(Second.P2, First.ClosestPoint(Second.P2, False));
  if Candidate < Result then
  begin
    Result := Candidate;
    OnFirst := EnsureRange(First.ParamOf(Second.P2), 0, 1);
    OnSecond := 1;
  end;
end;

function IntersectBeziers(const A, B: TCubicBezier): TIntersectionArray;
const
  // Pieces this close to their chords are taken as straight
  FLAT = 1e-4;
  MAX_DEPTH = 40;
  // Pairs of pieces looked at before the curves are taken to overlap
  WORK_LIMIT = 20000;
  // Two cubic curves that do not share a stretch cross at most 9 times
  MAX_CROSSINGS = 9;
var
  Work: integer;
  Overlap: boolean;

  procedure Add(S, T: double);
  begin
    if Distance(A.PointAt(S), B.PointAt(T)) <= DEFAULT_TOLERANCE / 10 then
      AddIntersection(Result, A.PointAt(S), S, T);
  end;

  // Pieces PA of A from A0 to A1 and PB of B from B0 to B1, halved while
  // they are near enough to meet and not yet straight
  procedure Visit(const PA: TCubicBezier; A0, A1: double; const PB: TCubicBezier; B0, B1: double; Depth: integer);
  var
    BendA, BendB, OnA, OnB, S, T: double;
    FirstA, SecondA, FirstB, SecondB: TCubicBezier;
    Crossed: boolean;
  begin
    if Overlap then
      Exit;
    Inc(Work);
    if Work > WORK_LIMIT then
    begin
      Overlap := True;
      Exit;
    end;
    BendA := ChordBend(PA);
    BendB := ChordBend(PB);
    if ChordGap(Line2(PA.P0, PA.P3), Line2(PB.P0, PB.P3), OnA, OnB) > BendA + BendB + DEFAULT_TOLERANCE / 10 then
      Exit;
    if ((BendA <= FLAT) and (BendB <= FLAT)) or (Depth >= MAX_DEPTH) then
    begin
      S := A0 + (A1 - A0) * OnA;
      T := B0 + (B1 - B0) * OnB;
      // A crossing refines on the curves; where they only touch, or cross
      // at a slant too slight to solve, their nearest approach is the point
      Crossed := RefineCurveCrossing(A, B, S, T);
      if not Crossed then
      begin
        S := A0 + (A1 - A0) * OnA;
        T := B0 + (B1 - B0) * OnB;
        RefineClosestApproach(A, B, S, T);
      end;
      Add(S, T);
      Exit;
    end;
    PA.Split(0.5, FirstA, SecondA);
    PB.Split(0.5, FirstB, SecondB);
    Visit(FirstA, A0, (A0 + A1) / 2, FirstB, B0, (B0 + B1) / 2, Depth + 1);
    Visit(FirstA, A0, (A0 + A1) / 2, SecondB, (B0 + B1) / 2, B1, Depth + 1);
    Visit(SecondA, (A0 + A1) / 2, A1, FirstB, B0, (B0 + B1) / 2, Depth + 1);
    Visit(SecondA, (A0 + A1) / 2, A1, SecondB, (B0 + B1) / 2, B1, Depth + 1);
  end;

  // Where the curves only touch, they stay within tolerance for a short
  // stretch, and pieces along it can each give a point of it: neighbours
  // with the curves still together halfway between are one touch, kept
  // where the curves are nearest. Two crossings have a gap between them.
  procedure MergeTouches;
  var
    Index, Kept: integer;
    MidS, MidT: double;
  begin
    Kept := 0;
    for Index := 1 to High(Result) do
    begin
      MidS := (Result[Kept].T1 + Result[Index].T1) / 2;
      MidT := (Result[Kept].T2 + Result[Index].T2) / 2;
      if PointsNear(Result[Kept].Point, Result[Index].Point) and
        (Distance(A.PointAt(MidS), B.PointAt(MidT)) <= DEFAULT_TOLERANCE / 10) then
      begin
        if Distance(A.PointAt(Result[Index].T1), B.PointAt(Result[Index].T2)) <
          Distance(A.PointAt(Result[Kept].T1), B.PointAt(Result[Kept].T2)) then
          Result[Kept] := Result[Index];
      end
      else
      begin
        Inc(Kept);
        Result[Kept] := Result[Index];
      end;
    end;
    if Length(Result) > 0 then
      SetLength(Result, Kept + 1);
  end;

begin
  Result := nil;
  Work := 0;
  Overlap := False;
  Visit(A, 0, 1, B, 0, 1, 0);
  MergeIntersections(Result);
  MergeTouches;
  // More than two cubics can cross, or too much to look at: they share a
  // stretch, which has no crossing point to give
  if Overlap or (Length(Result) > MAX_CROSSINGS) then
    Result := nil;
end;

function IntersectBezierCircle(const C: TCubicBezier; const Centre: TVec2; Radius: double): TIntersectionArray;
const
  BISECTIONS = 60;
var
  Breaks: TDoubleArray;
  Index, Step: integer;
  Lo, Hi, Mid, GLo, GHi: double;

// How far outside the circle the curve is at T, in mm
  function Gap(T: double): double;
  begin
    Result := Distance(C.PointAt(T), Centre) - Radius;
  end;

begin
  Result := nil;
  // Between the turns of the curve's distance from the centre, the distance
  // only rises or falls, so each stretch crosses the circle at most once,
  // and a turn on the circle is a touch. Crossings closer together than any
  // flattening are found as surely as those far apart.
  Breaks := C.SquareParams(Centre);
  Insert(0.0, Breaks, 0);
  Insert(1.0, Breaks, System.Length(Breaks));
  for Index := 0 to High(Breaks) do
    if Abs(Gap(Breaks[Index])) <= DEFAULT_TOLERANCE / 10 then
      AddIntersection(Result, C.PointAt(Breaks[Index]), Breaks[Index], 0);
  for Index := 1 to High(Breaks) do
  begin
    Lo := Breaks[Index - 1];
    Hi := Breaks[Index];
    GLo := Gap(Lo);
    GHi := Gap(Hi);
    if (Abs(GLo) <= DEFAULT_TOLERANCE / 10) or (Abs(GHi) <= DEFAULT_TOLERANCE / 10) or ((GLo < 0) = (GHi < 0)) then
      Continue;
    for Step := 1 to BISECTIONS do
    begin
      Mid := (Lo + Hi) / 2;
      if (Gap(Mid) < 0) = (GLo < 0) then
        Lo := Mid
      else
        Hi := Mid;
    end;
    Mid := (Lo + Hi) / 2;
    AddIntersection(Result, C.PointAt(Mid), Mid, 0);
  end;
  MergeIntersections(Result);
end;

end.
