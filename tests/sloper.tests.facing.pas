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

// The Features tab's facing: a neckline or armhole faced in one step
unit Sloper.Tests.Facing;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern,
  Sloper.Core.Features;

type
  // The edges of a simple bodice front, or of its back, its mirror image
  TBodiceEdges = record
    Neck, CentreFront, Waist, Side, Armhole, Shoulder: string;
  end;

  TTestFacing = class(TOSTestCase)
  private
    FPattern: TPattern;
    // A front with its centre front at x = Left, or a back mirrored to its
    // right with its centre back at x = Left: the neck curving from the
    // shoulder at (Left ± 70, 0) to the centre at (Left, 80), square to it
    function Bodice(Left: double; Back: boolean; const AName: string; out Edges: TBodiceEdges): TPieceObject;
    function Face(const EdgeKeys: array of string; out Made: TFacingMade): boolean;
    function Facing(const Made: TFacingMade; Index: integer = 0): TPieceObject;
    function Inner(const Made: TFacingMade; Index: integer = 0): TEdgeObject;
    // A front and a back seamed at the shoulder
    procedure FrontAndBack(out Front, Back: TBodiceEdges);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNeckFacing;
    procedure TestFacingMeetsTheEdgesBeside;
    procedure TestFacingLeavesThePieceAsItWas;
    procedure TestFacingIsCutAsThePiece;
    procedure TestFacingIsSeamedToThePiece;
    procedure TestFacingOnTheFold;
    procedure TestFacingsJoinAtTheShoulder;
    procedure TestFacingsShareTheirWidth;
    procedure TestArmholeFacing;
    procedure TestFacingTakesTheNotches;
    procedure TestFacingMovedAside;
    procedure TestInterfacing;
    procedure TestFacingIsOneUndoStep;
    procedure TestFacingIsSaved;
    procedure TestFacingNeedsAPiece;
    procedure TestFacingAllRoundIsRefused;
    procedure TestFacingTooWideIsRefused;
    procedure TestFacingOnAFoldIsRefused;
    // Behind a button extension: the step out to it at the neck is left out
    // of the inner edge, which runs down to the waist past the step back in
    procedure TestFacingBehindButtons;
  end;

implementation

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.PieceDetect, Sloper.Core.Seam, Sloper.Core.Materials, Sloper.Core.Transform,
  Sloper.Core.PatternFile, Sloper.Core.PatternCheck, Sloper.Document.PatternDocument;

procedure TTestFacing.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestFacing.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestFacing.Bodice(Left: double; Back: boolean; const AName: string; out Edges: TBodiceEdges): TPieceObject;
var
  Across: double;
  ShoulderNeck, CentreNeck, CentreWaist, SideWaist, Underarm, ShoulderEnd, Reason: string;
  Path: TPiecePath;

  function Pt(X, Y: double): string;
  begin
    Result := FPattern.AddFreePoint('', FloatToStr(Left + Across * X), FloatToStr(Y)).Key;
  end;

begin
  Across := 1;
  if Back then
    Across := -1;
  ShoulderNeck := Pt(70, 0);
  CentreNeck := Pt(0, 80);
  CentreWaist := Pt(0, 300);
  SideWaist := Pt(200, 300);
  Underarm := Pt(200, 150);
  ShoulderEnd := Pt(180, 30);
  // Leaving the shoulder straight down, and reaching the centre square to it
  Edges.Neck := FPattern.AddCurve(ShoulderNeck, CentreNeck, '270', '50', FloatToStr(90 - 90 * Across), '40', erOutline).Key;
  Edges.CentreFront := FPattern.AddLine(CentreNeck, CentreWaist, erOutline).Key;
  Edges.Waist := FPattern.AddLine(CentreWaist, SideWaist, erOutline).Key;
  Edges.Side := FPattern.AddLine(SideWaist, Underarm, erOutline).Key;
  Edges.Armhole := FPattern.AddCurve(Underarm, ShoulderEnd, FloatToStr(90 + 90 * Across), '40', '270', '60', erOutline).Key;
  Edges.Shoulder := FPattern.AddLine(ShoulderEnd, ShoulderNeck, erOutline).Key;
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + Across * 100, 200), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
  AssertTrue(Result.Message, Result.State = esValid);
end;

function TTestFacing.Face(const EdgeKeys: array of string; out Made: TFacingMade): boolean;
begin
  Result := InsertFacing(FPattern, DefaultFacing(FPattern, EdgeKeys), Made);
end;

function TTestFacing.Facing(const Made: TFacingMade; Index: integer): TPieceObject;
begin
  Result := TPieceObject(FPattern.FindNode(Made.FacingKeys[Index]));
end;

function TTestFacing.Inner(const Made: TFacingMade; Index: integer): TEdgeObject;
begin
  Result := TEdgeObject(FPattern.FindNode(Made.InnerKeys[Index]));
end;

procedure TTestFacing.FrontAndBack(out Front, Back: TBodiceEdges);
var
  FrontPiece, BackPiece: TPieceObject;
  SideA, SideB: TSeamSide;
begin
  FrontPiece := Bodice(0, False, 'Front', Front);
  BackPiece := Bodice(500, True, 'Back', Back);
  SideA := nil;
  SideB := nil;
  SetLength(SideA, 1);
  SetLength(SideB, 1);
  SideA[0].PieceKey := FrontPiece.Key;
  SideA[0].EdgeKey := Front.Shoulder;
  SideB[0].PieceKey := BackPiece.Key;
  SideB[0].EdgeKey := Back.Shoulder;
  AssertNotNull(FPattern.LastError, FPattern.AddSeam('Shoulder_seam', SideA, SideB));
end;

procedure TTestFacing.TestNeckFacing;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
begin
  Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  AssertEquals('one facing', 1, Length(Made.FacingKeys));
  Piece := Facing(Made);
  AssertEquals('named for the piece', FACING_PREFIX + 'Front', Piece.Name);
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('the neck, two parts and the inner edge', 4, Length(Piece.Path));
  AssertTrue('round the neck', Piece.PathIndexOf(Edges.Neck) >= 0);
  AssertTrue('inside the inner edge', Piece.PathIndexOf(Made.InnerKeys[0]) >= 0);
  AssertNotNull('its width is a variable', FPattern.FindVariable(FACING_WIDTH_VARIABLE));
  AssertNear('60 mm to start with', 60, FPattern.FindVariable(FACING_WIDTH_VARIABLE).Value);
  AssertTrue('an outline', Inner(Made).Role = erOutline);
  AssertEquals('no interfacing', '', Made.InterfacingKeys[0]);
end;

// The neck meets the centre front square, so the inner edge reaches it 60 mm
// down; it meets the shoulder at a slant, so it is trimmed to it there
procedure TTestFacing.TestFacingMeetsTheEdgesBeside;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Shoulder: TEdgeObject;
  Ends: array[0..1] of TVec2;
  Position, Offset: double;
  OnCentre: integer;
begin
  Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  Ends[0] := Inner(Made).PointAtLength(0);
  Ends[1] := Inner(Made).PointAtLength(Inner(Made).Length);
  OnCentre := 0;
  if Ends[1].X < Ends[0].X then
    OnCentre := 1;
  AssertPointsNear('60 mm down the centre front', Vec2(0, 140), Ends[OnCentre]);
  Shoulder := TEdgeObject(FPattern.FindNode(Edges.Shoulder));
  Shoulder.Locate(Ends[1 - OnCentre], Position, Offset);
  AssertTrue('on the shoulder', Offset < 0.001);
end;

procedure TTestFacing.TestFacingLeavesThePieceAsItWas;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
  Area: double;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  Area := Piece.Area;
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertNear('the same shape', Area, Piece.Area, 0.01);
  AssertEquals('the shoulder and centre front split', 8, Length(Piece.Path));
  AssertTrue('the facing is smaller', Facing(Made).Area < Area / 2);
end;

procedure TTestFacing.TestFacingIsCutAsThePiece;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
  Lining: TPatternMaterial;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  Lining := FPattern.AddMaterial('Wool');
  FPattern.SetPieceMaterial(Piece, Lining);
  AssertTrue(FPattern.SetCut(Piece, 2, True));
  AssertTrue(FPattern.SetGrainAngle(Piece, '80'));
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  AssertTrue('the same material', FPattern.MaterialOf(Facing(Made)) = Lining);
  AssertEquals('cut twice', 2, Facing(Made).CutCount);
  AssertTrue('mirrored', Facing(Made).Mirrored);
  AssertEquals('on the same grain', '80', FPattern.FormulaText(Facing(Made), GRAIN_ANGLE_FIELD));
end;

procedure TTestFacing.TestFacingIsSeamedToThePiece;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
  Seam: TSeamObject;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  AssertEquals('one seam', 1, Length(Made.SeamKeys));
  Seam := TSeamObject(FPattern.FindNode(Made.SeamKeys[0]));
  AssertEquals('the piece', Piece.Key, Seam.SideA[0].PieceKey);
  AssertEquals('its neck', Edges.Neck, Seam.SideA[0].EdgeKey);
  AssertEquals('the facing', Made.FacingKeys[0], Seam.SideB[0].PieceKey);
  AssertEquals('the same neck', Edges.Neck, Seam.SideB[0].EdgeKey);
  AssertTrue(Seam.Message, Seam.State = esValid);
  AssertFalse('they match', Seam.OutOfTolerance);
end;

procedure TTestFacing.TestFacingOnTheFold;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
  Fold: TEdgeObject;
  Blocked: integer;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Edges.CentreFront));
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  AssertTrue('the facing is cut on the fold', Facing(Made).FoldEdgeKey <> '');
  Fold := TEdgeObject(FPattern.FindNode(Facing(Made).FoldEdgeKey));
  AssertNear('along the centre front', 0, Fold.PointAtLength(0).X);
  AssertNear('the facing''s width of it', 60, Fold.Length);
  AssertEquals('the piece keeps its fold', Edges.CentreFront, Piece.FoldEdgeKey);
  AssertEquals('nothing outside the pieces', 0, Length(PatternProblems(FPattern, Blocked)));
  AssertTrue(Facing(Made).Message, Facing(Made).State = esValid);
end;

procedure TTestFacing.TestFacingsJoinAtTheShoulder;
var
  Front, Back: TBodiceEdges;
  Made: TFacingMade;
  Join: TSeamObject;
begin
  FrontAndBack(Front, Back);
  AssertTrue(FPattern.LastError, Face([Front.Neck, Back.Neck], Made));
  AssertEquals('two facings', 2, Length(Made.FacingKeys));
  AssertEquals('Facing_Front', Facing(Made, 0).Name);
  AssertEquals('Facing_Back', Facing(Made, 1).Name);
  AssertEquals('joined at the shoulder', 1, Length(Made.JoinKeys));
  Join := TSeamObject(FPattern.FindNode(Made.JoinKeys[0]));
  AssertEquals('the front facing', Made.FacingKeys[0], Join.SideA[0].PieceKey);
  AssertEquals('the back facing', Made.FacingKeys[1], Join.SideB[0].PieceKey);
  AssertTrue(Join.Message, Join.State = esValid);
  AssertFalse('the shoulders match', Join.OutOfTolerance);
end;

// How far down the inner edge meets the centre line at X
function CentreDepth(Edge: TEdgeObject; X: double): double;
var
  First, Last: TVec2;
begin
  First := Edge.PointAtLength(0);
  Last := Edge.PointAtLength(Edge.Length);
  if Abs(First.X - X) < Abs(Last.X - X) then
    Result := First.Y
  else
    Result := Last.Y;
end;

procedure TTestFacing.TestFacingsShareTheirWidth;
var
  Front, Back: TBodiceEdges;
  FrontMade, BackMade: TFacingMade;
begin
  FrontAndBack(Front, Back);
  AssertTrue(FPattern.LastError, Face([Front.Neck], FrontMade));
  AssertTrue(FPattern.LastError, Face([Back.Neck], BackMade));
  AssertEquals('one variable', 1, FPattern.VariableCount);
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindVariable(FACING_WIDTH_VARIABLE), 'formula', '40'));
  FPattern.Evaluate;
  AssertNear('the front narrower', 120, CentreDepth(Inner(FrontMade), 0));
  AssertNear('the back narrower', 120, CentreDepth(Inner(BackMade), 500));
  AssertTrue(Facing(FrontMade).Message, Facing(FrontMade).State = esValid);
  AssertTrue(Facing(BackMade).Message, Facing(BackMade).State = esValid);
end;

procedure TTestFacing.TestArmholeFacing;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, Face([Edges.Armhole], Made));
  AssertTrue(Facing(Made).Message, Facing(Made).State = esValid);
  AssertTrue('round the armhole', Facing(Made).PathIndexOf(Edges.Armhole) >= 0);
  AssertTrue('a curve inside', not Inner(Made).IsStraight);
  AssertTrue(Piece.Message, Piece.State = esValid);
end;

procedure TTestFacing.TestFacingTakesTheNotches;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Piece: TPieceObject;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.AddEdgeNotch(Piece, Edges.Neck, '30'));
  AssertTrue(FPattern.AddEdgeNotch(Piece, Edges.Waist, '30'));
  FPattern.Evaluate;
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  AssertEquals('the neck''s notch only', 1, Length(Facing(Made).Notches));
  AssertEquals('on the neck', Edges.Neck, Facing(Made).Notches[0].EdgeKey);
  AssertEquals('as far along', '30', FPattern.FormulaText(Facing(Made), Facing(Made).NotchField(0)));
end;

procedure TTestFacing.TestFacingMovedAside;
var
  Edges: TBodiceEdges;
  Spec: TFacingSpec;
  Made: TFacingMade;
  Piece: TPieceObject;
  Point: TVec2;
  Right, Left: double;
  Seam: TSeamObject;
  Blocked: integer;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.AddEdgeNotch(Piece, Edges.Neck, '30'));
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Edges.CentreFront));
  FPattern.Evaluate;
  Spec := DefaultFacing(FPattern, [Edges.Neck]);
  Spec.Aside := True;
  AssertTrue(FPattern.LastError, InsertFacing(FPattern, Spec, Made));
  AssertTrue(Facing(Made).Message, Facing(Made).State = esValid);
  Right := -1e9;
  for Point in Piece.CutLine do
    if Point.X > Right then
      Right := Point.X;
  Left := 1e9;
  for Point in Facing(Made).CutLine do
    if Point.X < Left then
      Left := Point.X;
  AssertTrue('beside the piece', Left > Right);
  AssertEquals('not on the neck itself', -1, Facing(Made).PathIndexOf(Edges.Neck));
  AssertTrue('its inner edge is a copy', FPattern.FindNode(Made.InnerKeys[0]) is TEdgeCopy);
  AssertEquals('the notch too', 1, Length(Facing(Made).Notches));
  Seam := TSeamObject(FPattern.FindNode(Made.SeamKeys[0]));
  AssertFalse('still seamed to the neck', Seam.OutOfTolerance);
  AssertTrue('on the fold', Facing(Made).FoldEdgeKey <> '');
  AssertEquals('nothing outside the pieces', 0, Length(PatternProblems(FPattern, Blocked)));
end;

procedure TTestFacing.TestInterfacing;
var
  Edges: TBodiceEdges;
  Spec: TFacingSpec;
  Made: TFacingMade;
  Interfacing: TPieceObject;
begin
  Bodice(0, False, 'Front', Edges);
  Spec := DefaultFacing(FPattern, [Edges.Neck]);
  Spec.Interfacing := 'Interfacing';
  AssertTrue(FPattern.LastError, InsertFacing(FPattern, Spec, Made));
  Interfacing := TPieceObject(FPattern.FindNode(Made.InterfacingKeys[0]));
  AssertNotNull('an interfacing', Interfacing);
  AssertEquals(INTERFACING_PREFIX + 'Front', Interfacing.Name);
  AssertNotNull('the material is added', FPattern.FindMaterialNamed('Interfacing'));
  AssertTrue('on it', FPattern.MaterialOf(Interfacing) = FPattern.FindMaterialNamed('Interfacing'));
  AssertTrue('not the facing', FPattern.MaterialOf(Facing(Made)) <> FPattern.MaterialOf(Interfacing));
  AssertNear('the facing''s shape', Facing(Made).Area, Interfacing.Area, 0.01);
end;

procedure TTestFacing.TestFacingIsOneUndoStep;
var
  Document: TPatternDocument;
  Pattern: TPattern;
  Edges: TBodiceEdges;
  Before: string;
  Made: TFacingMade;
begin
  Document := TPatternDocument.Create;
  try
    Pattern := FPattern;
    FPattern := Document.Pattern;
    try
      Document.BeginChange('Bodice');
      Bodice(0, False, 'Front', Edges);
      Document.EndChange;
      Before := SavePatternToText(Document.Pattern, False);
      Document.BeginChange(rsFeatureFacing);
      AssertTrue(Document.Pattern.LastError, Face([Edges.Neck], Made));
      Document.EndChange;
      AssertFalse('refused', Document.ChangeRefused);
      AssertTrue('changed', Before <> SavePatternToText(Document.Pattern, False));
      Document.Undo;
      AssertEquals('all of it gone', Before, SavePatternToText(Document.Pattern, False));
    finally
      FPattern := Pattern;
    end;
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestFacing.TestFacingIsSaved;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
  Text, Error: string;
  Loaded: TPattern;
  Piece: TPieceObject;
begin
  Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, Face([Edges.Neck], Made));
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(Error, LoadPatternFromText(Loaded, Text, Error));
    Loaded.Evaluate;
    Piece := TPieceObject(Loaded.FindObject(FACING_PREFIX + 'Front'));
    AssertTrue(Piece.Message, Piece.State = esValid);
    AssertNear('the same facing', Facing(Made).Area, Piece.Area, 0.01);
    AssertEquals('saved as it was', Text, SavePatternToText(Loaded));
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestFacing.TestFacingNeedsAPiece;
var
  Loose: string;
  Made: TFacingMade;
begin
  Loose := FPattern.AddLine(FPattern.AddFreePoint('', '0', '0').Key, FPattern.AddFreePoint('', '50', '0').Key, erOutline).Key;
  AssertFalse('a loose line', Face([Loose], Made));
  AssertTrue(FPattern.LastError, Pos('no piece', FPattern.LastError) > 0);
  AssertFalse('no edge', Face([], Made));
end;

procedure TTestFacing.TestFacingAllRoundIsRefused;
var
  Edges: TBodiceEdges;
  Made: TFacingMade;
begin
  Bodice(0, False, 'Front', Edges);
  AssertFalse('all round', Face([Edges.Neck, Edges.CentreFront, Edges.Waist, Edges.Side, Edges.Armhole, Edges.Shoulder], Made));
  AssertTrue(FPattern.LastError, Pos('lining', FPattern.LastError) > 0);
  AssertEquals('nothing added', 0, FPattern.VariableCount);
end;

procedure TTestFacing.TestFacingTooWideIsRefused;
var
  Edges: TBodiceEdges;
  Spec: TFacingSpec;
  Made: TFacingMade;
begin
  Bodice(0, False, 'Front', Edges);
  Spec := DefaultFacing(FPattern, [Edges.Neck]);
  // Wider than the bodice: nothing beside the neck is short enough to take
  // whole, nor does the inner edge meet anything
  Spec.Width := '400';
  AssertFalse('wider than the bodice', InsertFacing(FPattern, Spec, Made));
  AssertTrue(FPattern.LastError, Pos('wider than Front', FPattern.LastError) > 0);
end;

procedure TTestFacing.TestFacingOnAFoldIsRefused;
var
  Edges: TBodiceEdges;
  Piece: TPieceObject;
  Made: TFacingMade;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, Edges.CentreFront));
  FPattern.Evaluate;
  AssertFalse('a fold', Face([Edges.Neck, Edges.CentreFront], Made));
  AssertTrue(FPattern.LastError, Pos('fold', FPattern.LastError) > 0);
end;

procedure TTestFacing.TestFacingBehindButtons;
var
  Edges: TBodiceEdges;
  Piece: TPieceObject;
  Buttons: TButtonsSpec;
  ButtonsMade: TButtonsMade;
  Made: TFacingMade;
  Key, Step, StepBack: string;
  Edge: TEdgeObject;
  Waist: TEdgeObject;
  Position, Offset: double;
begin
  Piece := Bodice(0, False, 'Front', Edges);
  Buttons := DefaultButtons(FPattern, Edges.CentreFront);
  Buttons.Extension := '15';
  AssertTrue(FPattern.LastError, InsertButtons(FPattern, Buttons, ButtonsMade));
  // The step out at the neck, and the one back in at the waist
  Step := '';
  StepBack := '';
  for Key in ButtonsMade.ExtensionKeys do
  begin
    Edge := TEdgeObject(FPattern.FindNode(Key));
    if not Edge.IsStraight or (Edge.Length > 20) then
      Continue;
    if PointsNear(Edge.PointAtLength(0), Vec2(0, 80)) or PointsNear(Edge.PointAtLength(Edge.Length), Vec2(0, 80)) then
      Step := Key
    else
      StepBack := Key;
  end;
  AssertTrue('the step out', Step <> '');
  AssertTrue(FPattern.LastError, Face([Edges.Neck, Step, ButtonsMade.ExtensionKeys[1]], Made));
  AssertTrue(Facing(Made).Message, Facing(Made).State = esValid);
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertTrue('takes the step back in whole', Facing(Made).PathIndexOf(StepBack) >= 0);
  Waist := TEdgeObject(FPattern.FindNode(Edges.Waist));
  // The path runs up the extension, so the inner edge starts at the waist
  Waist.Locate(Inner(Made).PointAtLength(0), Position, Offset);
  AssertTrue('the inner edge starts on the waist', Offset < 0.001);
  AssertNear('60 mm in from the extension', 45, Inner(Made).PointAtLength(0).X);
end;

initialization
  RegisterTest(TTestFacing);
end.
