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

// What the canvas tools' clicks make, each as one undo step: a point, a line
// or curve between two snaps (making their points), a curve carried on, a
// circle or rectangle, a piece of the region clicked, a notch added or
// removed, a seam between the edges picked, a note or a callout. The desktop's tools (Sloper.UI.CanvasTools) and the web editor's,
// through the editor methods, both call these, so a click does the same
// everywhere. Kept free of the LCL.
unit Sloper.Editor.ToolEdits;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Draft, Sloper.Core.Pattern, Sloper.Core.Seam, Sloper.Document.PatternDocument,
  Sloper.Core.Note, Sloper.Editor.Snap, Sloper.Editor.SelectionEdits;

const
  // A line or curve shorter than this (mm) is ignored
  MIN_EDGE_LENGTH = 0.05;

// The point the snap makes, or the existing one it is on, which is selected
// without a change
function AddPointFromSnap(Document: TPatternDocument; const Snap: TSnap): TSelectionEdit;
// A line or curve from Start to Finish, making their points as needed; a curve
// leaves its ends along the chord, its handles a third of it. EndKey is the
// point it ends at, where the next one goes from. Not Done and no message when
// it would be too short to see.
function AddEdgeFromSnaps(Document: TPatternDocument; const Start, Finish: TSnap; Curve: boolean; Role: TEdgeRole;
  out EndKey: string): TSelectionEdit;
// Carries the curve or curve path CurveKey on through where Finish snaps, as one
// path; Start is where it ends now. A curve gone, as after undo, gives a new
// one in Role instead. EndKey as for AddEdgeFromSnaps.
function ExtendCurveToSnap(Document: TPatternDocument; const CurveKey: string; const Start, Finish: TSnap; Role: TEdgeRole;
  out EndKey: string): TSelectionEdit;
// A circle about the snapped centre through Opposite, or a rectangle from the
// snapped corner to Opposite
function AddShapeFromSnap(Document: TPatternDocument; const Start: TSnap; const Opposite: TVec2; Circle: boolean;
  Role: TEdgeRole): TSelectionEdit;
// A piece of the closed outline around At, with the default allowance; a
// region that already has one selects it instead
function AddPieceAt(Document: TPatternDocument; const At: TVec2): TSelectionEdit;
// Removes the notches within Radius mm of At; with none there, adds one on
// every piece whose seam line passes there
function ToggleNotchAt(Document: TPatternDocument; const At: TVec2; Radius: double): TSelectionEdit;
// What a circle's or rectangle's second click would make, for the status bar
function ShapeSizeText(Pattern: TPattern; const Start, Finish: TVec2; Circle: boolean): string;
// The Seam tool's click: the piece's edge within Radius mm of At goes on the
// side, or comes off it when it is there already. False, with the reason in
// Message, when there is none there or it is the piece's fold; otherwise
// Message is the tool's progress.
function PickSeamEntry(Pattern: TPattern; const At: TVec2; Radius: double; var SideA, SideB: TSeamSide; OnB: boolean;
  out Message: string): boolean;
// Which side is being picked, both sides' lengths and their difference
function SeamProgressText(Pattern: TPattern; const SideA, SideB: TSeamSide; OnB: boolean): string;
// The seam between the sides picked; refused while either is empty
function AddSeamFromSides(Document: TPatternDocument; const SideA, SideB: TSeamSide): TSelectionEdit;
// A note saying "Text", hung from where the Text tool's click at Click snapped
function AddNoteFromSnap(Document: TPatternDocument; const Snap: TSnap; const Click: TVec2): TSelectionEdit;
// Why the Callout tool's first click at Click cannot be its tip, as when it
// is on nothing; '' when it can
function CalloutStartRefusal(Pattern: TPattern; const Tip: TSnap; const TipClick: TVec2): string;
// A callout pointing where its first click snapped, its text at BoxAt
function AddCalloutFromSnap(Document: TPatternDocument; const Tip: TSnap; const TipClick, BoxAt: TVec2): TSelectionEdit;
// Hangs a callout from where its dragged tip was dropped (at TipClick,
// snapped to Tip), its text staying where it is, as one undo step
function MoveCalloutTip(Document: TPatternDocument; Note: TNoteObject; const Tip: TSnap; const TipClick: TVec2): TSelectionEdit;

resourcestring
  rsToolAddLine = 'Add line';
  rsToolAddCurve = 'Add curve';
  rsToolExtendCurve = 'Carry curve on';
  rsToolAddRound = 'Add circle or arc';
  rsToolAddRectangle = 'Add rectangle';
  rsToolCircleRim = 'Click a point on the rim';
  rsToolRadius = 'Radius %s';
  rsToolRectangleCorner = 'Click the opposite corner';
  rsToolRectangleSize = '%s by %s';
  rsToolAddPiece = 'Add piece';
  rsToolPieceExists = '%s already covers this region';
  rsToolAddNotch = 'Add notch';
  rsToolRemoveNotch = 'Remove notch';
  rsToolNoSeam = 'There is no piece''s edge here';
  rsToolSeamProgress = 'Side %s: A %s, B %s, difference %s. Tab changes side, Enter makes the seam';
  rsToolSeamSides = 'Pick edges for both sides first';
  rsToolAddSeam = 'Add seam';
  rsToolAddNote = 'Add note';
  rsToolNewNoteText = 'Text';
  rsToolCalloutBox = 'Click where the callout''s text goes';
  rsToolAddCallout = 'Add callout';
  rsToolMoveTip = 'Move callout tip';

implementation

uses
  Sloper.Core.Evaluator, Sloper.Core.Units, Sloper.Core.Drag, Sloper.Core.Piece, Sloper.Core.PieceDetect,
  Sloper.Editor.Scene, Sloper.Editor.Tools;

const
  // Curve handles start this fraction of the way along the chord
  HANDLE_FRACTION = 1 / 3;
  SEAM_SIDE_NAMES: array[boolean] of string = ('A', 'B');

// Done, selecting Keys
function Made(const Keys: array of string): TSelectionEdit;
var
  Key: string;
begin
  Result := Default(TSelectionEdit);
  Result.Done := True;
  Result.Reselect := True;
  for Key in Keys do
    Insert(Key, Result.Selection, Length(Result.Selection));
end;

// Refused, saying why
function Refused(const Reason: string): TSelectionEdit;
begin
  Result := Default(TSelectionEdit);
  Result.Message := Reason;
end;

// Ends the change: Made, selecting Keys, when Done, else undone and Refused
// with the pattern's reason
function Committed(Document: TPatternDocument; Done: boolean; const Keys: array of string): TSelectionEdit;
var
  Reason: string;
begin
  Reason := Document.Pattern.LastError;
  if Document.Commit(Done) then
    Result := Made(Keys)
  else
    Result := Refused(Reason);
end;

function AddPointFromSnap(Document: TPatternDocument; const Snap: TSnap): TSelectionEdit;
var
  Key: string;
begin
  if Snap.Kind = snPoint then
  begin
    Result := Made([Snap.PointKey]);
    Result.Done := False;
    Exit;
  end;
  Document.BeginChange(rsToolAddPoint);
  Key := PointFromSnap(Document.Pattern, Snap);
  Result := Committed(Document, Key <> '', [Key]);
end;

function AddEdgeFromSnaps(Document: TPatternDocument; const Start, Finish: TSnap; Curve: boolean; Role: TEdgeRole;
  out EndKey: string): TSelectionEdit;
var
  Pattern: TPattern;
  StartKey, Description, Handle: string;
  Chord: double;
  Edge: TEdgeObject;
begin
  EndKey := '';
  Chord := Distance(Start.Position, Finish.Position);
  if Chord < MIN_EDGE_LENGTH then
    Exit(Default(TSelectionEdit));
  if Curve then
    Description := rsToolAddCurve
  else
    Description := rsToolAddLine;
  Pattern := Document.Pattern;
  Document.BeginChange(Description);
  Edge := nil;
  StartKey := PointFromSnap(Pattern, Start);
  if StartKey <> '' then
    EndKey := PointFromSnap(Pattern, Finish);
  if (EndKey <> '') and (EndKey <> StartKey) then
    if Curve then
    begin
      Handle := RoundLengthFormulaText(Chord * HANDLE_FRACTION, Pattern.Units);
      Edge := Pattern.AddCurve(StartKey, EndKey, RoundedText(AngleBetween(Start.Position, Finish.Position), DRAG_ANGLE_DECIMALS),
        Handle, RoundedText(AngleBetween(Finish.Position, Start.Position), DRAG_ANGLE_DECIMALS), Handle, Role);
    end
    else
      Edge := Pattern.AddLine(StartKey, EndKey, Role);
  if Assigned(Edge) then
    Result := Committed(Document, True, [Edge.Key])
  else
  begin
    Result := Committed(Document, False, []);
    EndKey := '';
  end;
end;

function ExtendCurveToSnap(Document: TPatternDocument; const CurveKey: string; const Start, Finish: TSnap; Role: TEdgeRole;
  out EndKey: string): TSelectionEdit;
var
  Pattern: TPattern;
  Node: TEvalNode;
  Path: TCurvePathObject;
begin
  EndKey := '';
  if Distance(Start.Position, Finish.Position) < MIN_EDGE_LENGTH then
    Exit(Default(TSelectionEdit));
  Pattern := Document.Pattern;
  Node := Pattern.FindNode(CurveKey);
  // The curve has gone, as after undo: a new one starts instead
  if not (Node is TEdgeObject) then
    Exit(AddEdgeFromSnaps(Document, Start, Finish, True, Role, EndKey));
  Document.BeginChange(rsToolExtendCurve);
  Path := nil;
  EndKey := PointFromSnap(Pattern, Finish);
  if EndKey <> '' then
    Path := Pattern.ExtendCurve(TEdgeObject(Node), EndKey);
  Result := Committed(Document, Assigned(Path), [CurveKey]);
  if not Result.Done then
    EndKey := '';
end;

function AddShapeFromSnap(Document: TPatternDocument; const Start: TSnap; const Opposite: TVec2; Circle: boolean;
  Role: TEdgeRole): TSelectionEdit;
var
  Shape: TCircleObject;
  Edges: TRectangleEdges;
begin
  if Circle then
  begin
    Document.BeginChange(rsToolAddRound);
    Shape := CircleFromSnap(Document.Pattern, Start, Opposite, Role);
    if Assigned(Shape) then
      Exit(Committed(Document, True, [Shape.Key]));
    Exit(Committed(Document, False, []));
  end;
  Document.BeginChange(rsToolAddRectangle);
  if RectangleFromSnap(Document.Pattern, Start, Opposite, Role, Edges) then
    Result := Committed(Document, True, [Edges[0].Key, Edges[1].Key, Edges[2].Key, Edges[3].Key])
  else
    Result := Committed(Document, False, []);
end;

function AddPieceAt(Document: TPatternDocument; const At: TVec2): TSelectionEdit;
var
  Path: TPiecePath;
  Reason: string;
  Existing, Piece: TPieceObject;
begin
  if not DetectPiecePath(Document.Pattern, At, Path, Reason) then
    Exit(Refused(Reason));
  Existing := PieceOnPath(Document.Pattern, Path);
  if Assigned(Existing) then
  begin
    Result := Refused(Format(rsToolPieceExists, [Existing.DisplayName]));
    Result.Reselect := True;
    Result.Selection := [Existing.Key];
    Exit;
  end;
  Document.BeginChange(rsToolAddPiece);
  Piece := Document.Pattern.AddPiece('', Path, DEFAULT_PIECE_ALLOWANCE);
  if Assigned(Piece) then
    Result := Committed(Document, True, [Piece.Key])
  else
    Result := Committed(Document, False, []);
end;

function RemoveNotchesAt(Pattern: TPattern; const At: TVec2; Radius: double): boolean;
var
  Index, Notch: integer;
  Piece: TPieceObject;
begin
  Result := False;
  for Index := 0 to Pattern.ObjectCount - 1 do
    if Pattern.Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      for Notch := High(Piece.NotchMarks) downto 0 do
        if Distance(Piece.NotchMarks[Notch].Seam, At) <= Radius then
          Result := Pattern.RemoveNotch(Piece, Notch) or Result;
    end;
end;

function AddNotchesAt(Pattern: TPattern; const At: TVec2; Radius: double): boolean;
var
  Index: integer;
  Piece: TPieceObject;
  Target: TNotchTarget;
begin
  Result := False;
  if not NotchTargetAt(Pattern, At, Radius, Target) then
    Exit;
  for Index := Pattern.ObjectCount - 1 downto 0 do
    if Pattern.Objects[Index] is TPieceObject then
    begin
      Piece := TPieceObject(Pattern.Objects[Index]);
      if Piece.PathIndexOf(Target.EdgeKey) < 0 then
        Continue;
      if Target.PointKey <> '' then
        Result := Pattern.AddPointNotch(Piece, Pattern.UsePoint(Target.PointKey)) or Result
      else
        Result := Pattern.AddEdgeNotch(Piece, Target.EdgeKey, RoundLengthFormulaText(Target.Position, Pattern.Units)) or Result;
    end;
end;

function ToggleNotchAt(Document: TPatternDocument; const At: TVec2; Radius: double): TSelectionEdit;
begin
  Result := Default(TSelectionEdit);
  Document.BeginChange(rsToolRemoveNotch);
  if Document.Commit(RemoveNotchesAt(Document.Pattern, At, Radius)) then
  begin
    Result.Done := True;
    Exit;
  end;
  Document.BeginChange(rsToolAddNotch);
  Result.Done := Document.Commit(AddNotchesAt(Document.Pattern, At, Radius));
  if not Result.Done then
    Result.Message := rsToolNoSeam;
end;

function ShapeSizeText(Pattern: TPattern; const Start, Finish: TVec2; Circle: boolean): string;
begin
  if Circle then
    Result := Format(rsToolRadius, [LengthWithUnit(Distance(Start, Finish), Pattern.Units)])
  else
    Result := Format(rsToolRectangleSize, [LengthWithUnit(Abs(Finish.X - Start.X), Pattern.Units),
      LengthWithUnit(Abs(Finish.Y - Start.Y), Pattern.Units)]);
end;

function PickSeamEntry(Pattern: TPattern; const At: TVec2; Radius: double; var SideA, SideB: TSeamSide; OnB: boolean;
  out Message: string): boolean;
var
  Entry: TSeamEntry;
  Piece: TPieceObject;
begin
  Result := False;
  if not SeamEntryAt(Pattern, At, Radius, Entry) then
  begin
    Message := rsToolNoSeam;
    Exit;
  end;
  Piece := TPieceObject(Pattern.FindNode(Entry.PieceKey));
  if Piece.FoldEdgeKey = Entry.EdgeKey then
  begin
    Message := Format(rsSeamOnFold, [Pattern.FindNode(Entry.EdgeKey).DisplayName, Piece.DisplayName]);
    Exit;
  end;
  if OnB then
    ToggleSeamEntry(SideB, Entry)
  else
    ToggleSeamEntry(SideA, Entry);
  Message := SeamProgressText(Pattern, SideA, SideB, OnB);
  Result := True;
end;

function SeamProgressText(Pattern: TPattern; const SideA, SideB: TSeamSide; OnB: boolean): string;
var
  LengthA, LengthB: double;
begin
  LengthA := SeamSideLength(Pattern, SideA);
  LengthB := SeamSideLength(Pattern, SideB);
  Result := Format(rsToolSeamProgress, [SEAM_SIDE_NAMES[OnB], LengthWithUnit(LengthA, Pattern.Units),
    LengthWithUnit(LengthB, Pattern.Units), LengthWithUnit(LengthB - LengthA, Pattern.Units)]);
end;

function AddSeamFromSides(Document: TPatternDocument; const SideA, SideB: TSeamSide): TSelectionEdit;
var
  Seam: TSeamObject;
begin
  if (Length(SideA) = 0) or (Length(SideB) = 0) then
    Exit(Refused(rsToolSeamSides));
  Document.BeginChange(rsToolAddSeam);
  Seam := Document.Pattern.AddSeam('', SideA, SideB);
  if Assigned(Seam) then
    Result := Committed(Document, True, [Seam.Key])
  else
    Result := Committed(Document, False, []);
end;

function AddNoteFromSnap(Document: TPatternDocument; const Snap: TSnap; const Click: TVec2): TSelectionEdit;
var
  Note: TNoteObject;
begin
  Document.BeginChange(rsToolAddNote);
  Note := NoteFromSnap(Document.Pattern, Snap, Click, rsToolNewNoteText);
  if Assigned(Note) then
    Result := Committed(Document, True, [Note.Key])
  else
    Result := Committed(Document, False, []);
end;

function CalloutStartRefusal(Pattern: TPattern; const Tip: TSnap; const TipClick: TVec2): string;
var
  Anchor: TNoteAnchor;
  AnchorKey: string;
  Ratio: double;
begin
  Result := '';
  NoteAnchorFromSnap(Pattern, Tip, TipClick, Anchor, AnchorKey, Ratio);
  if Anchor = naFree then
    Result := rsPatternCalloutFree;
end;

function AddCalloutFromSnap(Document: TPatternDocument; const Tip: TSnap; const TipClick, BoxAt: TVec2): TSelectionEdit;
var
  Note: TNoteObject;
begin
  Document.BeginChange(rsToolAddCallout);
  Note := CalloutFromSnap(Document.Pattern, Tip, TipClick, BoxAt, rsToolNewNoteText, nlArrow);
  if Assigned(Note) then
    Result := Committed(Document, True, [Note.Key])
  else
    Result := Committed(Document, False, []);
end;

function MoveCalloutTip(Document: TPatternDocument; Note: TNoteObject; const Tip: TSnap; const TipClick: TVec2): TSelectionEdit;
begin
  Document.BeginChange(rsToolMoveTip);
  Result := Committed(Document, ReanchorFromSnap(Document.Pattern, Note, Tip, TipClick), [Note.Key]);
end;

end.
