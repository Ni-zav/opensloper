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

// The Features tab's buttons and buttonholes along a front opening
unit Sloper.Tests.Buttons;

{$mode ObjFPC}{$H+}

interface

uses
  fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Piece, Sloper.Core.Pattern,
  Sloper.Core.Features;

type
  TTestButtons = class(TOSTestCase)
  private
    FPattern: TPattern;
    // A front 200 wide and 400 long, its centre front down the left side at
    // x = Left, drawn from the top; or, mirrored, down the right side at
    // x = Left + 200, drawn from the bottom
    function Front(Left: double; Mirrored: boolean; const AName: string; out CentreFront: string): TPieceObject;
    function Apply(const Spec: TButtonsSpec; out Made: TButtonsMade): boolean;
    // The piece's marking of the repeat
    function MarkOf(Piece: TPieceObject; const Key: string): TMarkingMark;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFiveButtonsDownTheFront;
    procedure TestButtonsAreMarked;
    procedure TestHorizontalHolesStartPastTheCentreFront;
    procedure TestVerticalHolesAreCentred;
    procedure TestCountFollowsItsVariable;
    procedure TestExtension;
    procedure TestNarrowExtensionIsAProblem;
    procedure TestSeparateFronts;
    procedure TestButtonsAreOneUndoStep;
    procedure TestButtonsAreSaved;
    procedure TestButtonsNeedAPiece;
    procedure TestButtonsNeedRoom;
    procedure TestButtonsNeedACount;
    procedure TestButtonsOnAFoldAreRefused;
  end;

implementation

uses
  SysUtils, Sloper.Core.EvalTypes, Sloper.Core.PieceDetect, Sloper.Core.PatternFile, Sloper.Document.PatternDocument;

procedure TTestButtons.SetUp;
begin
  FPattern := TPattern.Create;
end;

procedure TTestButtons.TearDown;
begin
  FreeAndNil(FPattern);
end;

function TTestButtons.Front(Left: double; Mirrored: boolean; const AName: string; out CentreFront: string): TPieceObject;
var
  TopLeft, TopRight, BottomRight, BottomLeft, Reason: string;
  Path: TPiecePath;

  function Pt(X, Y: double): string;
  begin
    Result := FPattern.AddFreePoint('', FloatToStr(Left + X), FloatToStr(Y)).Key;
  end;

begin
  TopLeft := Pt(0, 0);
  TopRight := Pt(200, 0);
  BottomRight := Pt(200, 400);
  BottomLeft := Pt(0, 400);
  FPattern.AddLine(TopLeft, TopRight, erOutline);
  FPattern.AddLine(BottomRight, BottomLeft, erOutline);
  if Mirrored then
  begin
    CentreFront := FPattern.AddLine(BottomRight, TopRight, erOutline).Key;
    FPattern.AddLine(TopLeft, BottomLeft, erOutline);
  end
  else
  begin
    CentreFront := FPattern.AddLine(TopLeft, BottomLeft, erOutline).Key;
    FPattern.AddLine(TopRight, BottomRight, erOutline);
  end;
  FPattern.Evaluate;
  AssertTrue(Reason, DetectPiecePath(FPattern, Vec2(Left + 100, 200), Path, Reason));
  Result := FPattern.AddPiece(AName, Path, '10');
  AssertNotNull(FPattern.LastError, Result);
  FPattern.Evaluate;
end;

function TTestButtons.Apply(const Spec: TButtonsSpec; out Made: TButtonsMade): boolean;
begin
  Result := InsertButtons(FPattern, Spec, Made);
end;

function TTestButtons.MarkOf(Piece: TPieceObject; const Key: string): TMarkingMark;
var
  Index: integer;
begin
  Index := Piece.PointMarkingOf(Key);
  AssertTrue('marked on ' + Piece.Name, Index >= 0);
  Result := Piece.MarkingMarks[Index];
end;

procedure TTestButtons.TestFiveButtonsDownTheFront;
var
  CentreFront: string;
  Made: TButtonsMade;
begin
  Front(0, False, 'Front', CentreFront);
  AssertTrue(FPattern.LastError, Apply(DefaultButtons(FPattern, CentreFront), Made));
  AssertNear('five to start with', 5, FPattern.FindVariable(BUTTON_COUNT_VARIABLE).Value);
  AssertNear('15 mm buttons', 15, FPattern.FindVariable(BUTTON_SIZE_VARIABLE).Value);
  AssertNear('3 mm thick', 3, FPattern.FindVariable(BUTTON_THICKNESS_VARIABLE).Value);
  AssertPointsNear('20 mm down', Vec2(0, 20), TPointObject(FPattern.FindNode(Made.TopKey)).Position);
  AssertPointsNear('20 mm up', Vec2(0, 380), TPointObject(FPattern.FindNode(Made.BottomKey)).Position);
  AssertEquals(BUTTON_TOP_NAME, TDraftObject(FPattern.FindNode(Made.TopKey)).Name);
  AssertEquals('five holes', 5, TRepeatObject(FPattern.FindNode(Made.HolesKey)).Count);
  AssertPointsNear('evenly spaced', Vec2(0, 110), TRepeatObject(FPattern.FindNode(Made.ButtonsKey)).PositionAt(2));
  AssertEquals('one piece', Made.HolesPieceKey, Made.ButtonsPieceKey);
end;

procedure TTestButtons.TestButtonsAreMarked;
var
  CentreFront: string;
  Made: TButtonsMade;
  Piece: TPieceObject;
  Mark: TMarkingMark;
begin
  Piece := Front(0, False, 'Front', CentreFront);
  AssertTrue(FPattern.LastError, Apply(DefaultButtons(FPattern, CentreFront), Made));
  AssertTrue(Piece.Message, Piece.State = esValid);
  Mark := MarkOf(Piece, Made.ButtonsKey);
  AssertTrue('buttons', Mark.Marker = pmButton);
  AssertEquals(5, Length(Mark.Centres));
  AssertNear('the button''s size', 15, Mark.HoleSize);
  Mark := MarkOf(Piece, Made.HolesKey);
  AssertTrue('buttonholes', Mark.Marker = pmButtonhole);
  AssertNear('the button''s size and thickness', 18, Mark.HoleSize);
end;

// Square to the centre front, from 3 mm past it into the piece
procedure TTestButtons.TestHorizontalHolesStartPastTheCentreFront;
var
  CentreFront: string;
  Made: TButtonsMade;
  Piece: TPieceObject;
  Mark: TMarkingMark;
  Slot: TLine2;
begin
  Piece := Front(0, False, 'Front', CentreFront);
  AssertTrue(FPattern.LastError, Apply(DefaultButtons(FPattern, CentreFront), Made));
  Mark := MarkOf(Piece, Made.HolesKey);
  Slot := ButtonholeSlot(Mark.Centres[0], Mark.HoleSize, Mark.MarkerAngle, Mark.MarkerOffset);
  AssertPointsNear('3 mm past the centre front', Vec2(-3, 20), Slot.P1);
  AssertPointsNear('into the piece', Vec2(15, 20), Slot.P2);
end;

procedure TTestButtons.TestVerticalHolesAreCentred;
var
  CentreFront: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
  Piece: TPieceObject;
  Mark: TMarkingMark;
  Slot: TLine2;
begin
  Piece := Front(0, False, 'Front', CentreFront);
  Spec := DefaultButtons(FPattern, CentreFront);
  Spec.Direction := bdVertical;
  AssertTrue(FPattern.LastError, Apply(Spec, Made));
  Mark := MarkOf(Piece, Made.HolesKey);
  Slot := ButtonholeSlot(Mark.Centres[1], Mark.HoleSize, Mark.MarkerAngle, Mark.MarkerOffset);
  AssertPointsNear('down the centre front', Vec2(0, 101), Slot.P1);
  AssertPointsNear('centred on the button', Vec2(0, 119), Slot.P2);
end;

procedure TTestButtons.TestCountFollowsItsVariable;
var
  CentreFront: string;
  Made: TButtonsMade;
  Piece: TPieceObject;
begin
  Piece := Front(0, False, 'Front', CentreFront);
  AssertTrue(FPattern.LastError, Apply(DefaultButtons(FPattern, CentreFront), Made));
  AssertTrue(FPattern.LastError, FPattern.SetFormula(FPattern.FindVariable(BUTTON_COUNT_VARIABLE), 'formula', '7'));
  FPattern.Evaluate;
  AssertEquals('seven holes', 7, Length(MarkOf(Piece, Made.HolesKey).Centres));
  AssertEquals('seven buttons', 7, Length(MarkOf(Piece, Made.ButtonsKey).Centres));
  AssertPointsNear('spaced again', Vec2(0, 80), MarkOf(Piece, Made.ButtonsKey).Centres[1]);
end;

procedure TTestButtons.TestExtension;
var
  CentreFront: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
  Piece: TPieceObject;
  Edge: TEdgeObject;
begin
  Piece := Front(0, False, 'Front', CentreFront);
  Spec := DefaultButtons(FPattern, CentreFront);
  Spec.Extension := '#' + BUTTON_SIZE_VARIABLE;
  AssertTrue(FPattern.LastError, Apply(Spec, Made));
  AssertTrue(Piece.Message, Piece.State = esValid);
  AssertEquals('two lines out and the extension', 3, Length(Made.ExtensionKeys));
  AssertEquals('the centre front is no longer the outline', -1, Piece.PathIndexOf(CentreFront));
  AssertEquals('they take its place', 6, Length(Piece.Path));
  AssertNear('15 mm wider', 200 * 400 + 15 * 400, Piece.Area, 0.01);
  Edge := TEdgeObject(FPattern.FindNode(CentreFront));
  AssertTrue('a placement line', Edge.Role = erPlacement);
  AssertTrue('marked on the piece', Piece.LineMarkingOf(CentreFront) >= 0);
  AssertPointsNear('the buttons stay on it', Vec2(0, 20), MarkOf(Piece, Made.ButtonsKey).Centres[0]);
  AssertEquals('no problem', 0, Length(Made.Problems));
end;

procedure TTestButtons.TestNarrowExtensionIsAProblem;
var
  CentreFront: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
begin
  Front(0, False, 'Front', CentreFront);
  Spec := DefaultButtons(FPattern, CentreFront);
  Spec.Extension := '5';
  AssertTrue(FPattern.LastError, Apply(Spec, Made));
  AssertEquals('made, but worth a look', 1, Length(Made.Problems));
end;

// The right front runs the other way; its buttons still line up with the
// holes, and each lies only on its own piece
procedure TTestButtons.TestSeparateFronts;
var
  LeftFront, RightFront: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
  Left, Right: TPieceObject;
  Mark: TMarkingMark;
begin
  Left := Front(0, False, 'Left', LeftFront);
  Right := Front(300, True, 'Right', RightFront);
  Spec := DefaultButtons(FPattern, LeftFront);
  Spec.ButtonsEdgeKey := RightFront;
  Spec.Extension := '15';
  AssertTrue(FPattern.LastError, Apply(Spec, Made));
  AssertTrue(Left.Message, Left.State = esValid);
  AssertTrue(Right.Message, Right.State = esValid);
  AssertEquals('holes on the left', Left.Key, Made.HolesPieceKey);
  AssertEquals('buttons on the right', Right.Key, Made.ButtonsPieceKey);
  AssertEquals('no buttons on the left', -1, Left.PointMarkingOf(Made.ButtonsKey));
  AssertEquals('no holes on the right', -1, Right.PointMarkingOf(Made.HolesKey));
  Mark := MarkOf(Right, Made.ButtonsKey);
  AssertPointsNear('the top button level with the top hole', Vec2(500, 20), Mark.Centres[0]);
  AssertEquals('both fronts extended', 6, Length(Made.ExtensionKeys));
  AssertNear('the right front too', 200 * 400 + 15 * 400, Right.Area, 0.01);
end;

procedure TTestButtons.TestButtonsAreOneUndoStep;
var
  Document: TPatternDocument;
  Pattern: TPattern;
  CentreFront, Before: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
begin
  Document := TPatternDocument.Create;
  try
    Pattern := FPattern;
    FPattern := Document.Pattern;
    try
      Document.BeginChange('Front');
      Front(0, False, 'Front', CentreFront);
      Document.EndChange;
      Before := SavePatternToText(Document.Pattern, False);
      Spec := DefaultButtons(Document.Pattern, CentreFront);
      Spec.Extension := '15';
      Document.BeginChange(rsFeatureButtons);
      AssertTrue(Document.Pattern.LastError, Apply(Spec, Made));
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

procedure TTestButtons.TestButtonsAreSaved;
var
  CentreFront, Text, Error: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
  Loaded: TPattern;
  Piece: TPieceObject;
begin
  Front(0, False, 'Front', CentreFront);
  Spec := DefaultButtons(FPattern, CentreFront);
  Spec.Extension := '15';
  AssertTrue(FPattern.LastError, Apply(Spec, Made));
  Text := SavePatternToText(FPattern);
  Loaded := TPattern.Create;
  try
    AssertTrue(Error, LoadPatternFromText(Loaded, Text, Error));
    Loaded.Evaluate;
    Piece := TPieceObject(Loaded.FindObject('Front'));
    AssertTrue(Piece.Message, Piece.State = esValid);
    AssertEquals('holes and buttons and the centre front', 3, Length(Piece.MarkingMarks));
    AssertEquals('saved as it was', Text, SavePatternToText(Loaded));
  finally
    FreeAndNil(Loaded);
  end;
end;

procedure TTestButtons.TestButtonsNeedAPiece;
var
  Loose: string;
  Made: TButtonsMade;
begin
  Loose := FPattern.AddLine(FPattern.AddFreePoint('', '0', '0').Key, FPattern.AddFreePoint('', '0', '300').Key, erOutline).Key;
  AssertFalse('a loose line', Apply(DefaultButtons(FPattern, Loose), Made));
  AssertTrue(FPattern.LastError, Pos('no piece', FPattern.LastError) > 0);
  AssertFalse('no edge', Apply(DefaultButtons(FPattern, ''), Made));
end;

procedure TTestButtons.TestButtonsNeedRoom;
var
  CentreFront: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
begin
  Front(0, False, 'Front', CentreFront);
  Spec := DefaultButtons(FPattern, CentreFront);
  Spec.First := '250';
  Spec.Last := '150';
  AssertFalse('no room', Apply(Spec, Made));
  AssertTrue(FPattern.LastError, Pos('no room', FPattern.LastError) > 0);
end;

procedure TTestButtons.TestButtonsNeedACount;
var
  CentreFront: string;
  Spec: TButtonsSpec;
  Made: TButtonsMade;
begin
  Front(0, False, 'Front', CentreFront);
  Spec := DefaultButtons(FPattern, CentreFront);
  Spec.Count := '0';
  AssertFalse('none', Apply(Spec, Made));
  AssertTrue(FPattern.LastError, Pos('at least one', FPattern.LastError) > 0);
end;

procedure TTestButtons.TestButtonsOnAFoldAreRefused;
var
  CentreFront: string;
  Piece: TPieceObject;
  Made: TButtonsMade;
begin
  Piece := Front(0, False, 'Front', CentreFront);
  AssertTrue(FPattern.LastError, FPattern.SetFoldEdge(Piece, CentreFront));
  FPattern.Evaluate;
  AssertFalse('a fold', Apply(DefaultButtons(FPattern, CentreFront), Made));
  AssertTrue(FPattern.LastError, Pos('fold', FPattern.LastError) > 0);
end;

initialization
  RegisterTest(TTestButtons);
end.
