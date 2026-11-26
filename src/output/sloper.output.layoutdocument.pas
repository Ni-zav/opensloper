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

// The layout being edited in the publish app, with undo. A change records the
// layout's saved text before it, as TPatternDocument does, and undo loads it
// back, so the sources are read again and placements are held by index only
// between changes.
unit Sloper.Output.LayoutDocument;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Sloper.Core.TextHistory, Sloper.Output.Layout, Sloper.Core.PatternSources;

type
  TLayoutDocument = class
  private
    FLayout: TLayout;
    FHistory: TTextHistory;
    FSavedText: string;
    FChangeOpen: boolean;
    FGeneration: integer;
    FBefore, FDescription: string;
    // The files' stamps last time CheckSources saw them differ
    FPendingStamps: string;
    FOnChange: TNotifyEvent;
    function GetModified: boolean;
    function GetCanUndo: boolean;
    function GetCanRedo: boolean;
    function GetUndoDescription: string;
    procedure Restore(const Text: string);
    procedure Changed;
  public
    constructor Create;
    destructor Destroy; override;
    // Replaces the layout with one for this pattern, every piece placed. The
    // pattern is read from SourceFiles when it has been given
    procedure NewForPattern(const PatternFile: string);
    // Opens a layout file from disk, and its sources from disk too
    function Open(const FileName: string; out ErrorMessage: string): boolean;
    // Opens a layout from its file's text, with no file name, reading its
    // sources from SourceFiles, as the browser does. A source whose file is
    // missing gets a problem naming it (MissingFile); once SourceFiles has
    // it, Reload reads it.
    function OpenText(const Text: string; out ErrorMessage: string): boolean;
    function Save(const FileName: string; out ErrorMessage: string): boolean;
    // The layout's text, as Save writes it, counted as saved: the browser
    // downloads it, so no file is written here
    function SaveText: string;
    // Reads the pattern files again; not an undo step
    procedure Reload;
    // Call regularly: reads the sources again once a saved file has stopped
    // changing, and returns the names of the patterns read, '' when none
    function CheckSources: string;
    procedure BeginChange(const Description: string);
    // A step that matches the last one's non-empty key, within a second, joins it
    procedure EndChange(const MergeKey: string = '');
    procedure CancelChange;
    // Redraws without recording anything, during a drag
    procedure LiveUpdate;
    procedure Undo;
    procedure Redo;
    // The edits the publish window and the web page both make to one placed
    // piece, by its placement index, each one undo step
    procedure TurnPiece(Index: integer);
    procedure FlipPiece(Index: integer);
    // Back to the tray
    procedure UnplacePiece(Index: integer);
    // Places one copy from the tray in the rows below the others; False, and
    // nothing changed, when its piece cannot be placed
    function PlaceCopy(const Item: TUnplacedCopy): boolean;
    // The Output tab's settings, one undo step, which changes within a
    // second of each other join, as a run of spin clicks. Pages left out are
    // forgotten once the page grid moves, and a new material or kind takes
    // its material's size. False with the reason, nothing changed, when the
    // paper or sheet leaves nothing to print on.
    function ChangeOutput(const Output: TLayoutOutput; out Reason: string): boolean;
    // Leaves the page with this caption out of the print, or puts it back
    procedure TogglePage(const Caption: string);
    // The Patterns tab's edits, each one undo step. Paths are as the layout
    // stores them (TLayout.StoredPath). AddPattern returns how many copies
    // it put in the tray.
    function AddPattern(const Path: string): integer;
    procedure RemovePattern(Source: TPatternSource);
    // The measurement file to use, '' for the one the pattern names; the
    // size goes back to the file's first, as a size belongs to its file
    procedure SetMeasurements(Source: TPatternSource; const MeasurementFile: string);
    procedure SetSize(Source: TPatternSource; const Size: string);
    // The Notes tab's edits, each one undo step. A new note goes at the left,
    // below the pieces; its index.
    function AddNote: integer;
    // Changes within a second to the same note join one step, as typing
    procedure ChangeNote(Index: integer; const Note: TSheetNote);
    procedure DeleteNote(Index: integer);
    // The files' contents sources are read from, from now on, in place of
    // disk; undo and Reload read them again
    function SourceFiles: TSourceFiles;
    property Layout: TLayout read FLayout;
    property Modified: boolean read GetModified;
    property CanUndo: boolean read GetCanUndo;
    property CanRedo: boolean read GetCanRedo;
    property UndoDescription: string read GetUndoDescription;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // A change is open, as during a drag
    property ChangeOpen: boolean read FChangeOpen;
    // Counts the files it has held: New and Open add one, so what an
    // assistant learned about the one before is known to be stale
    property Generation: integer read FGeneration;
  end;

resourcestring
  rsLayoutTurnPiece = 'Turn piece';
  rsLayoutFlipPiece = 'Flip piece';
  rsLayoutUnplacePiece = 'Unplace piece';
  rsLayoutPlaceOne = 'Place piece';
  rsLayoutChangePaper = 'Change paper';
  rsLayoutAddPattern = 'Add pattern';
  rsLayoutAddNote = 'Add note';
  rsLayoutNewNote = 'New note';
  rsLayoutChangeNote = 'Change note';
  rsLayoutDeleteNote = 'Delete note';
  rsLayoutRemovePattern = 'Remove pattern';
  rsLayoutChangeMeasurements = 'Change measurements';
  rsLayoutChangeSize = 'Change size';
  rsLayoutTogglePage = 'Leave page out';
  rsLayoutCannotPlace = 'This piece has a problem in the pattern, so it cannot be placed yet';

implementation

uses
  Math, Sloper.Output.Tiling;

const
  // A new note's text size, in points, and its gap below the pieces, in mm
  NEW_NOTE_SIZE = 12;
  NEW_NOTE_GAP = 10;

constructor TLayoutDocument.Create;
begin
  FLayout := TLayout.Create;
  FHistory := TTextHistory.Create;
  FSavedText := FLayout.SaveToText;
end;

destructor TLayoutDocument.Destroy;
begin
  FreeAndNil(FHistory);
  FreeAndNil(FLayout);
  inherited Destroy;
end;

procedure TLayoutDocument.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

function TLayoutDocument.SourceFiles: TSourceFiles;
begin
  Result := FLayout.UseSourceFiles;
end;

procedure TLayoutDocument.NewForPattern(const PatternFile: string);
begin
  Inc(FGeneration);
  FLayout.Clear;
  FLayout.FileName := ChangeFileExt(PatternFile, LAYOUT_EXTENSION);
  FLayout.Name := ChangeFileExt(ExtractFileName(PatternFile), '');
  FLayout.AddSource(ExtractFileName(PatternFile), '', '');
  FLayout.LoadSources;
  FLayout.PlaceNewPieces;
  FLayout.UseDefaultTitle;
  FHistory.Clear;
  // Not saved yet, so closing it asks
  FSavedText := '';
  Changed;
end;

function TLayoutDocument.Open(const FileName: string; out ErrorMessage: string): boolean;
begin
  Inc(FGeneration);
  FLayout.ReadSourcesFromDisk;
  Result := FLayout.LoadFromFile(FileName, ErrorMessage);
  if not Result then
    Exit;
  FLayout.LoadSources;
  FHistory.Clear;
  FSavedText := FLayout.SaveToText;
  Changed;
end;

function TLayoutDocument.OpenText(const Text: string; out ErrorMessage: string): boolean;
begin
  Inc(FGeneration);
  FLayout.UseSourceFiles;
  FLayout.FileName := '';
  Result := FLayout.LoadFromText(Text, ErrorMessage);
  if not Result then
    Exit;
  FLayout.LoadSources;
  FHistory.Clear;
  FSavedText := FLayout.SaveToText;
  Changed;
end;

function TLayoutDocument.Save(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := FLayout.SaveToFile(FileName, ErrorMessage);
  if Result then
  begin
    FSavedText := FLayout.SaveToText;
    FHistory.EndMerging;
    Changed;
  end;
end;

function TLayoutDocument.SaveText: string;
begin
  Result := FLayout.SaveToText;
  FSavedText := Result;
  FHistory.EndMerging;
  Changed;
end;

procedure TLayoutDocument.Reload;
begin
  FLayout.LoadSources;
  Changed;
end;

// A file seen changing may still be being written, so it has to read the same
// on two checks running before it is loaded
function TLayoutDocument.CheckSources: string;
var
  Source: TPatternSource;
  Stamps: string;
begin
  Result := '';
  Stamps := '';
  for Source in FLayout.Sources do
  begin
    Stamps := Stamps + Source.CurrentStamp + ';';
    if Source.CurrentStamp <> Source.LoadedStamp then
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + ExtractFileName(Source.PatternPath);
    end;
  end;
  if Result = '' then
  begin
    FPendingStamps := '';
    Exit;
  end;
  if Stamps <> FPendingStamps then
  begin
    FPendingStamps := Stamps;
    Exit('');
  end;
  FPendingStamps := '';
  Reload;
end;

function TLayoutDocument.GetModified: boolean;
begin
  Result := FLayout.SaveToText <> FSavedText;
end;

function TLayoutDocument.GetCanUndo: boolean;
begin
  Result := FHistory.CanUndo;
end;

function TLayoutDocument.GetCanRedo: boolean;
begin
  Result := FHistory.CanRedo;
end;

function TLayoutDocument.GetUndoDescription: string;
begin
  Result := FHistory.UndoDescription;
end;

procedure TLayoutDocument.BeginChange(const Description: string);
begin
  FBefore := FLayout.SaveToText;
  FDescription := Description;
  FChangeOpen := True;
end;

procedure TLayoutDocument.EndChange(const MergeKey: string);
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  if FLayout.SaveToText = FBefore then
    Exit;
  FHistory.Add(FBefore, FDescription, MergeKey);
  Changed;
end;

procedure TLayoutDocument.CancelChange;
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  Restore(FBefore);
end;

procedure TLayoutDocument.LiveUpdate;
begin
  Changed;
end;

// Keeps the file name, which the text does not hold
procedure TLayoutDocument.Restore(const Text: string);
var
  Reason: string;
begin
  if FLayout.LoadFromText(Text, Reason) then
    FLayout.LoadSources;
  Changed;
end;

procedure TLayoutDocument.Undo;
begin
  if CanUndo then
    Restore(FHistory.Undo(FLayout.SaveToText));
end;

procedure TLayoutDocument.Redo;
begin
  if CanRedo then
    Restore(FHistory.Redo(FLayout.SaveToText));
end;

procedure TLayoutDocument.TurnPiece(Index: integer);
begin
  if (Index < 0) or (Index > High(FLayout.Placements)) then
    Exit;
  BeginChange(rsLayoutTurnPiece);
  FLayout.Placements[Index].Rotation := (FLayout.Placements[Index].Rotation + 90) mod 360;
  EndChange;
end;

procedure TLayoutDocument.FlipPiece(Index: integer);
begin
  if (Index < 0) or (Index > High(FLayout.Placements)) then
    Exit;
  BeginChange(rsLayoutFlipPiece);
  FLayout.Placements[Index].Flipped := not FLayout.Placements[Index].Flipped;
  EndChange;
end;

procedure TLayoutDocument.UnplacePiece(Index: integer);
begin
  if (Index < 0) or (Index > High(FLayout.Placements)) then
    Exit;
  BeginChange(rsLayoutUnplacePiece);
  FLayout.RemovePlacement(Index);
  EndChange;
end;

function TLayoutDocument.ChangeOutput(const Output: TLayoutOutput; out Reason: string): boolean;
var
  Wanted, Before: TLayoutOutput;
begin
  Reason := '';
  Wanted := Output;
  Before := FLayout.Output;
  // Page names mean other sheets once the grid moves
  if (Wanted.Paper <> Before.Paper) or (Wanted.Tiles.PaperWidth <> Before.Tiles.PaperWidth) or
    (Wanted.Tiles.PaperHeight <> Before.Tiles.PaperHeight) or (Wanted.Tiles.Margin <> Before.Tiles.Margin) or
    (Wanted.Tiles.Overlap <> Before.Tiles.Overlap) or (Wanted.Kind <> Before.Kind) then
    Wanted.ExcludedPages := nil;
  if not TilesAreUsable(Wanted.Tiles) or (Wanted.RollWidth <= 2 * Wanted.Tiles.Margin) or (Wanted.MaterialWidth <= 0) then
  begin
    Reason := rsLayoutNoPrintArea;
    Exit(False);
  end;
  BeginChange(rsLayoutChangePaper);
  FLayout.Output := Wanted;
  // Choosing a material, or a material sheet, starts from that material's size
  if (Wanted.Material <> Before.Material) or (Wanted.Kind <> Before.Kind) then
    FLayout.TakeMaterialSize;
  EndChange('paper');
  Result := True;
end;

procedure TLayoutDocument.TogglePage(const Caption: string);
begin
  if Caption = '' then
    Exit;
  BeginChange(rsLayoutTogglePage);
  FLayout.TogglePage(Caption);
  EndChange;
end;

function TLayoutDocument.AddPattern(const Path: string): integer;
var
  Before: integer;
begin
  Before := Length(FLayout.Unplaced);
  BeginChange(rsLayoutAddPattern);
  FLayout.AddSource(Path, '', '');
  FLayout.LoadSources;
  EndChange;
  Result := Length(FLayout.Unplaced) - Before;
end;

procedure TLayoutDocument.RemovePattern(Source: TPatternSource);
begin
  BeginChange(rsLayoutRemovePattern);
  FLayout.RemoveSource(Source);
  EndChange;
end;

procedure TLayoutDocument.SetMeasurements(Source: TPatternSource; const MeasurementFile: string);
begin
  BeginChange(rsLayoutChangeMeasurements);
  Source.MeasurementFile := MeasurementFile;
  Source.Size := '';
  FLayout.LoadSources;
  EndChange;
end;

procedure TLayoutDocument.SetSize(Source: TPatternSource; const Size: string);
begin
  BeginChange(rsLayoutChangeSize);
  Source.Size := Size;
  FLayout.LoadSources;
  EndChange;
end;

function TLayoutDocument.AddNote: integer;
var
  Lowest: double;
  Shape: TPlacedPiece;
begin
  Lowest := 0;
  for Shape in FLayout.PlacedPieces do
    Lowest := Max(Lowest, Shape.Bounds.MaxY + NEW_NOTE_GAP);
  BeginChange(rsLayoutAddNote);
  Result := FLayout.AddNote(rsLayoutNewNote, 0, Lowest, NEW_NOTE_SIZE);
  EndChange;
end;

procedure TLayoutDocument.ChangeNote(Index: integer; const Note: TSheetNote);
begin
  if (Index < 0) or (Index > High(FLayout.Notes)) then
    Exit;
  BeginChange(rsLayoutChangeNote);
  FLayout.Notes[Index] := Note;
  EndChange('note:' + IntToStr(Index));
end;

procedure TLayoutDocument.DeleteNote(Index: integer);
begin
  if (Index < 0) or (Index > High(FLayout.Notes)) then
    Exit;
  BeginChange(rsLayoutDeleteNote);
  FLayout.RemoveNote(Index);
  EndChange;
end;

function TLayoutDocument.PlaceCopy(const Item: TUnplacedCopy): boolean;
begin
  Result := Item.CanPlace;
  if not Result then
    Exit;
  BeginChange(rsLayoutPlaceOne);
  FLayout.PlaceCopies([Item]);
  EndChange;
end;

end.
