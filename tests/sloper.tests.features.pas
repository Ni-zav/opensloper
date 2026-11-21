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

// Features applied in one step: a zip in a piece's edge, and a dart
unit Sloper.Tests.Features;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern,
  Sloper.Core.Features;

type
  TTestFeatures = class(TOSTestCase)
  private
    FPattern: TPattern;
    // Corners at (Left, 0) and (Left + Width, Height); Right runs down from
    // the top right corner, and Back down the left side, against the way
    // the piece runs round
    function Panel(Left, Width, Height: double; out Right: string): TPieceObject;
    function PanelSides(Left, Width, Height: double; out Right, Back: string): TPieceObject;
    function Zip(const EdgeKey: string; out Made: TZipMade): boolean;
    // 200 by 300 from (0, 0), Top running right along y = 0
    function Bodice(out Top: string): TPieceObject;
    function Dart(const EdgeKey: string; out Made: TDartMade): boolean;
    function PointAt(const Key: string): TVec2;
    // How far the point is from the piece's cutting line
    function OffCutLine(Piece: TPieceObject; const Point: TVec2): double;
    // A dart in the middle of the top, with a 20 mm allowance right of it
    function CappedDart(TowardsEnd: boolean): TPieceObject;
    procedure AssertOnCutLine(Piece: TPieceObject; const Points: array of TVec2);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestZipStopsAtItsLength;
    procedure TestZipSplitsThePieceEdge;
    procedure TestZipWidensTheOpening;
    procedure TestZipNotchesTheStop;
    procedure TestCentredZipIsTopstitchedInside;
    procedure TestTopstitchedInsideEitherWayRound;
    procedure TestInvisibleZipHasNoTopstitching;
    procedure TestZipFromTheEnd;
    procedure TestZipsShareTheirLength;
    procedure TestZipInCentimetres;
    procedure TestZipTooLongIsRefused;
    procedure TestZipNeedsAPiece;
    procedure TestLappedZipStitchesAcrossTheStop;
    procedure TestFlyFrontStitchesAJ;
    procedure TestFlyFrontEitherWayRound;
    procedure TestFlyFrontAddsAShield;
    procedure TestStylesStartWithTheirOwnWidths;
    procedure TestDartOnAStraightEdge;
    procedure TestDartTakesThePlaceOfItsOpening;
    procedure TestDartIsMarked;
    procedure TestDartOnACurvedEdge;
    procedure TestDartFromTheEnd;
    procedure TestDartToAPickedPoint;
    procedure TestDartIsOneUndoStep;
    procedure TestDartCapPeaksOverTheCentre;
    procedure TestDartCapPressedTowardsTheStart;
    procedure TestDartCapPressedTowardsTheEnd;
    procedure TestDartCapIsSaved;
    procedure TestDartClosesInTheGarment;
    procedure TestDartNeedsAPiece;
    procedure TestDartTooWideIsRefused;
    procedure TestDartPastAnEndIsRefused;
    procedure TestDartNeedsADepth;
    procedure TestDartPointOutsideIsRefused;
    procedure TestDartLegsCrossingIsRefused;
    procedure TestDartInAFoldIsRefused;
  end;

implementation

uses
  SysUtils, Math, Sloper.Core.EvalTypes, Sloper.Core.PieceDetect, Sloper.Core.Units, Sloper.Core.Seam,
  Sloper.Core.Garment, Sloper.Core.PatternFile, Sloper.Document.PatternDocument;

const
  // The cutting line is rounded to 0.001 mm
  CUT_TOLERANCE = 0.01;

procedure TTestFeatures.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestFeatures.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestFeatures.Panel(Left, Width, Height: double; out Right: string): TPieceObject;
var
  Back: string;
begin
  Result := PanelSides(Left, Width, Height, Right, Back);
end;

function TTestFeatures.PanelSides(Left, Width, Height: double; out Right, Back: string): TPieceObject;
var
  A, B, C, D, Reason: string;
  Path: TPiecePath;

  function Pt(X, Y: double): string;
  begin
    Result := FPattern.AddFreePoint('', FloatToStr(X), FloatToStr(Y)).Key;
  end;

begin
  A := Pt(Left, 0);
  B := Pt(Left + Width, 0);
  C := Pt(Left + Width, Height);
  D := Pt(Left, Height);
  FPattern.AddLine(A, B, erOutline);
  Right := FPattern.AddLine(B, C, erOutline).Key;
  FPattern.AddLine(C, D, erOutline);
  Back := FPattern.AddLine(A, D, erOutline).Key;
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Width / 2, Height / 2), Path, Reason));
  Result := FPattern.AddPiece('', Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestFeatures.Zip(const EdgeKey: string; out Made: TZipMade): boolean;
begin
  Result := InsertZip(FPattern, DefaultZip(FPattern, EdgeKey), Made);
end;

procedure TTestFeatures.TestZipStopsAtItsLength;
var
  Right: string;
  Made: TZipMade;
begin
  Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  AssertNotNull('its length is a variable', FPattern.FindVariable(ZIP_LENGTH_VARIABLE));
  AssertNear('200 mm to start with', 200, FPattern.FindVariable(ZIP_LENGTH_VARIABLE).Value);
  AssertPointsNear('200 mm down the edge', Vec2(100, 200), TPointObject(FPattern.FindNode(Made.StopKey)).Position);
  AssertEquals('named for what it is', ZIP_STOP_NAME, TDraftObject(FPattern.FindNode(Made.StopKey)).Name);
end;

procedure TTestFeatures.TestZipSplitsThePieceEdge;
var
  Piece: TPieceObject;
  Right: string;
  Made: TZipMade;
begin
  Piece := Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  AssertEquals('the whole edge is gone', -1, Piece.PathIndexOf(Right));
  AssertTrue('the opening', Piece.PathIndexOf(Made.OpeningKey) >= 0);
  AssertTrue('the rest', Piece.PathIndexOf(Made.RestKey) >= 0);
  AssertNear('the opening is the zip', 200, TEdgeObject(FPattern.FindNode(Made.OpeningKey)).Length);
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('one piece', 1, Length(Made.PieceKeys));
end;

procedure TTestFeatures.TestZipWidensTheOpening;
var
  Piece: TPieceObject;
  Right: string;
  Made: TZipMade;
  Index: integer;
begin
  Piece := Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  Index := Piece.PathIndexOf(Made.OpeningKey);
  AssertTrue('the opening has its own allowance', Piece.HasOverride(Index));
  AssertEquals('20', FPattern.FormulaText(Piece, Piece.OverrideField(Index)));
  AssertFalse('the rest keeps the piece''s', Piece.HasOverride(Piece.PathIndexOf(Made.RestKey)));
end;

procedure TTestFeatures.TestZipNotchesTheStop;
var
  Piece: TPieceObject;
  Right: string;
  Made: TZipMade;
begin
  Piece := Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  AssertEquals('one notch', 1, Length(Piece.Notches));
  AssertEquals('at the stop', Made.StopKey, Piece.Notches[0].PointKey);
end;

procedure TTestFeatures.TestCentredZipIsTopstitchedInside;
var
  Right: string;
  Made: TZipMade;
  Stitch: TEdgeObject;
begin
  Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  AssertEquals('one line', 1, Length(Made.StitchKeys));
  Stitch := TEdgeObject(FPattern.FindNode(Made.StitchKeys[0]));
  AssertTrue('a stitch line', Stitch.Role = erStitch);
  AssertTrue(Stitch.Message, Stitch.State = esValid);
  AssertPointsNear('7 mm inside the piece', Vec2(93, 100), Stitch.PointAtLength(100));
  AssertNear('along the opening', 200, Stitch.Length);
end;

// A piece runs one of its sides against the way the edge was drawn; its
// topstitching is still inside it
procedure TTestFeatures.TestTopstitchedInsideEitherWayRound;
var
  Right, Back: string;
  Made: TZipMade;
  Stitch: TEdgeObject;
begin
  PanelSides(0, 100, 300, Right, Back);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  Stitch := TEdgeObject(FPattern.FindNode(Made.StitchKeys[0]));
  AssertNear('inside on the right', 93, Stitch.PointAtLength(10).X);
  AssertTrue(FPattern.LastError, Zip(Back, Made));
  Stitch := TEdgeObject(FPattern.FindNode(Made.StitchKeys[0]));
  AssertNear('inside on the left', 7, Stitch.PointAtLength(10).X);
end;

procedure TTestFeatures.TestInvisibleZipHasNoTopstitching;
var
  Right: string;
  Spec: TZipSpec;
  Made: TZipMade;
begin
  Panel(0, 100, 300, Right);
  Spec := DefaultZip(FPattern, Right);
  Spec.Style := zsInvisible;
  AssertTrue(FPattern.LastError, InsertZip(FPattern, Spec, Made));
  AssertEquals('nothing shows', 0, Length(Made.StitchKeys));
end;

procedure TTestFeatures.TestZipFromTheEnd;
var
  Piece: TPieceObject;
  Right: string;
  Spec: TZipSpec;
  Made: TZipMade;
begin
  Piece := Panel(0, 100, 300, Right);
  Spec := DefaultZip(FPattern, Right);
  Spec.FromEnd := True;
  AssertTrue(FPattern.LastError, InsertZip(FPattern, Spec, Made));
  AssertPointsNear('200 mm up from the bottom', Vec2(100, 100), TPointObject(FPattern.FindNode(Made.StopKey)).Position);
  AssertNear('the opening is the lower part', 200, TEdgeObject(FPattern.FindNode(Made.OpeningKey)).Length);
  AssertTrue('with the wider allowance', Piece.HasOverride(Piece.PathIndexOf(Made.OpeningKey)));
end;

// Both sides of a seam take the one length, so they match
procedure TTestFeatures.TestZipsShareTheirLength;
var
  Left, Right: string;
  Made: TZipMade;
begin
  Panel(0, 100, 300, Left);
  Panel(200, 100, 300, Right);
  AssertTrue(FPattern.LastError, Zip(Left, Made));
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  AssertEquals('one variable', 1, FPattern.VariableCount);
  AssertEquals('stops named apart', ZIP_STOP_NAME + '2', TDraftObject(FPattern.FindNode(Made.StopKey)).Name);
end;

procedure TTestFeatures.TestZipInCentimetres;
var
  Piece: TPieceObject;
  Right: string;
  Made: TZipMade;
begin
  FPattern.Units := muCentimetre;
  Piece := Panel(0, 10, 30, Right);
  AssertTrue(FPattern.LastError, Zip(Right, Made));
  AssertEquals('a round length', '20', FPattern.FormulaText(FPattern.FindVariable(ZIP_LENGTH_VARIABLE), 'formula'));
  AssertEquals('a round allowance', '2', FPattern.FormulaText(Piece, Piece.OverrideField(Piece.PathIndexOf(Made.OpeningKey))));
end;

procedure TTestFeatures.TestZipTooLongIsRefused;
var
  Right: string;
  Spec: TZipSpec;
  Made: TZipMade;
begin
  Panel(0, 100, 300, Right);
  Spec := DefaultZip(FPattern, Right);
  Spec.Length := '400';
  AssertFalse('longer than the edge', InsertZip(FPattern, Spec, Made));
  AssertTrue(FPattern.LastError, Pos('does not fit', FPattern.LastError) > 0);
end;

procedure TTestFeatures.TestZipNeedsAPiece;
var
  Made: TZipMade;
  Line: TLineObject;
begin
  Line := FPattern.AddLine(FPattern.AddFreePoint('', '0', '0').Key, FPattern.AddFreePoint('', '0', '300').Key, erOutline);
  FPattern.Evaluate;
  AssertFalse('no piece', Zip(Line.Key, Made));
  AssertTrue(FPattern.LastError, Pos('no piece', FPattern.LastError) > 0);
  AssertFalse('no edge', Zip('', Made));
end;

function StyledZip(Pattern: TPattern; const EdgeKey: string; Style: TZipStyle; out Made: TZipMade): boolean;
begin
  Result := InsertZip(Pattern, DefaultZip(Pattern, EdgeKey, Style), Made);
end;

// The lap's stitching runs down the opening and turns across to the seam at the stop
procedure TTestFeatures.TestLappedZipStitchesAcrossTheStop;
var
  Piece: TPieceObject;
  Right: string;
  Made: TZipMade;
  Down, Across: TEdgeObject;
begin
  Piece := Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, StyledZip(FPattern, Right, zsLapped, Made));
  AssertEquals('down and across', 2, Length(Made.StitchKeys));
  Down := TEdgeObject(FPattern.FindNode(Made.StitchKeys[0]));
  Across := TEdgeObject(FPattern.FindNode(Made.StitchKeys[1]));
  AssertTrue(Down.Message, Down.State = esValid);
  AssertTrue(Across.Message, Across.State = esValid);
  AssertNear('the lap, 10 mm in', 90, Down.PointAtLength(50).X);
  AssertTrue('stitched', Across.Role = erStitch);
  AssertNear('across the lap', 10, Across.Length);
  AssertNear('at the stop', 200, Across.PointAtLength(5).Y);
  AssertEquals('the lap''s allowance', '20', FPattern.FormulaText(Piece, Piece.OverrideField(Piece.PathIndexOf(Made.OpeningKey))));
  AssertEquals('no shield', '', Made.ShieldKey);
end;

// The fly's stitching runs down at the fly's width and curves in to the stop
procedure TTestFeatures.TestFlyFrontStitchesAJ;
var
  Piece: TPieceObject;
  Right: string;
  Made: TZipMade;
  Straight, Curve: TEdgeObject;
  Middle: TVec2;
begin
  Piece := Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, StyledZip(FPattern, Right, zsFlyFront, Made));
  AssertEquals('the extension', '40', FPattern.FormulaText(Piece, Piece.OverrideField(Piece.PathIndexOf(Made.OpeningKey))));
  AssertEquals('straight and curved', 2, Length(Made.StitchKeys));
  Straight := TEdgeObject(FPattern.FindNode(Made.StitchKeys[0]));
  Curve := TEdgeObject(FPattern.FindNode(Made.StitchKeys[1]));
  AssertTrue(Straight.Message, Straight.State = esValid);
  AssertTrue(Curve.Message, Curve.State = esValid);
  AssertTrue('stitched', (Straight.Role = erStitch) and (Curve.Role = erStitch));
  AssertNear('30 mm in', 70, Straight.PointAtLength(50).X);
  AssertNear('down to where it curves', 170, Straight.Length);
  AssertPointsNear('the curve starts there', Vec2(70, 170), Curve.PointAtLength(0));
  AssertPointsNear('and ends at the stop', Vec2(100, 200), Curve.PointAtLength(Curve.Length));
  Middle := Curve.PointAtLength(Curve.Length / 2);
  AssertTrue('rounding the corner', (Middle.X > 70) and (Middle.X < 100) and (Middle.Y > 170) and (Middle.Y < 200));
  AssertTrue('inside the corner''s square', Distance(Middle, Vec2(70, 200)) < Distance(Vec2(85, 185), Vec2(70, 200)) + 5);
end;

procedure TTestFeatures.TestFlyFrontEitherWayRound;
var
  Right, Back: string;
  Made: TZipMade;
  Curve: TEdgeObject;
begin
  PanelSides(0, 100, 300, Right, Back);
  AssertTrue(FPattern.LastError, StyledZip(FPattern, Back, zsFlyFront, Made));
  AssertNear('30 mm in from the left', 30, TEdgeObject(FPattern.FindNode(Made.StitchKeys[0])).PointAtLength(50).X);
  Curve := TEdgeObject(FPattern.FindNode(Made.StitchKeys[1]));
  AssertPointsNear('to the stop', Vec2(0, 200), Curve.PointAtLength(Curve.Length));
end;

// A separate piece behind the zip, cut on the fold, beside the pattern
procedure TTestFeatures.TestFlyFrontAddsAShield;
var
  Right: string;
  Made: TZipMade;
  Shield: TPieceObject;
  Low, High: TVec2;
  Point: TVec2;
begin
  Panel(0, 100, 300, Right);
  AssertTrue(FPattern.LastError, StyledZip(FPattern, Right, zsFlyFront, Made));
  Shield := TPieceObject(FPattern.FindNode(Made.ShieldKey));
  AssertNotNull('a shield', Shield);
  AssertTrue(Shield.Message, Shield.State = esValid);
  AssertEquals(FLY_SHIELD_NAME, Shield.Name);
  AssertTrue('on the fold', Shield.FoldEdgeKey <> '');
  Low := Shield.Outline[0];
  High := Shield.Outline[0];
  for Point in Shield.Outline do
  begin
    Low := Vec2(Min(Low.X, Point.X), Min(Low.Y, Point.Y));
    High := Vec2(Max(High.X, Point.X), Max(High.Y, Point.Y));
  end;
  AssertNear('its width, doubled on the fold', 40, High.X - Low.X);
  AssertNear('a little longer than the zip', 220, High.Y - Low.Y);
  AssertTrue('beside the pattern', Low.X > 110);
  // Its length follows the zip's
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindVariable(ZIP_LENGTH_VARIABLE), 'formula', '180'));
  FPattern.Evaluate;
  High.Y := Shield.Outline[0].Y;
  Low.Y := High.Y;
  for Point in Shield.Outline do
  begin
    Low.Y := Min(Low.Y, Point.Y);
    High.Y := Max(High.Y, Point.Y);
  end;
  AssertNear('follows the zip', 200, High.Y - Low.Y);
end;

procedure TTestFeatures.TestStylesStartWithTheirOwnWidths;
begin
  AssertEquals('7', DefaultZip(FPattern, '', zsCentred).StitchDistance);
  AssertEquals('10', DefaultZip(FPattern, '', zsLapped).StitchDistance);
  AssertEquals('30', DefaultZip(FPattern, '', zsFlyFront).StitchDistance);
  AssertEquals('40', DefaultZip(FPattern, '', zsFlyFront).Allowance);
  AssertEquals('20', DefaultZip(FPattern, '', zsLapped).Allowance);
end;

function TTestFeatures.Bodice(out Top: string): TPieceObject;
var
  A, B, C, D, Reason: string;
  Path: TPiecePath;
begin
  A := FPattern.AddFreePoint('A', '0', '0').Key;
  B := FPattern.AddFreePoint('B', '200', '0').Key;
  C := FPattern.AddFreePoint('C', '200', '300').Key;
  D := FPattern.AddFreePoint('D', '0', '300').Key;
  Top := FPattern.AddLine(A, B, erOutline).Key;
  FPattern.AddLine(B, C, erOutline);
  FPattern.AddLine(C, D, erOutline);
  FPattern.AddLine(D, A, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(100, 150), Path, Reason));
  Result := FPattern.AddPiece('Bodice', Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestFeatures.Dart(const EdgeKey: string; out Made: TDartMade): boolean;
begin
  Result := InsertDart(FPattern, DefaultDart(FPattern, EdgeKey), Made);
end;

function TTestFeatures.PointAt(const Key: string): TVec2;
begin
  Result := TPointObject(FPattern.FindNode(Key)).Position;
end;

function TTestFeatures.OffCutLine(Piece: TPieceObject; const Point: TVec2): double;
var
  Index: integer;
  Cut: TVec2Array;
  Segment: TLine2;
begin
  Result := Infinity;
  Cut := Piece.CutLine;
  for Index := 0 to High(Cut) do
  begin
    Segment := Line2(Cut[Index], Cut[(Index + 1) mod Length(Cut)]);
    Result := Min(Result, Distance(Point, Segment.ClosestPoint(Point, False)));
  end;
end;

function TTestFeatures.CappedDart(TowardsEnd: boolean): TPieceObject;
var
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
  Right: TEdgeObject;
  Entry: TPieceEdge;
begin
  Result := Bodice(Top);
  Spec := DefaultDart(FPattern, Top);
  Spec.TowardsEnd := TowardsEnd;
  AssertTrue(FPattern.LastError, InsertDart(FPattern, Spec, Made));
  // The top's part right of the dart: the one that starts at its leg
  Right := nil;
  for Entry in Result.Path do
    if TEdgeObject(FPattern.FindNode(Entry.EdgeKey)).StartKey = Made.LegPointKeys[1] then
      Right := TEdgeObject(FPattern.FindNode(Entry.EdgeKey));
  AssertNotNull('the part right of the dart', Right);
  AssertTrue(FPattern.LastError, FPattern.SetEdgeAllowance(Result, Result.PathIndexOf(Right.Key), '20'));
  FPattern.Evaluate;
  AssertTrue(Result.Message, Result.State = esValid);
end;

procedure TTestFeatures.AssertOnCutLine(Piece: TPieceObject; const Points: array of TVec2);
var
  Index: integer;
begin
  for Index := 0 to High(Points) do
    AssertNear(Format('(%g, %g) on the cutting line', [Points[Index].X, Points[Index].Y]), 0, OffCutLine(Piece, Points[Index]),
      CUT_TOLERANCE);
end;

procedure TTestFeatures.TestDartOnAStraightEdge;
var
  Top: string;
  Made: TDartMade;
begin
  Bodice(Top);
  AssertTrue(FPattern.LastError, Dart(Top, Made));
  AssertPointsNear('halfway along', Vec2(100, 0), PointAt(Made.MidKey));
  AssertPointsNear('the leg on the start''s side', Vec2(90, 0), PointAt(Made.LegPointKeys[0]));
  AssertPointsNear('the leg on the end''s side', Vec2(110, 0), PointAt(Made.LegPointKeys[1]));
  AssertPointsNear('90 mm into the piece', Vec2(100, 90), PointAt(Made.ApexKey));
  AssertEquals('named for what it is', DART_MID_NAME, TDraftObject(FPattern.FindNode(Made.MidKey)).Name);
  AssertEquals(DART_APEX_NAME, TDraftObject(FPattern.FindNode(Made.ApexKey)).Name);
end;

procedure TTestFeatures.TestDartTakesThePlaceOfItsOpening;
var
  Piece: TPieceObject;
  Top: string;
  Made: TDartMade;
  First, Second, Count: integer;
  Opening: TEdgeObject;
  Index: integer;
begin
  Piece := Bodice(Top);
  AssertTrue(FPattern.LastError, Dart(Top, Made));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('the top is gone from the outline', -1, Piece.PathIndexOf(Top));
  AssertEquals('two parts of the top and the legs in place of it', 7, Length(Piece.Path));
  First := Piece.PathIndexOf(Made.LegKeys[0]);
  Second := Piece.PathIndexOf(Made.LegKeys[1]);
  Count := Length(Piece.Path);
  AssertTrue('the legs follow each other', ((First + 1) mod Count = Second) or ((Second + 1) mod Count = First));
  // What was between the legs is construction, in no piece
  Opening := nil;
  for Index := 0 to FPattern.ObjectCount - 1 do
    if (FPattern.Objects[Index] is TEdgeObject) and (TEdgeObject(FPattern.Objects[Index]).StartKey = Made.LegPointKeys[0]) and
      (TEdgeObject(FPattern.Objects[Index]).EndKey = Made.LegPointKeys[1]) then
      Opening := TEdgeObject(FPattern.Objects[Index]);
  AssertNotNull('the opening', Opening);
  AssertTrue('construction', Opening.Role = erConstruction);
  AssertEquals('not in the outline', -1, Piece.PathIndexOf(Opening.Key));
  AssertNear('the seam line is longer by the legs, less the opening', 1000 - 20 + 2 * Sqrt(Sqr(10) + Sqr(90)), Piece.Perimeter, 1e-6);
end;

procedure TTestFeatures.TestDartIsMarked;
var
  Piece: TPieceObject;
  Top: string;
  Made: TDartMade;
  Seam: TSeamObject;
  Hole: TDraftObject;
  Centre: TEdgeObject;
begin
  Piece := Bodice(Top);
  AssertTrue(FPattern.LastError, Dart(Top, Made));
  Seam := TSeamObject(FPattern.FindNode(Made.SeamKey));
  AssertTrue(Seam.Message, Seam.State = esValid);
  AssertEquals(DART_SEAM_NAME, Seam.Name);
  AssertEquals('one leg', Made.LegKeys[0], Seam.SideA[0].EdgeKey);
  AssertEquals('to the other', Made.LegKeys[1], Seam.SideB[0].EdgeKey);
  AssertNear('the legs match', 0, Seam.Difference, 1e-6);
  AssertEquals('a notch at each leg', 2, Length(Piece.Notches));
  AssertEquals(Made.LegPointKeys[0], Piece.Notches[0].PointKey);
  AssertEquals(Made.LegPointKeys[1], Piece.Notches[1].PointKey);
  AssertPointsNear('notched from the cutting line', Vec2(90, -10), Piece.NotchMarks[0].Cut);
  Hole := TDraftObject(FPattern.FindNode(Made.HoleKey));
  AssertTrue('a hole', Hole.Marker = pmHole);
  AssertPointsNear('10 mm back from the point', Vec2(100, 80), PointAt(Made.HoleKey));
  AssertTrue('printed with the piece', Piece.PointMarkingOf(Made.HoleKey) >= 0);
  Centre := TEdgeObject(FPattern.FindNode(Made.CentreKey));
  AssertTrue('the centre line folds', Centre.Role = erFold);
  AssertTrue('printed with the piece', Piece.LineMarkingOf(Made.CentreKey) >= 0);
  AssertEquals('a cap', 1, Length(Piece.Darts));
  AssertTrue('pressed towards the start', Piece.Darts[0].TowardsFirst);
end;

procedure TTestFeatures.TestDartOnACurvedEdge;
var
  Piece: TPieceObject;
  Curve: TCurveObject;
  Path: TPiecePath;
  Reason: string;
  Made: TDartMade;
  Length0, Along, Gap, Start: double;
begin
  Curve := FPattern.AddCurve(FPattern.AddFreePoint('A', '0', '0').Key, FPattern.AddFreePoint('B', '200', '0').Key, '20', '80', '160', '80',
    erOutline);
  FPattern.AddLine(Curve.EndKey, FPattern.AddFreePoint('C', '200', '300').Key, erOutline);
  FPattern.AddLine(FPattern.FindObject('C').Key, FPattern.AddFreePoint('D', '0', '300').Key, erOutline);
  FPattern.AddLine(FPattern.FindObject('D').Key, Curve.StartKey, erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(100, 150), Path, Reason));
  Piece := FPattern.AddPiece('', Path, '10');
  FPattern.Evaluate;
  Length0 := Curve.Length;
  AssertTrue(FPattern.LastError, Dart(Curve.Key, Made));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertNear('the edge is as long as it was', Length0, Curve.Length, 1e-6);
  Curve.Locate(PointAt(Made.LegPointKeys[0]), Start, Gap);
  AssertNear('on the curve', 0, Gap, 1e-6);
  Curve.Locate(PointAt(Made.LegPointKeys[1]), Along, Gap);
  AssertNear('on the curve', 0, Gap, 1e-6);
  AssertNear('the width apart along it', 20, Along - Start, 1e-6);
  AssertNear('either side of halfway', Length0 / 2, (Along + Start) / 2, 1e-6);
end;

procedure TTestFeatures.TestDartFromTheEnd;
var
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Bodice(Top);
  Spec := DefaultDart(FPattern, Top);
  Spec.FromEnd := True;
  Spec.Position := '50';
  Spec.Width := '30';
  Spec.Depth := '100';
  AssertTrue(FPattern.LastError, InsertDart(FPattern, Spec, Made));
  AssertPointsNear('50 mm from the end', Vec2(150, 0), PointAt(Made.MidKey));
  AssertPointsNear('the start''s side is further from the end', Vec2(135, 0), PointAt(Made.LegPointKeys[0]));
  AssertPointsNear('the end''s side', Vec2(165, 0), PointAt(Made.LegPointKeys[1]));
  AssertPointsNear('100 mm in', Vec2(150, 100), PointAt(Made.ApexKey));
end;

// A dart to the bust point follows it
procedure TTestFeatures.TestDartToAPickedPoint;
var
  Piece: TPieceObject;
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
  Point: TFreePoint;
begin
  Piece := Bodice(Top);
  AssertNotNull(FPattern.AddVariable('bust_depth', '120'));
  Point := FPattern.AddFreePoint('BP', '80', '#bust_depth');
  FPattern.Evaluate;
  Spec := DefaultDart(FPattern, Top);
  Spec.ApexKey := Point.Key;
  AssertTrue(FPattern.LastError, InsertDart(FPattern, Spec, Made));
  AssertEquals('the point itself', Point.Key, Made.ApexKey);
  AssertNull('no point of its own', FPattern.FindObject(DART_APEX_NAME));
  AssertPointsNear('to the point', Vec2(80, 120), TEdgeObject(FPattern.FindNode(Made.LegKeys[0])).PointAtLength(
    TEdgeObject(FPattern.FindNode(Made.LegKeys[0])).Length));
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindVariable('bust_depth'), 'formula', '150'));
  FPattern.Evaluate;
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertPointsNear('follows the point', Vec2(80, 150), TEdgeObject(FPattern.FindNode(Made.LegKeys[1])).PointAtLength(0));
  AssertPointsNear('the hole too', Vec2(80, 150) + (Vec2(100, 0) - Vec2(80, 150)).Normalized * 10, PointAt(Made.HoleKey));
end;

procedure TTestFeatures.TestDartIsOneUndoStep;
var
  Document: TPatternDocument;
  Pattern: TPattern;
  Top, Before: string;
  Piece: TPieceObject;
  Made: TDartMade;
begin
  Document := TPatternDocument.Create;
  try
    Pattern := FPattern;
    FPattern := Document.Pattern;
    try
      Document.BeginChange('Bodice');
      Piece := Bodice(Top);
      Document.EndChange;
      Before := SavePatternToText(Document.Pattern, False);
      Document.BeginChange(rsFeatureDart);
      AssertTrue(Document.Pattern.LastError, Dart(Top, Made));
      Document.EndChange;
      AssertFalse('refused', Document.ChangeRefused);
      Document.Undo;
      AssertEquals('all of it gone', Before, SavePatternToText(Document.Pattern, False));
      Piece := TPieceObject(Document.Pattern.FindObject('Bodice'));
      AssertEquals('the top back in the outline', 4, Length(Piece.Path));
      AssertEquals('no cap', 0, Length(Piece.Darts));
    finally
      FPattern := Pattern;
    end;
  finally
    FreeAndNil(Document);
  end;
end;

// Hand-worked: with the legs at (90, 0) and (110, 0) and the point at
// (100, 90), the dart closes by 2 atan(10 / 90). Closed, the 10 mm cutting
// line is y = -10, which the centre line, folded over, meets 102.5 from the
// point; unfolded, that is the cap's peak. The legs meet it at
// (100 -+ 100 / 9, -10).
procedure TTestFeatures.TestDartCapPeaksOverTheCentre;
var
  Piece: TPieceObject;
  Top: string;
  Made: TDartMade;
  Point: TVec2;
begin
  Piece := Bodice(Top);
  AssertTrue(FPattern.LastError, Dart(Top, Made));
  AssertOnCutLine(Piece, [Vec2(100, -12.5), Vec2(100 - 100 / 9, -10), Vec2(100 + 100 / 9, -10), Vec2(50, -10), Vec2(150, -10)]);
  AssertTrue('the opening is inside it', PointInPolygon(Vec2(100, 40), Piece.CutLine));
  for Point in Piece.CutLine do
    AssertTrue('nothing above the peak', Point.Y > -12.5 - CUT_TOLERANCE);
end;

// Hand-worked, with 10 mm left of the dart and 20 mm right of it. Pressed
// to the left, the right side turns 2 atan(10 / 90) about the point onto the
// left leg; its 20 mm band starts square to it at the leg, from (90, 0) to
// (85.610, -19.512), and runs on up to the right over where the left leg
// carries on. The left's y = -10 meets it at (87.75, -10). The folded
// centre line crosses the closed cutting line at (77.5, -10) and the leg at
// (87.778, -20). Opened out, the cap mirrors that in the leg and turns it
// back for the other half.
procedure TTestFeatures.TestDartCapPressedTowardsTheStart;
var
  Piece: TPieceObject;
begin
  Piece := CappedDart(False);
  AssertOnCutLine(Piece, [Vec2(77.5, -10), Vec2(87.75, -10), Vec2(85.610, -19.512), Vec2(87.778, -20), Vec2(90, -20), Vec2(90, -10.25),
    Vec2(100, -12.5), Vec2(110, -10.25), Vec2(110, -20), Vec2(112.222, -20), Vec2(150, -20)]);
  AssertFalse('a notch between the ears', PointInPolygon(Vec2(100, -15), Piece.CutLine));
end;

// Pressed to the right, the left side turns onto the right leg: its 10 mm
// line comes in at (110, -10.25) under the right's 20 mm. The folded centre
// line crosses y = -20 at (124.75, -20), which mirrors to a peak at
// (100, -22.75).
procedure TTestFeatures.TestDartCapPressedTowardsTheEnd;
var
  Piece: TPieceObject;
begin
  Piece := CappedDart(True);
  AssertOnCutLine(Piece, [Vec2(77.5, -10), Vec2(87.75, -10), Vec2(85.610, -19.512), Vec2(87.778, -20), Vec2(100, -22.75),
    Vec2(112.222, -20), Vec2(150, -20)]);
  AssertTrue('no notch', PointInPolygon(Vec2(100, -15), Piece.CutLine));
end;

procedure TTestFeatures.TestDartCapIsSaved;
var
  Top, Text, Error: string;
  Made: TDartMade;
  Loaded: TPattern;
  Piece: TPieceObject;
begin
  Bodice(Top);
  AssertTrue(FPattern.LastError, Dart(Top, Made));
  AssertTrue(FPattern.LastError, FPattern.SetDartCap(TPieceObject(FPattern.FindObject('Bodice')), Made.LegKeys[1], Made.LegKeys[0], dpFirst));
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(Error, LoadPatternFromText(Loaded, Text, Error));
    Loaded.Evaluate;
    Piece := TPieceObject(Loaded.FindObject('Bodice'));
    AssertEquals('one cap, replaced', 1, Length(Piece.Darts));
    AssertEquals(Made.LegKeys[1], Piece.Darts[0].FirstKey);
    AssertTrue('towards it', Piece.Darts[0].TowardsFirst);
    AssertEquals('saved as it was', Text, SavePatternToText(Loaded));
  finally
    FreeAndNil(Loaded);
  end;
  AssertTrue(FPattern.LastError, FPattern.SetDartCap(TPieceObject(FPattern.FindObject('Bodice')), Made.LegKeys[0], Made.LegKeys[1], dpNone));
  AssertEquals('taken off', 0, Length(TPieceObject(FPattern.FindObject('Bodice')).Darts));
end;

procedure TTestFeatures.TestDartClosesInTheGarment;
var
  Top: string;
  Made: TDartMade;
  Scene: TGarmentScene;
begin
  Bodice(Top);
  AssertTrue(FPattern.LastError, Dart(Top, Made));
  Scene := BuildGarment(FPattern);
  AssertEquals('no notes', 0, Length(Scene.Notes));
  AssertEquals('closed, as a stitch line', 1, Length(Scene.Pieces[0].Stitches));
  AssertEquals(Made.SeamKey, Scene.Pieces[0].Stitches[0].SeamKey);
end;

procedure TTestFeatures.TestDartNeedsAPiece;
var
  Made: TDartMade;
  Line: TLineObject;
begin
  Line := FPattern.AddLine(FPattern.AddFreePoint('', '0', '0').Key, FPattern.AddFreePoint('', '300', '0').Key, erOutline);
  FPattern.Evaluate;
  AssertFalse('no piece', Dart(Line.Key, Made));
  AssertTrue(FPattern.LastError, Pos('no piece', FPattern.LastError) > 0);
  AssertFalse('no edge', Dart('', Made));
end;

procedure TTestFeatures.TestDartTooWideIsRefused;
var
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Bodice(Top);
  Spec := DefaultDart(FPattern, Top);
  Spec.Width := '250';
  AssertFalse('wider than the edge', InsertDart(FPattern, Spec, Made));
  AssertTrue(FPattern.LastError, Pos('runs past an end', FPattern.LastError) > 0);
  Spec.Width := '0';
  AssertFalse('no width', InsertDart(FPattern, Spec, Made));
end;

procedure TTestFeatures.TestDartPastAnEndIsRefused;
var
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Bodice(Top);
  Spec := DefaultDart(FPattern, Top);
  Spec.Position := '5';
  AssertFalse('off the start', InsertDart(FPattern, Spec, Made));
  AssertTrue(FPattern.LastError, Pos('runs past an end', FPattern.LastError) > 0);
end;

procedure TTestFeatures.TestDartNeedsADepth;
var
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Bodice(Top);
  Spec := DefaultDart(FPattern, Top);
  Spec.Depth := '0';
  AssertFalse(InsertDart(FPattern, Spec, Made));
  AssertEquals(rsFeatureDartNoDepth, FPattern.LastError);
  Spec.Depth := '-10';
  AssertFalse(InsertDart(FPattern, Spec, Made));
end;

procedure TTestFeatures.TestDartPointOutsideIsRefused;
var
  Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Bodice(Top);
  Spec := DefaultDart(FPattern, Top);
  Spec.Depth := '400';
  AssertFalse('deeper than the piece', InsertDart(FPattern, Spec, Made));
  AssertTrue(FPattern.LastError, Pos('is not inside', FPattern.LastError) > 0);
end;

// A U: the legs to a point in one arm cross the gap's edges
procedure TTestFeatures.TestDartLegsCrossingIsRefused;
var
  Keys: array[0..7] of string;
  Corners: array[0..7] of TVec2;
  Index: integer;
  Path: TPiecePath;
  Reason, Top: string;
  Spec: TDartSpec;
  Made: TDartMade;
begin
  Corners[0] := Vec2(0, 0);
  Corners[1] := Vec2(200, 0);
  Corners[2] := Vec2(200, 300);
  Corners[3] := Vec2(150, 300);
  Corners[4] := Vec2(150, 100);
  Corners[5] := Vec2(50, 100);
  Corners[6] := Vec2(50, 300);
  Corners[7] := Vec2(0, 300);
  for Index := 0 to 7 do
    Keys[Index] := FPattern.AddFreePoint('', FloatToStr(Corners[Index].X), FloatToStr(Corners[Index].Y)).Key;
  Top := FPattern.AddLine(Keys[0], Keys[1], erOutline).Key;
  for Index := 1 to 7 do
    FPattern.AddLine(Keys[Index], Keys[(Index + 1) mod 8], erOutline);
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(25, 200), Path, Reason));
  AssertNotNull(FPattern.LastError, FPattern.AddPiece('', Path, '10'));
  FPattern.Evaluate;
  Spec := DefaultDart(FPattern, Top);
  Spec.ApexKey := FPattern.AddFreePoint('', '25', '200').Key;
  FPattern.Evaluate;
  AssertFalse('across the gap', InsertDart(FPattern, Spec, Made));
  AssertTrue(FPattern.LastError, Pos('would cross', FPattern.LastError) > 0);
end;

procedure TTestFeatures.TestDartInAFoldIsRefused;
var
  Piece: TPieceObject;
  Top: string;
  Made: TDartMade;
begin
  Piece := Bodice(Top);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Top));
  FPattern.Evaluate;
  AssertFalse('a fold', Dart(Top, Made));
  AssertTrue(FPattern.LastError, Pos('fold', FPattern.LastError) > 0);
end;

initialization
  RegisterTest(TTestFeatures);
end.
