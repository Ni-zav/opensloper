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

// Text placed on a pattern or layout: the {fields} it may hold, its lines, and
// how much room it takes. A named font is measured by the measurer the output
// layer installs, from the font's own widths; the default font, or one that
// cannot be measured, is estimated from Helvetica's average letter width.
// No LCL dependency.
unit Sloper.Core.TextFields;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, Sloper.Core.Geometry, Sloper.Core.Pattern, Sloper.Core.Note, Sloper.Core.Piece, Sloper.Core.Materials;

const
  // The fields a title block can show; also usable as {pattern.name} in text
  FIELD_PATTERN_NAME = 'pattern.name';
  FIELD_MEASUREMENTS_NAME = 'measurements.name';
  FIELD_LAYOUT_NAME = 'layout.name';
  FIELD_DATE = 'date';
  FIELD_CUT_LIST = 'cutlist';
  FIELD_MATERIALS = 'materials';
  // Filled in by layouts only, from the material needed
  FIELD_MATERIAL_NEEDED = 'materialneeded';
  // The size chosen from a size table
  FIELD_SIZE = 'size';
  // Filled in for a note on one piece: its name, how to cut it and its material
  FIELD_PIECE_NAME = 'piece.name';
  FIELD_PIECE_CUT = 'piece.cut';
  FIELD_PIECE_MATERIAL = 'piece.material';
  POINTS_TO_MM = 25.4 / 72;

type
  // How far Text runs, in mm, at Size points in Style's font; False when the
  // font cannot be measured, so the estimate is used
  TTextMeasurer = function(const Style: TTextStyle; const Text: string; Size: double; out Width: double): boolean;

  // What fields stand for in text; an empty value leaves the field as typed
  TFieldValues = record
    PatternName, MeasurementsName, LayoutName, Date, Page, Pages, CutList, Materials, MaterialNeeded, Size: string;
    PieceName, PieceCut, PieceMaterial: string;
  end;

// Text with its known {fields} filled in
function ExpandFields(const Text: string; const Values: TFieldValues): string;
// Text as lines, however it was broken
function TextLines(const Text: string): TStringArray;
// About how far a line of text runs, in mm, at Size points in Helvetica
function TextWidth(const Text: string; Size: double): double; overload;
// How far it runs in Style's font, measured when it can be
function TextWidth(const Text: string; Size: double; const Style: TTextStyle): double; overload;
// Measures named fonts from here on; nil goes back to estimating them
procedure SetTextMeasurer(Measurer: TTextMeasurer);
// The height of one line of text, in mm
function LineHeight(Size: double): double;
// Today's date as fields show it
function FieldDateText: string;
// The fields a pattern's notes can show: the pattern's name from its file
// (empty when it has none), its measurement set and size, today's date, its
// cut list and materials. Page and pages are left as typed.
function PatternFieldValues(Pattern: TPattern; const PatternFileName: string): TFieldValues;
// Values with the piece fields of Piece added; Whole as for its cut caption
function PieceFieldValues(Pattern: TPattern; Piece: TPieceObject; const Values: TFieldValues; Whole: boolean = False): TFieldValues;
// Values with the piece fields added when the note prints with one piece
// only; on none or several they are left as typed
function NoteFieldValues(Pattern: TPattern; Note: TNoteObject; const Values: TFieldValues): TFieldValues; overload;
// The same for Shown, text the note is about to show, such as a preview
function NoteFieldValues(Pattern: TPattern; Note: TNoteObject; const Values: TFieldValues; const Shown: string): TFieldValues; overload;
// What a note would show with Typed, in display form, as its text: each {=…}
// worked out with the pattern as last evaluated, and one that does not work
// out yet, or is not closed, kept as typed. For showing text while it is typed.
function NotePreviewText(Pattern: TPattern; const Typed: string): string;
// The rough area a note's text covers, in mm, from its top left down; a
// stamp's drawing at its scale
function NoteBox(Note: TNoteObject; const Values: TFieldValues): TRect2; overload;
// The same for Shown in place of the note's own text
function NoteBox(Note: TNoteObject; const Values: TFieldValues; const Shown: string): TRect2; overload;
// What a note draws round its text: the white box when it has one, or just
// the text; a callout's leader leaves from its edge
function NoteFrame(Note: TNoteObject; const Values: TFieldValues): TRect2; overload;
function NoteFrame(Note: TNoteObject; const Values: TFieldValues; const Shown: string): TRect2; overload;

implementation

const
  // Line spacing, and the average width of a Helvetica letter, as shares of its size
  LINE_SPACING = 1.25;
  LETTER_WIDTH = 0.52;
  // Helvetica Bold's letters are this much wider
  BOLD_LETTER_WIDTH = 0.57;
  // The title block fields only this unit fills in: the sheet's number and count
  FIELD_PAGE = 'page';
  FIELD_PAGES = 'pages';

function ExpandFields(const Text: string; const Values: TFieldValues): string;

  procedure Fill(const Field, Value: string);
  begin
    if Value <> '' then
      Result := StringReplace(Result, '{' + Field + '}', Value, [rfReplaceAll]);
  end;

begin
  Result := Text;
  Fill(FIELD_PATTERN_NAME, Values.PatternName);
  Fill(FIELD_MEASUREMENTS_NAME, Values.MeasurementsName);
  Fill(FIELD_LAYOUT_NAME, Values.LayoutName);
  Fill(FIELD_DATE, Values.Date);
  Fill(FIELD_PAGE, Values.Page);
  Fill(FIELD_PAGES, Values.Pages);
  Fill(FIELD_CUT_LIST, Values.CutList);
  Fill(FIELD_MATERIALS, Values.Materials);
  Fill(FIELD_MATERIAL_NEEDED, Values.MaterialNeeded);
  Fill(FIELD_SIZE, Values.Size);
  Fill(FIELD_PIECE_NAME, Values.PieceName);
  Fill(FIELD_PIECE_CUT, Values.PieceCut);
  Fill(FIELD_PIECE_MATERIAL, Values.PieceMaterial);
end;

function TextLines(const Text: string): TStringArray;
var
  Unified: string;
  Start, Position: integer;
begin
  Result := nil;
  Unified := StringReplace(Text, #13#10, #10, [rfReplaceAll]);
  Unified := StringReplace(Unified, #13, #10, [rfReplaceAll]);
  Start := 1;
  for Position := 1 to Length(Unified) + 1 do
    if (Position > Length(Unified)) or (Unified[Position] = #10) then
    begin
      Insert(Copy(Unified, Start, Position - Start), Result, Length(Result));
      Start := Position + 1;
    end;
end;

var
  InstalledMeasurer: TTextMeasurer;

function TextWidth(const Text: string; Size: double): double;
begin
  Result := Length(UTF8Decode(Text)) * Size * LETTER_WIDTH * POINTS_TO_MM;
end;

function TextWidth(const Text: string; Size: double; const Style: TTextStyle): double;
begin
  if (Style.Font <> '') and Assigned(InstalledMeasurer) and InstalledMeasurer(Style, Text, Size, Result) then
    Exit;
  if Style.Bold then
    Result := Length(UTF8Decode(Text)) * Size * BOLD_LETTER_WIDTH * POINTS_TO_MM
  else
    Result := TextWidth(Text, Size);
end;

procedure SetTextMeasurer(Measurer: TTextMeasurer);
begin
  InstalledMeasurer := Measurer;
end;

function LineHeight(Size: double): double;
begin
  Result := Size * LINE_SPACING * POINTS_TO_MM;
end;

function FieldDateText: string;
begin
  Result := FormatDateTime('yyyy-mm-dd', Date);
end;

function PatternFieldValues(Pattern: TPattern; const PatternFileName: string): TFieldValues;
begin
  Result := Default(TFieldValues);
  Result.PatternName := ChangeFileExt(ExtractFileName(PatternFileName), '');
  if Assigned(Pattern.Measurements) then
  begin
    Result.MeasurementsName := Pattern.Measurements.Name;
    if Pattern.Measurements.SizeName <> '' then
      Result.MeasurementsName := Trim(Result.MeasurementsName + ' ' + Pattern.Measurements.SizeName);
    Result.Size := Pattern.Measurements.SizeName;
  end;
  Result.Date := FieldDateText;
  Result.CutList := Pattern.CutList;
  Result.Materials := Pattern.MaterialNames;
end;

function PieceFieldValues(Pattern: TPattern; Piece: TPieceObject; const Values: TFieldValues; Whole: boolean): TFieldValues;
var
  Material: TPatternMaterial;
begin
  Result := Values;
  Result.PieceName := Piece.DisplayName;
  Result.PieceCut := Piece.CutText(Whole);
  Material := Pattern.MaterialOf(Piece);
  if Assigned(Material) then
    Result.PieceMaterial := Material.Name;
end;

function NoteFieldValues(Pattern: TPattern; Note: TNoteObject; const Values: TFieldValues): TFieldValues;
begin
  Result := NoteFieldValues(Pattern, Note, Values, Note.ShownText);
end;

function NoteFieldValues(Pattern: TPattern; Note: TNoteObject; const Values: TFieldValues; const Shown: string): TFieldValues;
var
  Pieces: TPieceObjectArray;
begin
  Result := Values;
  // Finding the piece costs more than filling in the text, so only when asked
  if Pos('{piece.', Shown) = 0 then
    Exit;
  Pieces := Pattern.NotePieces(Note);
  if Length(Pieces) = 1 then
    Result := PieceFieldValues(Pattern, Pieces[0], Values);
end;

function NotePreviewText(Pattern: TPattern; const Typed: string): string;
var
  Template: string;
  Expressions: TStringArray;
  ErrorPos, Index, Next: integer;
  Value: double;
begin
  if not SplitDraftValues(Typed, Template, Expressions, ErrorPos) then
    Exit(Typed);
  Result := '';
  Next := 0;
  for Index := 1 to Length(Template) do
    if Template[Index] <> VALUE_MARK then
      Result := Result + Template[Index]
    else
    begin
      if Pattern.EvaluateText(Expressions[Next], Value) then
        Result := Result + DraftValueText(Value)
      else
        Result := Result + '{=' + Expressions[Next] + '}';
      Inc(Next);
    end;
end;

function NoteBox(Note: TNoteObject; const Values: TFieldValues): TRect2;
begin
  Result := NoteBox(Note, Values, Note.ShownText);
end;

function NoteBox(Note: TNoteObject; const Values: TFieldValues; const Shown: string): TRect2;
var
  Lines: TStringArray;
  Line: string;
  Widest: double;
begin
  // A stamp is its drawing, at its scale
  if Note.IsStamp then
  begin
    Result.MinX := Note.Position.X;
    Result.MinY := Note.Position.Y;
    Result.MaxX := Note.Position.X + Note.Drawing.Width * Note.Scale;
    Result.MaxY := Note.Position.Y + Note.Drawing.Height * Note.Scale;
    Exit;
  end;
  Lines := TextLines(ExpandFields(Shown, Values));
  Widest := 0;
  for Line in Lines do
    if TextWidth(Line, Note.Size, Note.Style) > Widest then
      Widest := TextWidth(Line, Note.Size, Note.Style);
  Result.MinX := Note.Position.X;
  Result.MinY := Note.Position.Y;
  Result.MaxX := Note.Position.X + Widest;
  Result.MaxY := Note.Position.Y + Length(Lines) * LineHeight(Note.Size);
end;

function NoteFrame(Note: TNoteObject; const Values: TFieldValues): TRect2;
begin
  Result := NoteFrame(Note, Values, Note.ShownText);
end;

function NoteFrame(Note: TNoteObject; const Values: TFieldValues; const Shown: string): TRect2;
begin
  Result := NoteBox(Note, Values, Shown);
  if Note.Boxed then
    Result := PaddedBox(Result);
end;

end.
