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

// Meshes of a drape's placed pieces, with their seams paired vertex to vertex
// for Blender's cloth sewing, which pulls together vertices joined by loose
// edges. Both sides of a seam get points at the same fractions of their
// lengths, so the seam's ease is spread evenly along it, as easing would; the
// points are pinned in each piece's outline before it is resampled and
// meshed. Every edge end on either side is a break, and a corner on either
// side is one unless it is close to another; between breaks the points are no
// further apart than the spacing on the longer side. A side with a gap (a waist
// either side of a dart), or that goes on to another piece, has two points at
// the break, both sewn to the other side's one. A dart's legs pair from the
// apex out, the apex sewn to nothing. An edge in several seams gets every
// seam's points, those very close together merged. A piece on a fold is meshed
// whole, opened out; each half is sewn on its own. Which copies are sewn
// together goes by where they are placed: each copy of the piece with the most
// copies on the seam takes the nearest unused copy of every other piece on it.
// Drafted coordinates, mm. No LCL dependency.
unit Sloper.Core.DrapeMesh;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Mesher, Sloper.Core.DrapeFile;

type
  // Two mesh vertices sewn together, each an item of the drape and a point of
  // its mesh, from a seam of a source
  TDrapeSeamPair = record
    SourceId: integer;
    SeamKey: string;
    FirstItem, FirstVertex, SecondItem, SecondVertex: integer;
  end;

  TDrapeSeamPairArray = array of TDrapeSeamPair;
  TFlatMeshArray = array of TFlatMesh;

  TDrapeMeshing = record
    // One for each of the drape's items, of its placed seam line
    // (PlacedSeamLine) as drafted; empty when the copy cannot be meshed
    Meshes: TFlatMeshArray;
    Pairs: TDrapeSeamPairArray;
    // Seams left open on a copy
    Problems: TDrapeProblemArray;
  end;

// The placed items meshed at about Spacing (mm), and their seams paired
function MeshDrape(Drape: TDrape; Spacing: double = DEFAULT_MESH_SPACING): TDrapeMeshing;

resourcestring
  rsDrapeSeamOpen = '%s: seam %s is left open on a copy of %s, as no copy of %s is left to sew it to';

implementation

uses
  Math, Generics.Collections, Generics.Defaults, Sloper.Core.Numeric, Sloper.Core.Geometry, Sloper.Core.Geometry3, Sloper.Core.EvalTypes,
  Sloper.Core.Pattern, Sloper.Core.Piece, Sloper.Core.Seam, Sloper.Core.PatternSources, Sloper.Core.DrapePlacement;

const
  // Seam points closer than this share of the spacing along an outline are
  // merged into one
  PIN_MERGE_SHARE = 0.1;
  // A corner closer than this share of the spacing to another break is not one
  CORNER_MERGE_SHARE = 0.25;
  // Positions along an outline closer than this (mm) are the same
  ALONG_TOLERANCE = 1e-6;
  // Fractions of a seam's length closer than this are the same
  FRACTION_TOLERANCE = 1e-9;

type
  TDoubleList = specialize TList<double>;

  // A placed item's seam line as PlacedSeamLine gives it, with how far along it
  // (mm) each point is, and the positions along it the seams ask for
  TItemLine = record
    Piece: TPieceObject;
    Points: TVec2Array;
    // One more than Points: the last is the whole length
    Along: array of double;
    FoldStart: integer;
    Anchor: TVec2;
    Mirrored: boolean;
    Placement: TDrapePlacement;
    Pins: array of double;
  end;

  // A copy of a piece on a seam: a placed item and, on a fold, which half
  TSeamInstance = record
    Item: integer;
    MirrorHalf: boolean;
  end;

  TSeamInstanceArray = array of TSeamInstance;

  // The stretch of an item's line that a seam entry covers. Forward when the
  // seam runs the way the line does.
  TSeamSegment = record
    Item: integer;
    Start, Length: double;
    Forward: boolean;
  end;

  TSeamSegmentArray = array of TSeamSegment;

  TPinRef = record
    Item, Pin: integer;
  end;

  TPinRefArray = array of TPinRef;

  // A pin and its position, for sorting
  TPinPlace = record
    Pin: integer;
    Position: double;
  end;

  TPinPlaceList = specialize TList<TPinPlace>;

  TPinPair = record
    SourceId: integer;
    SeamKey: string;
    First, Second: TPinRef;
  end;

  // A fraction of a seam's length where its points must fall, or should
  TSeamBreak = record
    Fraction: double;
    Needed: boolean;
  end;

  TSeamBreakList = specialize TList<TSeamBreak>;

  { TDrapeMesher }

  TDrapeMesher = class
  private
    FDrape: TDrape;
    FSpacing: double;
    FLines: array of TItemLine;
    FPairs: array of TPinPair;
    FProblems: TDrapeProblemArray;
    procedure PrepareLines;
    function LineLength(Item: integer): double;
    function PointAlong(Item: integer; Position: double): TVec2;
    // The stretch of the item's line along path edge PathIndex, Low to High;
    // it runs with the path unless on a fold's mirrored half
    function EdgeRange(const Instance: TSeamInstance; PathIndex: integer; out Low, High: double): boolean;
    function Segment(Seam: TSeamObject; const Entry: TSeamEntry; OnSideB: boolean; const Instance: TSeamInstance;
      out Part: TSeamSegment): boolean;
    function PositionIn(const Part: TSeamSegment; Distance: double): double;
    function InstancesOf(SourceId: integer; const PieceKey: string): TSeamInstanceArray;
    // Where an instance's stretches of the seam lie once placed: their ends
    // and middles
    function InstancePoints(Seam: TSeamObject; const Instance: TSeamInstance; const PieceKey: string): TVec3Array;
    function SideSegments(Seam: TSeamObject; OnSideB: boolean; const Keys: TStringArray; const Group: TSeamInstanceArray;
      out Parts: TSeamSegmentArray; out Total: double): boolean;
    procedure AddCorners(Breaks: TSeamBreakList; const Parts: TSeamSegmentArray; Total: double);
    function SeamFractions(const PartsA, PartsB: TSeamSegmentArray; TotalA, TotalB: double): TDoubleArray;
    function AddPin(Item: integer; Position: double): integer;
    function PinsAt(const Parts: TSeamSegmentArray; Total, Fraction: double): TPinRefArray;
    procedure PairGroup(Source: TPatternSource; Seam: TSeamObject; const Keys: TStringArray; const Group: TSeamInstanceArray);
    procedure PairSeam(Source: TPatternSource; Seam: TSeamObject);
    function MeshItem(Item: integer; out PinVertex: TMeshIndexArray): TFlatMesh;
  public
    constructor Create(ADrape: TDrape; ASpacing: double);
    function Run: TDrapeMeshing;
  end;

constructor TDrapeMesher.Create(ADrape: TDrape; ASpacing: double);
begin
  inherited Create;
  FDrape := ADrape;
  FSpacing := ASpacing;
end;

procedure TDrapeMesher.PrepareLines;
var
  Index, Point: integer;
  Piece: TPieceObject;
  Line: TItemLine;
begin
  FLines := nil;
  SetLength(FLines, Length(FDrape.Items));
  for Index := 0 to High(FDrape.Items) do
  begin
    Line := Default(TItemLine);
    if FDrape.FindPiece(FDrape.Items[Index].Piece, Piece) and (Piece.State = esValid) and (Length(Piece.Outline) >= 3) and
      (Length(Piece.EdgeStarts) = Length(Piece.Path)) then
    begin
      Line.Piece := Piece;
      Line.Points := PlacedSeamLine(Piece);
      Line.FoldStart := PlacedFoldStart(Piece);
      Line.Anchor := PieceAnchor(Piece);
      Line.Mirrored := CopyIsMirrored(Piece, FDrape.Items[Index].Piece.Copy);
      Line.Placement := FDrape.Items[Index].Placement;
      SetLength(Line.Along, Length(Line.Points) + 1);
      Line.Along[0] := 0;
      for Point := 0 to High(Line.Points) do
        Line.Along[Point + 1] := Line.Along[Point] + Distance(Line.Points[Point], Line.Points[(Point + 1) mod Length(Line.Points)]);
    end;
    FLines[Index] := Line;
  end;
end;

function TDrapeMesher.LineLength(Item: integer): double;
begin
  Result := FLines[Item].Along[High(FLines[Item].Along)];
end;

function TDrapeMesher.PointAlong(Item: integer; Position: double): TVec2;
var
  Index, Count: integer;
  Step: double;
begin
  Count := Length(FLines[Item].Points);
  Position := Position - Floor(Position / LineLength(Item)) * LineLength(Item);
  Index := 0;
  while (Index < Count - 1) and (FLines[Item].Along[Index + 1] < Position) do
    Inc(Index);
  Step := FLines[Item].Along[Index + 1] - FLines[Item].Along[Index];
  if Step <= EPSILON then
    Exit(FLines[Item].Points[Index]);
  Result := Lerp(FLines[Item].Points[Index], FLines[Item].Points[(Index + 1) mod Count],
    EnsureRange((Position - FLines[Item].Along[Index]) / Step, 0, 1));
end;

function TDrapeMesher.EdgeRange(const Instance: TSeamInstance; PathIndex: integer; out Low, High: double): boolean;
var
  Count, First, Last, Start, LowIndex, HighIndex: integer;
  Line: TItemLine;
begin
  Low := 0;
  High := 0;
  Line := FLines[Instance.Item];
  Count := Length(Line.Piece.Outline);
  First := Line.Piece.EdgeStarts[PathIndex];
  if PathIndex < System.High(Line.Piece.Path) then
    Last := Line.Piece.EdgeStarts[PathIndex + 1]
  else
    Last := Count;
  Start := Line.FoldStart;
  if Start < 0 then
  begin
    LowIndex := First;
    HighIndex := Last;
  end
  else if not Instance.MirrorHalf then
  begin
    LowIndex := (First - Start + Count) mod Count;
    HighIndex := LowIndex + Last - First;
  end
  else
  begin
    // The mirrored half runs back: the edge's end comes first
    LowIndex := Count - 1 + ((Start - 1 - Last) mod Count + Count) mod Count;
    HighIndex := Count - 1 + ((Start - 1 - First) mod Count + Count) mod Count;
  end;
  Result := (LowIndex >= 0) and (LowIndex <= HighIndex) and (HighIndex <= System.High(Line.Along));
  if Result then
  begin
    Low := Line.Along[LowIndex];
    High := Line.Along[HighIndex];
  end;
end;

function TDrapeMesher.Segment(Seam: TSeamObject; const Entry: TSeamEntry; OnSideB: boolean; const Instance: TSeamInstance;
  out Part: TSeamSegment): boolean;
var
  Piece: TPieceObject;
  PathIndex: integer;
  Low, High: double;
begin
  Part := Default(TSeamSegment);
  Piece := FLines[Instance.Item].Piece;
  PathIndex := Piece.PathIndexOf(Entry.EdgeKey);
  if (PathIndex < 0) or (Entry.EdgeKey = Piece.FoldEdgeKey) or not EdgeRange(Instance, PathIndex, Low, High) then
    Exit(False);
  Part.Item := Instance.Item;
  Part.Length := High - Low;
  // Along the path, unless the seam runs back along the edge as drawn
  Part.Forward := (Seam.RunsForward(Piece, Entry, OnSideB) = not Piece.Path[PathIndex].Reversed) <> Instance.MirrorHalf;
  if Part.Forward then
    Part.Start := Low
  else
    Part.Start := High;
  Result := True;
end;

function TDrapeMesher.PositionIn(const Part: TSeamSegment; Distance: double): double;
begin
  Distance := EnsureRange(Distance, 0, Part.Length);
  if Part.Forward then
    Result := Part.Start + Distance
  else
    Result := Part.Start - Distance;
end;

function TDrapeMesher.InstancesOf(SourceId: integer; const PieceKey: string): TSeamInstanceArray;
var
  Item: integer;
  Instance: TSeamInstance;
begin
  Result := nil;
  for Item := 0 to High(FLines) do
    if Assigned(FLines[Item].Piece) and (FDrape.Items[Item].Piece.SourceId = SourceId) and
      (FDrape.Items[Item].Piece.PieceKey = PieceKey) then
    begin
      Instance.Item := Item;
      Instance.MirrorHalf := False;
      Insert(Instance, Result, Length(Result));
      if FLines[Item].FoldStart >= 0 then
      begin
        Instance.MirrorHalf := True;
        Insert(Instance, Result, Length(Result));
      end;
    end;
end;

function TDrapeMesher.InstancePoints(Seam: TSeamObject; const Instance: TSeamInstance; const PieceKey: string): TVec3Array;

  procedure AddSide(const Side: TSeamSide; OnSideB: boolean);
  var
    Entry: TSeamEntry;
    Part: TSeamSegment;
    Line: TItemLine;
    Share: integer;
  begin
    Line := FLines[Instance.Item];
    for Entry in Side do
      if (Entry.PieceKey = PieceKey) and Segment(Seam, Entry, OnSideB, Instance, Part) then
        for Share := 0 to 2 do
          Insert(PlacePoint(PointAlong(Instance.Item, PositionIn(Part, Part.Length * Share / 2)), Line.Anchor, Line.Mirrored,
            Line.Placement), Result, Length(Result));
  end;

begin
  Result := nil;
  AddSide(Seam.SideA, False);
  AddSide(Seam.SideB, True);
end;

function TDrapeMesher.SideSegments(Seam: TSeamObject; OnSideB: boolean; const Keys: TStringArray; const Group: TSeamInstanceArray;
  out Parts: TSeamSegmentArray; out Total: double): boolean;
var
  Side: TSeamSide;
  Entry: TSeamEntry;
  Part: TSeamSegment;
  Key: integer;
begin
  Parts := nil;
  Total := 0;
  if OnSideB then
    Side := Seam.SideB
  else
    Side := Seam.SideA;
  for Entry in Side do
  begin
    Key := 0;
    while (Key < Length(Keys)) and (Keys[Key] <> Entry.PieceKey) do
      Inc(Key);
    if (Key >= Length(Keys)) or not Segment(Seam, Entry, OnSideB, Group[Key], Part) then
      Exit(False);
    Insert(Part, Parts, Length(Parts));
    Total := Total + Part.Length;
  end;
  Result := (Length(Parts) > 0) and (Total > ALONG_TOLERANCE);
end;

function MakeBreak(Fraction: double; Needed: boolean): TSeamBreak;
begin
  Result.Fraction := Fraction;
  Result.Needed := Needed;
end;

procedure TDrapeMesher.AddCorners(Breaks: TSeamBreakList; const Parts: TSeamSegmentArray; Total: double);
var
  Part: TSeamSegment;
  Done, Low, High: double;
  Index, Count: integer;
  Line: TItemLine;
begin
  Done := 0;
  for Part in Parts do
  begin
    Line := FLines[Part.Item];
    Count := Length(Line.Points);
    Low := Min(Part.Start, PositionIn(Part, Part.Length));
    High := Max(Part.Start, PositionIn(Part, Part.Length));
    for Index := 0 to Count - 1 do
      if (Line.Along[Index] > Low + ALONG_TOLERANCE) and (Line.Along[Index] < High - ALONG_TOLERANCE) and
        (TurnAt(Line.Points[(Index + Count - 1) mod Count], Line.Points[Index], Line.Points[(Index + 1) mod Count]) > MESH_CORNER_ANGLE) then
        Breaks.Add(MakeBreak((Done + Abs(Line.Along[Index] - Part.Start)) / Total, False));
    Done := Done + Part.Length;
  end;
end;

function TDrapeMesher.SeamFractions(const PartsA, PartsB: TSeamSegmentArray; TotalA, TotalB: double): TDoubleArray;
var
  Breaks: TSeamBreakList;
  Kept: TDoubleList;
  Longer, Near, Done, Low, High: double;
  Part: TSeamSegment;
  Index, Step, Steps: integer;
  Close: boolean;
  Candidate: TSeamBreak;
begin
  Result := nil;
  Longer := Max(TotalA, TotalB);
  Near := CORNER_MERGE_SHARE * FSpacing / Longer;
  Breaks := TSeamBreakList.Create;
  Kept := TDoubleList.Create;
  try
    Breaks.Add(MakeBreak(0, True));
    Breaks.Add(MakeBreak(1, True));
    Done := 0;
    for Part in PartsA do
    begin
      Done := Done + Part.Length;
      Breaks.Add(MakeBreak(Done / TotalA, True));
    end;
    Done := 0;
    for Part in PartsB do
    begin
      Done := Done + Part.Length;
      Breaks.Add(MakeBreak(Done / TotalB, True));
    end;
    AddCorners(Breaks, PartsA, TotalA);
    AddCorners(Breaks, PartsB, TotalB);
    // Every needed break, then each corner not close to one kept
    for Candidate in Breaks do
      if Candidate.Needed then
        Kept.Add(EnsureRange(Candidate.Fraction, 0, 1));
    for Candidate in Breaks do
      if not Candidate.Needed then
      begin
        Close := False;
        for Index := 0 to Kept.Count - 1 do
          Close := Close or (Abs(Kept[Index] - Candidate.Fraction) < Near);
        if not Close then
          Kept.Add(Candidate.Fraction);
      end;
    Kept.Sort;
    // Each stretch between breaks divided evenly, no step longer than the
    // spacing on the longer side
    for Index := 0 to Kept.Count - 2 do
    begin
      Low := Kept[Index];
      High := Kept[Index + 1];
      if High - Low < FRACTION_TOLERANCE then
        Continue;
      Steps := Max(1, Ceil((High - Low) * Longer / FSpacing - 1e-9));
      for Step := 0 to Steps - 1 do
        Insert(Low + (High - Low) * Step / Steps, Result, Length(Result));
    end;
    Insert(1.0, Result, Length(Result));
  finally
    FreeAndNil(Kept);
    FreeAndNil(Breaks);
  end;
end;

function TDrapeMesher.AddPin(Item: integer; Position: double): integer;
begin
  Result := Length(FLines[Item].Pins);
  Insert(Position, FLines[Item].Pins, Result);
end;

function TDrapeMesher.PinsAt(const Parts: TSeamSegmentArray; Total, Fraction: double): TPinRefArray;
var
  Part: TSeamSegment;
  Done, Distance: double;
  Pin: TPinRef;
begin
  Result := nil;
  Done := 0;
  for Part in Parts do
  begin
    Distance := Fraction * Total - Done;
    if (Distance >= -FRACTION_TOLERANCE * Total) and (Distance <= Part.Length + FRACTION_TOLERANCE * Total) then
    begin
      Pin.Item := Part.Item;
      Pin.Pin := AddPin(Part.Item, PositionIn(Part, Distance));
      Insert(Pin, Result, Length(Result));
    end;
    Done := Done + Part.Length;
  end;
end;

procedure TDrapeMesher.PairGroup(Source: TPatternSource; Seam: TSeamObject; const Keys: TStringArray; const Group: TSeamInstanceArray);
var
  PartsA, PartsB: TSeamSegmentArray;
  TotalA, TotalB, Fraction: double;
  PinsA, PinsB: TPinRefArray;
  Pair: TPinPair;
  Index: integer;
begin
  if not SideSegments(Seam, False, Keys, Group, PartsA, TotalA) or not SideSegments(Seam, True, Keys, Group, PartsB, TotalB) then
    Exit;
  Pair.SourceId := Source.Id;
  Pair.SeamKey := Seam.Key;
  for Fraction in SeamFractions(PartsA, PartsB, TotalA, TotalB) do
  begin
    PinsA := PinsAt(PartsA, TotalA, Fraction);
    PinsB := PinsAt(PartsB, TotalB, Fraction);
    // Where a side breaks off (a gap, or another piece), its end and the next
    // start each pair with the other side's one point, or with the other
    // side's own end and start
    for Index := 0 to Max(Length(PinsA), Length(PinsB)) - 1 do
    begin
      Pair.First := PinsA[Min(Index, High(PinsA))];
      Pair.Second := PinsB[Min(Index, High(PinsB))];
      Insert(Pair, FPairs, Length(FPairs));
    end;
  end;
end;

procedure TDrapeMesher.PairSeam(Source: TPatternSource; Seam: TSeamObject);
var
  Keys: TStringArray;
  Instances: array of TSeamInstanceArray;
  Used: array of array of boolean;
  Group: TSeamInstanceArray;
  Points, Candidate: TVec3Array;
  Entry: TSeamEntry;
  Index, Key, Main, Best, Choice: integer;
  BestDistance, Gap: double;
  Point, Other: TVec3;
  Complete: boolean;
  MainPiece, Missing: TPieceObject;

  procedure AddKey(const PieceKey: string);
  var
    Known: string;
  begin
    for Known in Keys do
      if Known = PieceKey then
        Exit;
    Insert(PieceKey, Keys, Length(Keys));
  end;

begin
  Keys := nil;
  for Entry in Seam.SideA do
    AddKey(Entry.PieceKey);
  for Entry in Seam.SideB do
    AddKey(Entry.PieceKey);
  if Length(Keys) = 0 then
    Exit;
  Instances := nil;
  SetLength(Instances, Length(Keys));
  Used := nil;
  SetLength(Used, Length(Keys));
  Main := 0;
  for Key := 0 to High(Keys) do
  begin
    Instances[Key] := InstancesOf(Source.Id, Keys[Key]);
    // A piece with no copy placed is a problem of its own
    if Length(Instances[Key]) = 0 then
      Exit;
    SetLength(Used[Key], Length(Instances[Key]));
    if Length(Instances[Key]) > Length(Instances[Main]) then
      Main := Key;
  end;
  Group := nil;
  SetLength(Group, Length(Keys));
  for Index := 0 to High(Instances[Main]) do
  begin
    Group[Main] := Instances[Main][Index];
    Points := InstancePoints(Seam, Group[Main], Keys[Main]);
    Complete := True;
    for Key := 0 to High(Keys) do
    begin
      if Key = Main then
        Continue;
      Best := -1;
      BestDistance := 0;
      for Choice := 0 to High(Instances[Key]) do
        if not Used[Key][Choice] then
        begin
          Candidate := InstancePoints(Seam, Instances[Key][Choice], Keys[Key]);
          for Point in Candidate do
            for Other in Points do
            begin
              Gap := Distance3(Point, Other);
              if (Best < 0) or (Gap < BestDistance) then
              begin
                Best := Choice;
                BestDistance := Gap;
              end;
            end;
        end;
      if Best < 0 then
      begin
        MainPiece := FLines[Group[Main].Item].Piece;
        Missing := FLines[Instances[Key][0].Item].Piece;
        SetLength(FProblems, Length(FProblems) + 1);
        FProblems[High(FProblems)].Text := Format(rsDrapeSeamOpen, [ExtractFileName(Source.PatternFile), Seam.DisplayName,
          MainPiece.DisplayName, Missing.DisplayName]);
        FProblems[High(FProblems)].Item := Group[Main].Item;
        Complete := False;
        Break;
      end;
      Used[Key][Best] := True;
      Group[Key] := Instances[Key][Best];
      Insert(InstancePoints(Seam, Group[Key], Keys[Key]), Points, Length(Points));
    end;
    if Complete then
      PairGroup(Source, Seam, Keys, Group);
  end;
end;

function ComparePinPlaces(constref First, Second: TPinPlace): integer;
begin
  Result := CompareValue(First.Position, Second.Position);
  if Result = 0 then
    Result := CompareValue(First.Pin, Second.Pin);
end;

function TDrapeMesher.MeshItem(Item: integer; out PinVertex: TMeshIndexArray): TFlatMesh;
var
  Line: TItemLine;
  Pins: array of double;
  Order: TPinPlaceList;
  Place: TPinPlace;
  Merged: array of integer;
  MergedAt: array of double;
  Points: TVec2Array;
  Keep: TBooleanArray;
  KeptAt: TMeshIndexArray;
  PointOf: array of integer;
  Total, Position: double;
  Pin, Point, Count, Next: integer;

  procedure AddPoint(const Value: TVec2; Kept: boolean);
  begin
    Insert(Value, Points, Length(Points));
    Insert(Kept, Keep, Length(Keep));
  end;

begin
  Result := Default(TFlatMesh);
  PinVertex := nil;
  Line := FLines[Item];
  if not Assigned(Line.Piece) then
    Exit;
  Total := LineLength(Item);
  Count := Length(Line.Points);
  // Positions round the closed line, from 0 up to its length
  Pins := Copy(Line.Pins);
  for Pin := 0 to High(Pins) do
  begin
    Pins[Pin] := Pins[Pin] - Floor(Pins[Pin] / Total) * Total;
    if Pins[Pin] > Total - ALONG_TOLERANCE then
      Pins[Pin] := 0;
  end;
  // Pins in order, each merged into the one before when close to it
  Order := TPinPlaceList.Create;
  try
    for Pin := 0 to High(Pins) do
    begin
      Place.Pin := Pin;
      Place.Position := Pins[Pin];
      Order.Add(Place);
    end;
    Order.Sort(specialize TComparer<TPinPlace>.Construct(@ComparePinPlaces));
    Merged := nil;
    SetLength(Merged, Length(Pins));
    MergedAt := nil;
    for Place in Order do
      if (Length(MergedAt) > 0) and (Place.Position - MergedAt[High(MergedAt)] < PIN_MERGE_SHARE * FSpacing) then
        Merged[Place.Pin] := High(MergedAt)
      else
      begin
        Merged[Place.Pin] := Length(MergedAt);
        Insert(Place.Position, MergedAt, Length(MergedAt));
      end;
  finally
    FreeAndNil(Order);
  end;
  // The last merged round to the first
  if (Length(MergedAt) > 1) and (MergedAt[0] + Total - MergedAt[High(MergedAt)] < PIN_MERGE_SHARE * FSpacing) then
  begin
    for Pin := 0 to High(Merged) do
      if Merged[Pin] = High(MergedAt) then
        Merged[Pin] := 0;
    SetLength(MergedAt, Length(MergedAt) - 1);
  end;
  // The line with the merged pins in it, kept
  Points := nil;
  Keep := nil;
  PointOf := nil;
  SetLength(PointOf, Length(MergedAt));
  Next := 0;
  for Point := 0 to Count - 1 do
  begin
    AddPoint(Line.Points[Point], False);
    while (Next < Length(MergedAt)) and (MergedAt[Next] < Line.Along[Point + 1] - ALONG_TOLERANCE) do
    begin
      Position := MergedAt[Next];
      if Position <= Line.Along[Point] + ALONG_TOLERANCE then
        Keep[High(Keep)] := True
      else
        AddPoint(PointAlong(Item, Position), True);
      PointOf[Next] := High(Points);
      Inc(Next);
    end;
  end;
  // A pin at the very end is the first point
  while Next < Length(MergedAt) do
  begin
    Keep[0] := True;
    PointOf[Next] := 0;
    Inc(Next);
  end;
  Result := MeshPolygon(ResampleOutline(Points, Keep, FSpacing, KeptAt), FSpacing);
  if Length(Result.Points) = 0 then
    Exit;
  SetLength(PinVertex, Length(Pins));
  for Pin := 0 to High(Pins) do
    PinVertex[Pin] := KeptAt[PointOf[Merged[Pin]]];
end;

function TDrapeMesher.Run: TDrapeMeshing;
var
  Source: TPatternSource;
  Index, Item: integer;
  PinVertices: array of TMeshIndexArray;
  Pair: TPinPair;
  Sewn: TDrapeSeamPair;
  Seen: specialize TDictionary<string, boolean>;
  Name: string;
begin
  Result := Default(TDrapeMeshing);
  FPairs := nil;
  FProblems := nil;
  PrepareLines;
  for Source in FDrape.Sources do
    if Assigned(Source.Pattern) then
      for Index := 0 to Source.Pattern.ObjectCount - 1 do
        if (Source.Pattern.Objects[Index] is TSeamObject) and (Source.Pattern.Objects[Index].State = esValid) then
          PairSeam(Source, TSeamObject(Source.Pattern.Objects[Index]));
  SetLength(Result.Meshes, Length(FLines));
  PinVertices := nil;
  SetLength(PinVertices, Length(FLines));
  for Item := 0 to High(FLines) do
    Result.Meshes[Item] := MeshItem(Item, PinVertices[Item]);
  // Each pair once, leaving out a dart's apex sewn to itself
  Seen := specialize TDictionary<string, boolean>.Create;
  try
    for Pair in FPairs do
    begin
      if (Length(PinVertices[Pair.First.Item]) = 0) or (Length(PinVertices[Pair.Second.Item]) = 0) then
        Continue;
      Sewn.SourceId := Pair.SourceId;
      Sewn.SeamKey := Pair.SeamKey;
      Sewn.FirstItem := Pair.First.Item;
      Sewn.FirstVertex := PinVertices[Pair.First.Item][Pair.First.Pin];
      Sewn.SecondItem := Pair.Second.Item;
      Sewn.SecondVertex := PinVertices[Pair.Second.Item][Pair.Second.Pin];
      if (Sewn.FirstVertex < 0) or (Sewn.SecondVertex < 0) or ((Sewn.FirstItem = Sewn.SecondItem) and (Sewn.FirstVertex = Sewn.SecondVertex)) then
        Continue;
      Name := Format('%d:%d:%d:%d', [Sewn.FirstItem, Sewn.FirstVertex, Sewn.SecondItem, Sewn.SecondVertex]);
      if Seen.ContainsKey(Name) then
        Continue;
      Seen.Add(Name, True);
      Seen.AddOrSetValue(Format('%d:%d:%d:%d', [Sewn.SecondItem, Sewn.SecondVertex, Sewn.FirstItem, Sewn.FirstVertex]), True);
      Insert(Sewn, Result.Pairs, Length(Result.Pairs));
    end;
  finally
    FreeAndNil(Seen);
  end;
  Result.Problems := FProblems;
end;

function MeshDrape(Drape: TDrape; Spacing: double): TDrapeMeshing;
var
  Mesher: TDrapeMesher;
begin
  Mesher := TDrapeMesher.Create(Drape, Spacing);
  try
    Result := Mesher.Run;
  finally
    FreeAndNil(Mesher);
  end;
end;

end.
