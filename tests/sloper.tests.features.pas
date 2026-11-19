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

// Features applied in one step: a zip in a piece's edge
unit Sloper.Tests.Features;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern,
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
  end;

implementation

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.EvalTypes, Sloper.Core.PieceDetect, Sloper.Core.Units;

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

initialization
  RegisterTest(TTestFeatures);
end.
