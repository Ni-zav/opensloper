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

// The drape file being edited in the drape app, with undo. As the publish
// app's layout document, a change records the file's text before it and undo
// loads it back, so the sources are read again and items are held by index
// only between changes. No LCL dependency.
unit Sloper.Document.DrapeDocument;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Sloper.Core.TextHistory, Sloper.Core.DrapeFile, Sloper.Core.PatternSources;

type
  TDrapeDocument = class
  private
    FDrape: TDrape;
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
    // Replaces the file with one for this pattern, every piece placed by a guess
    procedure NewForPattern(const PatternFile: string);
    // An empty file, with no name, as the app starts
    procedure NewEmpty;
    function Open(const FileName: string; out ErrorMessage: string): boolean;
    function Save(const FileName: string; out ErrorMessage: string): boolean;
    // Reads the pattern files and the body's measurements again; not an undo step
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
    property Drape: TDrape read FDrape;
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

implementation

constructor TDrapeDocument.Create;
begin
  FDrape := TDrape.Create;
  FHistory := TTextHistory.Create;
  FSavedText := FDrape.SaveToText;
end;

destructor TDrapeDocument.Destroy;
begin
  FreeAndNil(FHistory);
  FreeAndNil(FDrape);
  inherited Destroy;
end;

procedure TDrapeDocument.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TDrapeDocument.NewForPattern(const PatternFile: string);
begin
  Inc(FGeneration);
  FDrape.Clear;
  FDrape.FileName := ChangeFileExt(PatternFile, DRAPE_EXTENSION);
  FDrape.Name := ChangeFileExt(ExtractFileName(PatternFile), '');
  FDrape.AddSource(ExtractFileName(PatternFile), '', '');
  FDrape.LoadSources;
  FDrape.GuessPlacements;
  FHistory.Clear;
  // Not saved yet, so closing it asks
  FSavedText := '';
  Changed;
end;

procedure TDrapeDocument.NewEmpty;
begin
  Inc(FGeneration);
  FDrape.Clear;
  FDrape.FileName := '';
  FHistory.Clear;
  FSavedText := FDrape.SaveToText;
  Changed;
end;

function TDrapeDocument.Open(const FileName: string; out ErrorMessage: string): boolean;
begin
  Inc(FGeneration);
  Result := FDrape.LoadFromFile(FileName, ErrorMessage);
  if not Result then
    Exit;
  FDrape.LoadSources;
  FHistory.Clear;
  FSavedText := FDrape.SaveToText;
  Changed;
end;

function TDrapeDocument.Save(const FileName: string; out ErrorMessage: string): boolean;
begin
  Result := FDrape.SaveToFile(FileName, ErrorMessage);
  if Result then
  begin
    FSavedText := FDrape.SaveToText;
    FHistory.EndMerging;
    Changed;
  end;
end;

procedure TDrapeDocument.Reload;
begin
  FDrape.LoadSources;
  Changed;
end;

// A file seen changing may still be being written, so it has to read the same
// on two checks running before it is loaded
function TDrapeDocument.CheckSources: string;
var
  Source: TPatternSource;
  Stamps: string;
begin
  Result := '';
  Stamps := '';
  for Source in FDrape.Sources do
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

function TDrapeDocument.GetModified: boolean;
begin
  Result := FDrape.SaveToText <> FSavedText;
end;

function TDrapeDocument.GetCanUndo: boolean;
begin
  Result := FHistory.CanUndo;
end;

function TDrapeDocument.GetCanRedo: boolean;
begin
  Result := FHistory.CanRedo;
end;

function TDrapeDocument.GetUndoDescription: string;
begin
  Result := FHistory.UndoDescription;
end;

procedure TDrapeDocument.BeginChange(const Description: string);
begin
  FBefore := FDrape.SaveToText;
  FDescription := Description;
  FChangeOpen := True;
end;

procedure TDrapeDocument.EndChange(const MergeKey: string);
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  if FDrape.SaveToText = FBefore then
    Exit;
  FHistory.Add(FBefore, FDescription, MergeKey);
  Changed;
end;

procedure TDrapeDocument.CancelChange;
begin
  if not FChangeOpen then
    Exit;
  FChangeOpen := False;
  Restore(FBefore);
end;

procedure TDrapeDocument.LiveUpdate;
begin
  Changed;
end;

// Keeps the file name, which the text does not hold
procedure TDrapeDocument.Restore(const Text: string);
var
  Reason: string;
begin
  if FDrape.LoadFromText(Text, Reason) then
    FDrape.LoadSources;
  Changed;
end;

procedure TDrapeDocument.Undo;
begin
  if CanUndo then
    Restore(FHistory.Undo(FDrape.SaveToText));
end;

procedure TDrapeDocument.Redo;
begin
  if CanRedo then
    Restore(FHistory.Redo(FDrape.SaveToText));
end;

end.
