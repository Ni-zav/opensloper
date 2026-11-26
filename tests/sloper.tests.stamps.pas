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

// SVG stamps (annotations stage 4): reading an SVG drawing at true size, what
// is refused and warned about, the drawing's path data, and a stamp kept in a
// pattern, drawn and printed.
unit Sloper.Tests.Stamps;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, Sloper.Tests.TestCase, Sloper.Core.Geometry, Sloper.Core.Stamp, Sloper.Core.SvgImport,
  Sloper.Core.Pattern, Sloper.Core.Note;

type
  TTestStamps = class(TOSTestCase)
  private
    FPattern, FLoaded: TPattern;
    function Svg(const Size, Body: string): string;
    function Read(const Text: string; out Warnings: TStringArray): TStampDrawing;
    function Refusal(const Text: string): string;
    function Stamp(const Body: string): TNoteObject;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTrueSizeInMillimetres;
    procedure TestPixelsWarned;
    procedure TestViewBoxScales;
    procedure TestTextRefused;
    procedure TestImageAndClonesRefused;
    procedure TestNotSvg;
    procedure TestPlainDoctype;
    procedure TestDoctypeSubsetRefused;
    procedure TestDoctypeBackstop;
    procedure TestDoctypeUnreadable;
    procedure TestEmptyRefused;
    procedure TestTransformsAndGroups;
    procedure TestRotation;
    procedure TestRelativeAndShortCommands;
    procedure TestArcsAndCircles;
    procedure TestStrokeInBounds;
    procedure TestColours;
    procedure TestInheritedAndStyleAttribute;
    procedure TestInkscapeElementsSkipped;
    procedure TestHiddenSkipped;
    procedure TestPathDataRoundTrip;
    procedure TestBadStoredData;
    procedure TestPatternRoundTrip;
    procedure TestStampBox;
    procedure TestScaleLimits;
    procedure TestLoadRefusesBadDrawing;
    procedure TestDraftSVG;
    procedure TestPropertyRows;
    procedure TestObjectList;
    procedure TestAddStampStep;
  end;

implementation

uses
  StrUtils, Sloper.Core.PatternFile, Sloper.Core.TextFields, Sloper.Core.Draft, Sloper.Core.Units, Sloper.Output.DraftSVG,
  Sloper.Document.PatternDocument, Sloper.Editor.PropertyRows, Sloper.Editor.ObjectList, Sloper.Editor.SelectionEdits,
  Sloper.Editor.ToolEdits;

const
  MM_SIZE = 'width="20mm" height="10mm" viewBox="0 0 20 10"';

procedure TTestStamps.SetUp;
begin
  FPattern := TPattern.Create;
  FLoaded := TPattern.Create;
end;

procedure TTestStamps.TearDown;
begin
  FreeAndNil(FLoaded);
  FreeAndNil(FPattern);
end;

function TTestStamps.Svg(const Size, Body: string): string;
begin
  Result := '<?xml version="1.0"?>' + LineEnding + '<svg xmlns="http://www.w3.org/2000/svg" ' + Size + '>' + Body + '</svg>';
end;

function TTestStamps.Read(const Text: string; out Warnings: TStringArray): TStampDrawing;
var
  Err: string;
begin
  AssertTrue(Err, ImportSvgStamp(Text, Result, Warnings, Err));
end;

function TTestStamps.Refusal(const Text: string): string;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  AssertFalse('refused', ImportSvgStamp(Text, Drawing, Warnings, Result));
  AssertFalse('no drawing', HasDrawing(Drawing));
end;

function TTestStamps.Stamp(const Body: string): TNoteObject;
var
  Warnings: TStringArray;
begin
  Result := FPattern.AddNote('', 'Logo', naFree, '', '', '10', '20');
  AssertTrue(FPattern.LastError, FPattern.SetNoteDrawing(Result, Read(Svg(MM_SIZE, Body), Warnings)));
end;

procedure TTestStamps.TestTrueSizeInMillimetres;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<rect x="2" y="1" width="16" height="8" fill="#ff0000"/>'), Warnings);
  AssertEquals('no warnings', 0, Length(Warnings));
  AssertNear('width', 16, Drawing.Width);
  AssertNear('height', 8, Drawing.Height);
  AssertEquals('one path', 1, Length(Drawing.Paths));
  AssertEquals('red', $FF0000, Drawing.Paths[0].Fill);
  AssertEquals('no stroke', STAMP_NO_COLOUR, Drawing.Paths[0].Stroke);
  AssertPointsNear('moved to the origin', Vec2(0, 0), Drawing.Paths[0].Contours[0].Start);
end;

procedure TTestStamps.TestPixelsWarned;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg('width="96" height="48"', '<rect width="96" height="48"/>'), Warnings);
  AssertNear('an inch', 25.4, Drawing.Width);
  AssertNear('half an inch', 12.7, Drawing.Height);
  AssertEquals('one warning', 1, Length(Warnings));
  AssertEquals(rsSvgPixels, Warnings[0]);
  // No size at all is pixels too
  Drawing := Read(Svg('', '<rect width="96" height="96"/>'), Warnings);
  AssertNear('no size', 25.4, Drawing.Width);
  AssertEquals('warned', 1, Length(Warnings));
  // Pixels with a viewBox still are
  Drawing := Read(Svg('width="192px" viewBox="0 0 96 96"', '<rect width="96" height="96"/>'), Warnings);
  AssertNear('two inches', 50.8, Drawing.Width);
  AssertEquals('warned with a viewBox', 1, Length(Warnings));
end;

procedure TTestStamps.TestViewBoxScales;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  // 1 inch across holding 100 units: each unit is 0.254 mm
  Drawing := Read(Svg('width="1in" height="1in" viewBox="-50 -50 100 100"', '<rect x="-50" y="-50" width="100" height="50"/>'), Warnings);
  AssertNear('width', 25.4, Drawing.Width);
  AssertNear('height', 12.7, Drawing.Height);
  AssertEquals('no warnings', 0, Length(Warnings));
  // A height alone sets the scale
  Drawing := Read(Svg('height="2cm" viewBox="0 0 10 10"', '<rect width="5" height="10"/>'), Warnings);
  AssertNear('from the height', 10, Drawing.Width);
end;

procedure TTestStamps.TestTextRefused;
begin
  AssertEquals(rsSvgText, Refusal(Svg(MM_SIZE, '<rect width="5" height="5"/><text x="0" y="5">Logo</text>')));
  AssertEquals('inside a group', rsSvgText, Refusal(Svg(MM_SIZE, '<g><g><text>A</text></g></g>')));
  AssertTrue('asks for paths', Pos('paths', rsSvgText) > 0);
end;

procedure TTestStamps.TestImageAndClonesRefused;
begin
  AssertEquals(rsSvgImage, Refusal(Svg(MM_SIZE, '<image href="logo.png" width="5" height="5"/>')));
  AssertEquals(rsSvgUse, Refusal(Svg(MM_SIZE, '<defs><rect id="r" width="5" height="5"/></defs><use href="#r"/>')));
end;

procedure TTestStamps.TestNotSvg;
begin
  AssertEquals('another kind of XML', rsSvgNotSvg, Refusal('<html><body/></html>'));
  AssertTrue('not XML', Pos(Copy(rsSvgNotXml, 1, 20), Refusal('M 0 0 L 10 10')) = 1);
end;

procedure TTestStamps.TestPlainDoctype;
const
  SVG_RECTANGLE = '<svg xmlns="http://www.w3.org/2000/svg" ' + MM_SIZE + '><rect width="5" height="5"/></svg>';
  SVG_11 = '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">';
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read('<?xml version="1.0"?>' + #10 + '<!-- <!DOCTYPE svg> -->' + #10 + SVG_11 + SVG_RECTANGLE, Warnings);
  AssertEquals('the drawing imports', 1, Length(Drawing.Paths));
  Drawing := Read('<!DOCTYPE svg SYSTEM "urn:example:stamp[1]">' + SVG_RECTANGLE, Warnings);
  AssertEquals('a quoted bracket is part of the identifier', 1, Length(Drawing.Paths));
  Drawing := Read('<!DOCTYPE stamp:svg><stamp:svg xmlns:stamp="http://www.w3.org/2000/svg" ' + MM_SIZE +
    '><stamp:rect width="5" height="5"/></stamp:svg>', Warnings);
  AssertEquals('the SVG root can use a prefix', 1, Length(Drawing.Paths));
end;

procedure TTestStamps.TestDoctypeSubsetRefused;
const
  SVG_RECTANGLE = '<svg xmlns="http://www.w3.org/2000/svg" ' + MM_SIZE + '><rect width="5" height="5"/></svg>';
begin
  AssertEquals(rsSvgDoctypeSubset, Refusal('<!DOCTYPE svg []>' + SVG_RECTANGLE));
end;

procedure TTestStamps.TestDoctypeBackstop;
const
  SVG_RECTANGLE = '<svg xmlns="http://www.w3.org/2000/svg" ' + MM_SIZE + '><rect width="5" height="5"/></svg>';
begin
  AssertTrue('a second declaration is still refused',
    Pos(Copy(rsSvgNotXml, 1, 20), Refusal('<!DOCTYPE svg><!DOCTYPE svg>' + SVG_RECTANGLE)) = 1);
end;

// A declaration the importer cannot read says how to fix the file, rather
// than giving the parser's own words
procedure TTestStamps.TestDoctypeUnreadable;
const
  SVG_RECTANGLE = '<svg xmlns="http://www.w3.org/2000/svg" ' + MM_SIZE + '><rect width="5" height="5"/></svg>';
begin
  AssertEquals('lower case, as in HTML', rsSvgDoctypeUnread, Refusal('<!doctype svg>' + SVG_RECTANGLE));
  AssertEquals('a literal left open', rsSvgDoctypeUnread, Refusal('<!DOCTYPE svg SYSTEM "abc>' + SVG_RECTANGLE));
  AssertEquals('PUBLIC without its system ID', rsSvgDoctypeUnread, Refusal('<!DOCTYPE svg PUBLIC "x">' + SVG_RECTANGLE));
  AssertEquals('no name', rsSvgDoctypeUnread, Refusal('<!DOCTYPE>' + SVG_RECTANGLE));
end;

procedure TTestStamps.TestEmptyRefused;
begin
  AssertEquals('nothing', rsSvgEmpty, Refusal(Svg(MM_SIZE, '')));
  AssertEquals('only defs', rsSvgEmpty, Refusal(Svg(MM_SIZE, '<defs><rect width="5" height="5"/></defs>')));
  AssertEquals('neither filled nor stroked', rsSvgEmpty, Refusal(Svg(MM_SIZE, '<rect width="5" height="5" fill="none"/>')));
end;

procedure TTestStamps.TestTransformsAndGroups;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<g transform="translate(5,5) scale(2)"><rect width="1" height="1"/></g>' +
    '<rect x="0" y="0" width="1" height="1" transform="matrix(1 0 0 1 2 1)"/>'), Warnings);
  // From (2, 1) to (7, 7)
  AssertNear('width', 5, Drawing.Width);
  AssertNear('height', 6, Drawing.Height);
  AssertEquals('two paths', 2, Length(Drawing.Paths));
  AssertPointsNear('scaled rect, moved', Vec2(3, 4), Drawing.Paths[0].Contours[0].Start);
end;

procedure TTestStamps.TestRotation;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<path d="M0 0 L10 0 L10 4 Z" transform="rotate(90)"/>'), Warnings);
  AssertNear('width', 4, Drawing.Width);
  AssertNear('height', 10, Drawing.Height);
  AssertTrue('closed', Drawing.Paths[0].Contours[0].Closed);
end;

procedure TTestStamps.TestRelativeAndShortCommands;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  // Numbers run together, implicit linetos after m, h and v, and a second
  // subpath starting where z went back to
  Drawing := Read(Svg(MM_SIZE, '<path d="m1,1h10v5-5zm0 0l-1-1 2,0q1 1 2 0t2 0c1 1 2 1 3 0s2-1 3 0"/>'), Warnings);
  AssertEquals('two contours', 2, Length(Drawing.Paths[0].Contours));
  AssertEquals('h, v, v', 3, Length(Drawing.Paths[0].Contours[0].Segments));
  AssertEquals('l, l, q, t, c, s', 6, Length(Drawing.Paths[0].Contours[1].Segments));
  AssertTrue('q is a cubic', Drawing.Paths[0].Contours[1].Segments[2].Curve);
  AssertNear('across', 12, Drawing.Width, 0.01);
  AssertEquals('no warnings', 0, Length(Warnings));
  Drawing := Read(Svg(MM_SIZE, '<path d="M0 0 L 10 0 L 10 x 5"/>'), Warnings);
  AssertEquals('drawn up to the fault', 1, Length(Drawing.Paths[0].Contours[0].Segments));
  AssertEquals(rsSvgBadPath, Warnings[0]);
end;

procedure TTestStamps.TestArcsAndCircles;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<circle cx="5" cy="5" r="5"/>'), Warnings);
  AssertNear('circle across', 10, Drawing.Width, 0.01);
  AssertNear('circle down', 10, Drawing.Height, 0.01);
  Drawing := Read(Svg(MM_SIZE, '<ellipse cx="0" cy="0" rx="6" ry="2"/>'), Warnings);
  AssertNear('ellipse across', 12, Drawing.Width, 0.01);
  AssertNear('ellipse down', 4, Drawing.Height, 0.01);
  // A half circle over the top
  Drawing := Read(Svg(MM_SIZE, '<path d="M0 5 A 5 5 0 0 1 10 5"/>'), Warnings);
  AssertNear('half across', 10, Drawing.Width, 0.01);
  AssertNear('half down', 5, Drawing.Height, 0.01);
  // Radii too small are grown to fit
  Drawing := Read(Svg(MM_SIZE, '<path d="M0 0 a 1 1 0 1 0 10 0"/>'), Warnings);
  AssertNear('grown', 10, Drawing.Width, 0.01);
  Drawing := Read(Svg(MM_SIZE, '<rect width="10" height="6" rx="2"/>'), Warnings);
  AssertEquals('rounded corners', 8, Length(Drawing.Paths[0].Contours[0].Segments));
end;

procedure TTestStamps.TestStrokeInBounds;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<line x1="0" y1="0" x2="10" y2="0" stroke="black" stroke-width="2"/>'), Warnings);
  AssertNear('height is the stroke', 2, Drawing.Height);
  AssertNear('width', 12, Drawing.Width);
  AssertNear('stroke width', 2, Drawing.Paths[0].StrokeWidth);
  AssertEquals('a line has nothing to fill', STAMP_NO_COLOUR, Drawing.Paths[0].Fill);
  // Scaled with its shape
  Drawing := Read(Svg(MM_SIZE, '<g transform="scale(3)"><polyline points="0,0 5,0" fill="none" stroke="#000" stroke-width="0.5"/></g>'),
    Warnings);
  AssertNear('scaled stroke', 1.5, Drawing.Paths[0].StrokeWidth);
  AssertEquals('not filled', STAMP_NO_COLOUR, Drawing.Paths[0].Fill);
end;

procedure TTestStamps.TestColours;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<rect width="1" height="1" fill="#0f0"/><rect width="1" height="1" fill="rgb(0, 0, 255)"/>' +
    '<rect width="1" height="1" fill="rgb(100%, 0%, 0%)"/><rect width="1" height="1" fill="navy"/>' +
    '<rect width="1" height="1" fill="url(#gradient)"/><rect width="1" height="1" fill="chartreuse"/>' +
    '<rect width="1" height="1" color="#123456" fill="currentColor"/>'), Warnings);
  AssertEquals('short hex', $00FF00, Drawing.Paths[0].Fill);
  AssertEquals('rgb', $0000FF, Drawing.Paths[1].Fill);
  AssertEquals('percent', $FF0000, Drawing.Paths[2].Fill);
  AssertEquals('named', $000080, Drawing.Paths[3].Fill);
  AssertEquals('gradient in black', 0, Drawing.Paths[4].Fill);
  AssertEquals('unknown in black', 0, Drawing.Paths[5].Fill);
  AssertEquals('current colour', $123456, Drawing.Paths[6].Fill);
  AssertEquals('two warnings', 2, Length(Warnings));
end;

procedure TTestStamps.TestInheritedAndStyleAttribute;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<g fill="green" fill-rule="evenodd"><rect width="1" height="1"/>' +
    '<rect width="1" height="1" fill="red" style="fill:none;stroke:#00f;stroke-width:0.5"/></g>'), Warnings);
  AssertEquals('inherited', $008000, Drawing.Paths[0].Fill);
  AssertTrue('even-odd inherited', Drawing.Paths[0].EvenOdd);
  AssertEquals('style wins', STAMP_NO_COLOUR, Drawing.Paths[1].Fill);
  AssertEquals('stroke from style', $0000FF, Drawing.Paths[1].Stroke);
  AssertNear('stroke width from style', 0.5, Drawing.Paths[1].StrokeWidth);
end;

procedure TTestStamps.TestInkscapeElementsSkipped;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read('<svg:svg xmlns:svg="http://www.w3.org/2000/svg" xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd" ' +
    MM_SIZE + '><sodipodi:namedview pagecolor="#ffffff"/><svg:metadata/><svg:path d="M0 0 H 4 V 3 Z"/></svg:svg>', Warnings);
  AssertEquals('one path', 1, Length(Drawing.Paths));
  AssertNear('width', 4, Drawing.Width);
  Drawing := Read(Svg(MM_SIZE, '<style>.a { fill: red }</style><rect class="a" width="1" height="1"/>'), Warnings);
  AssertEquals(rsSvgStyleSheet, Warnings[0]);
end;

procedure TTestStamps.TestHiddenSkipped;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
begin
  Drawing := Read(Svg(MM_SIZE, '<rect width="1" height="1"/><g display="none"><rect width="9" height="9"/></g>' +
    '<rect width="9" height="9" style="display: none"/><rect width="9" height="9" visibility="hidden"/>'), Warnings);
  AssertEquals('one shown', 1, Length(Drawing.Paths));
  AssertNear('width', 1, Drawing.Width);
end;

procedure TTestStamps.TestPathDataRoundTrip;
var
  Drawing: TStampDrawing;
  Warnings: TStringArray;
  Contours: TStampContourArray;
  Data, Err: string;
begin
  Drawing := Read(Svg(MM_SIZE, '<path d="M0 0 L 10 0 C 10 5 5 5 0 5 Z M 1 1 L 2 2"/>'), Warnings);
  Data := StampPathData(Drawing.Paths[0], Vec2(0, 0), 1);
  AssertEquals('M 0 0 L 10 0 C 10 5 5 5 0 5 Z M 1 1 L 2 2', Data);
  AssertTrue(Err, ParseStampPathData(Data, Contours, Err));
  AssertEquals('two contours', 2, Length(Contours));
  AssertTrue('first closed', Contours[0].Closed);
  AssertFalse('second open', Contours[1].Closed);
  AssertTrue('curve kept', Contours[0].Segments[1].Curve);
  AssertEquals('placed and scaled', 'M 5 6 L 25 6 C 25 16 15 16 5 16 Z M 7 8 L 9 10', StampPathData(Drawing.Paths[0], Vec2(5, 6), 2));
end;

procedure TTestStamps.TestBadStoredData;
var
  Contours: TStampContourArray;
  Err: string;
begin
  AssertFalse('relative', ParseStampPathData('M 0 0 l 1 1', Contours, Err));
  AssertFalse('no start', ParseStampPathData('L 1 1', Contours, Err));
  AssertFalse('short', ParseStampPathData('M 0 0 C 1 1 2 2', Contours, Err));
  AssertFalse('after Z', ParseStampPathData('M 0 0 L 1 1 Z L 2 2', Contours, Err));
  AssertTrue('empty is no contours', ParseStampPathData('', Contours, Err));
end;

procedure TTestStamps.TestPatternRoundTrip;
var
  Note, Back: TNoteObject;
  Text: string;
  Err: string;
begin
  Note := Stamp('<rect width="20" height="10" fill="#ff0000" stroke="#000000" stroke-width="0.5" fill-rule="evenodd"/>');
  AssertTrue(FPattern.LastError, FPattern.SetNoteScale(Note, 1.5));
  Text := SavePatternToText(FPattern);
  AssertTrue('drawing saved', Pos('"drawing": {', Text) > 0);
  AssertTrue('scale saved', Pos('"scale": 1.5', Text) > 0);
  AssertTrue('path data', Pos('"d": "M ', Text) > 0);
  AssertTrue(Err, LoadPatternFromText(FLoaded, Text, Err));
  AssertEquals('same again', Text, SavePatternToText(FLoaded));
  Back := TNoteObject(FLoaded.FindObject('Note'));
  AssertTrue('a stamp', Back.IsStamp);
  AssertNear('scale', 1.5, Back.Scale);
  AssertEquals('fill', $FF0000, Back.Drawing.Paths[0].Fill);
  AssertEquals('stroke', $000000, Back.Drawing.Paths[0].Stroke);
  AssertTrue('even-odd', Back.Drawing.Paths[0].EvenOdd);
  AssertNear('width', 20.5, Back.Drawing.Width);
  // A note of text writes neither
  FPattern.AddNote('', 'Plain', naFree, '', '', '0', '0');
  Text := SavePatternToText(FPattern);
  AssertEquals('only the stamp has a drawing', Pos('"drawing"', Text), RPos('"drawing"', Text));
end;

procedure TTestStamps.TestStampBox;
var
  Note: TNoteObject;
  Box: TRect2;
begin
  Note := Stamp('<rect width="20" height="10"/>');
  FPattern.SetNoteScale(Note, 2);
  FPattern.Evaluate;
  Box := NoteBox(Note, Default(TFieldValues));
  AssertNear('left', 10, Box.MinX);
  AssertNear('top', 20, Box.MinY);
  AssertNear('right', 50, Box.MaxX);
  AssertNear('bottom', 40, Box.MaxY);
  // Back to text
  FPattern.SetNoteDrawing(Note, Default(TStampDrawing));
  AssertFalse('text again', Note.IsStamp);
end;

procedure TTestStamps.TestScaleLimits;
var
  Note: TNoteObject;
begin
  Note := Stamp('<rect width="20" height="10"/>');
  AssertFalse('zero', FPattern.SetNoteScale(Note, 0));
  AssertFalse('too big', FPattern.SetNoteScale(Note, MAX_STAMP_SCALE + 1));
  AssertTrue('smallest', FPattern.SetNoteScale(Note, MIN_STAMP_SCALE));
  AssertNear('kept', MIN_STAMP_SCALE, Note.Scale);
end;

procedure TTestStamps.TestLoadRefusesBadDrawing;
var
  Text, Err: string;
begin
  Stamp('<rect width="20" height="10"/>');
  Text := SavePatternToText(FPattern);
  AssertFalse('bad path data', LoadPatternFromText(FLoaded, StringReplace(Text, '"d": "M', '"d": "Q', []), Err));
  AssertTrue(Err, Pos('path data', Err) > 0);
  AssertFalse('bad colour', LoadPatternFromText(FLoaded, StringReplace(Text, '"fill": "#000000"', '"fill": "black"', []), Err));
  AssertFalse('bad scale', LoadPatternFromText(FLoaded, StringReplace(Text, '"drawing"', '"scale": 0,'#10'"drawing"', []), Err));
end;

// Drawn as paths in its own colours at its place and scale, never as text
procedure TTestStamps.TestDraftSVG;
var
  Note: TNoteObject;
  Drawn: string;
begin
  Note := Stamp('<rect width="20" height="10" fill="#ff0000" stroke="#0000ff" stroke-width="0.5" fill-rule="evenodd"/>');
  FPattern.SetNoteScale(Note, 2);
  FPattern.Evaluate;
  Drawn := DraftToSVG(FPattern, DefaultDraftSVGOptions);
  AssertTrue('a path of the note', Pos('<path data-id="' + Note.Key + '" d="M 10.5 20.5 ', Drawn) > 0);
  AssertTrue('filled', Pos('fill="#ff0000" fill-rule="evenodd" stroke="#0000ff" stroke-width="1"', Drawn) > 0);
  AssertEquals('not as text', 0, Pos('>Logo<', Drawn));
  FPattern.SetNotePrint(Note, False);
  AssertEquals('screen only', 0, Pos('#ff0000', DraftToSVG(FPattern, DefaultDraftSVGOptions)));
end;

// A stamp's scale in place of the text's size and font
procedure TTestStamps.TestPropertyRows;
var
  Note: TNoteObject;
  Row: TPropertyRow;
  Ids: string;
  Document: TPatternDocument;
  Reason: string;
begin
  Note := Stamp('<rect width="20" height="10"/>');
  Ids := '';
  for Row in PropertyRows(FPattern, Note) do
    Ids := Ids + Row.Id + ' ';
  AssertTrue('scale', Pos(PROPERTY_ROW_STAMP_SCALE + ' ', Ids) > 0);
  AssertTrue('name text', Pos(PROPERTY_ROW_NOTE_TEXT + ' ', Ids) > 0);
  AssertEquals('no size', 0, Pos(PROPERTY_ROW_NOTE_SIZE + ' ', Ids));
  AssertEquals('no font', 0, Pos(PROPERTY_ROW_NOTE_FONT + ' ', Ids));
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Stamp');
    Note := Document.Pattern.AddNote('', 'Logo', naFree, '', '', '0', '0');
    Document.Pattern.SetNoteDrawing(Note, TNoteObject(FPattern.FindObject('Note')).Drawing);
    Document.Commit(True);
    AssertTrue(Reason, CommitPropertyNumber(Document, Note, PROPERTY_ROW_STAMP_SCALE, 3, Reason));
    AssertNear('scaled', 3, TNoteObject(Document.Pattern.FindObject('Note')).Scale);
    AssertFalse('too big', CommitPropertyNumber(Document, Document.Pattern.FindObject('Note'), PROPERTY_ROW_STAMP_SCALE, 1000, Reason));
    AssertTrue(Document.Undo);
    AssertNear('undone', 1, TNoteObject(Document.Pattern.FindObject('Note')).Scale);
    AssertTrue('still a stamp after undo', TNoteObject(Document.Pattern.FindObject('Note')).IsStamp);
  finally
    FreeAndNil(Document);
  end;
end;

procedure TTestStamps.TestObjectList;
var
  Note: TNoteObject;
begin
  Note := Stamp('<rect width="20" height="10"/>');
  FPattern.Evaluate;
  AssertEquals('type', rsTypeStamp, TypeCaption(Note));
  AssertEquals('named by its text', 'Logo', ResultText(Note, muMillimetre));
  FPattern.SetNoteText(Note, '');
  AssertEquals('by its size', '20 mm by 10 mm', ResultText(Note, muMillimetre));
end;

// Centred on what is selected, or free in the middle of the view
procedure TTestStamps.TestAddStampStep;
var
  Document: TPatternDocument;
  Drawing: TStampDrawing;
  Warnings: TStringArray;
  Edit: TSelectionEdit;
  Note: TNoteObject;
  Point: TDraftObject;
begin
  Drawing := Read(Svg(MM_SIZE, '<rect width="20" height="10"/>'), Warnings);
  Document := TPatternDocument.Create;
  try
    Document.BeginChange('Point');
    Point := Document.Pattern.AddFreePoint('A', '100', '50');
    Document.Commit(True);
    Edit := AddStampStep(Document, Drawing, 'Logo', [Point.Key], Vec2(0, 0));
    AssertTrue(Edit.Message, Edit.Done);
    Note := TNoteObject(Document.Pattern.FindNode(Edit.Selection[0]));
    AssertTrue('on the point', Note.Anchor = naPoint);
    AssertTrue('a stamp', Note.IsStamp);
    AssertPointsNear('centred on it', Vec2(90, 45), Note.Position);
    AssertEquals('one undo step', 'Add stamp', Document.UndoDescription);
    Edit := AddStampStep(Document, Drawing, 'Free', [], Vec2(30, 40));
    Note := TNoteObject(Document.Pattern.FindNode(Edit.Selection[0]));
    AssertTrue('free', Note.Anchor = naFree);
    AssertPointsNear('centred in the view', Vec2(20, 35), Note.Position);
  finally
    FreeAndNil(Document);
  end;
end;

initialization
  RegisterTest(TTestStamps);

end.
