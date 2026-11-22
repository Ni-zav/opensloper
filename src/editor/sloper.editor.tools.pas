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

// The table of the canvas's tools: each one's key, icon, caption and hint,
// so the desktop canvas, its main form and the web editor list them from one
// place. What the tools do is in Sloper.UI.CanvasTools.
unit Sloper.Editor.Tools;

{$mode ObjFPC}{$H+}

interface

uses
  Sloper.Core.Shortcuts, Sloper.Core.IconSet;

type
  // ctSelect selects and drags; ctZoom zooms to a box, or in or out a step
  // at a click; ctPoint, ctLine and ctCurve add objects where
  // the snap points; ctPiece makes a piece of the region clicked; ctNotch adds
  // or removes a notch on a piece's seam line; ctSeam picks the edges of the
  // two sides of a seam; ctText places a note, hung from what it snaps to;
  // ctCallout takes what its tip points at, then where its text goes
  TCanvasTool = (ctSelect, ctZoom, ctPoint, ctLine, ctCurve, ctCircle, ctRectangle, ctPiece, ctNotch, ctSeam, ctText, ctCallout);

  // How the tool is offered: its key in Sloper.Core.Shortcuts, its toolbar
  // icon, its menu caption, and the hint the status bar shows while it is in use
  TCanvasToolInfo = record
    Command: TKeyCommand;
    Icon: TAppIcon;
    Caption: string;
    Hint: string;
  end;

const
  // Screen pixels around the pointer that a tool snaps to or picks from
  SNAP_RADIUS = 8;
  // The tools as the API names them
  CANVAS_TOOL_NAMES: array[TCanvasTool] of string = ('select', 'zoom', 'point', 'line', 'curve', 'circle', 'rectangle', 'piece',
    'notch', 'seam', 'text', 'callout');

function CanvasToolInfo(Tool: TCanvasTool): TCanvasToolInfo;

resourcestring
  rsToolSelect = 'Select';
  rsToolSelectHint = 'Select: click to select, drag a point to move it';
  rsToolZoom = 'Zoom';
  rsToolZoomHint = 'Zoom: drag a box to zoom to it, click to zoom in, Shift+click to zoom out';
  rsToolPoint = 'Point';
  rsToolPointHint = 'Point: click to add a point where it snaps';
  rsToolLine = 'Line';
  rsToolLineHint = 'Line: click the start, then the end; Escape stops';
  rsToolCurve = 'Curve';
  rsToolCurveHint = 'Curve: click the start, then the end; Shift+click carries it on as one path; Escape stops';
  rsToolCircle = 'Circle';
  rsToolCircleHint = 'Circle: click the centre, then a point on the rim; Escape stops';
  rsToolRectangle = 'Rectangle';
  rsToolRectangleHint = 'Rectangle: click one corner, then the opposite one; Escape stops';
  rsToolPiece = 'Piece';
  rsToolPieceHint = 'Piece: click inside a closed outline';
  rsToolNotch = 'Notch';
  rsToolNotchHint = 'Notch: click a piece''s edge to add a notch, or a notch to remove it';
  rsToolSeam = 'Seam';
  rsToolSeamHint = 'Seam: click edges for side A, Tab moves to side B, Enter makes the seam';
  rsToolText = 'Text';
  rsToolTextHint = 'Text: click to place a note; it hangs from the point, edge or piece it snaps to';
  rsToolCallout = 'Callout';
  rsToolCalloutHint = 'Callout: click what it points at, then where its text goes; Escape stops';
  // The undo step of the Point tool's click
  rsToolAddPoint = 'Add point';

implementation

function CanvasToolInfo(Tool: TCanvasTool): TCanvasToolInfo;

  function Info(Command: TKeyCommand; Icon: TAppIcon; const ACaption, AHint: string): TCanvasToolInfo;
  begin
    Result.Command := Command;
    Result.Icon := Icon;
    Result.Caption := ACaption;
    Result.Hint := AHint;
  end;

begin
  case Tool of
    ctSelect: Result := Info(kcToolSelect, aiSelect, rsToolSelect, rsToolSelectHint);
    ctZoom: Result := Info(kcToolZoom, aiZoomArea, rsToolZoom, rsToolZoomHint);
    ctPoint: Result := Info(kcToolPoint, aiPoint, rsToolPoint, rsToolPointHint);
    ctLine: Result := Info(kcToolLine, aiLine, rsToolLine, rsToolLineHint);
    ctCurve: Result := Info(kcToolCurve, aiCurve, rsToolCurve, rsToolCurveHint);
    ctCircle: Result := Info(kcToolCircle, aiCircle, rsToolCircle, rsToolCircleHint);
    ctRectangle: Result := Info(kcToolRectangle, aiRectangle, rsToolRectangle, rsToolRectangleHint);
    ctPiece: Result := Info(kcToolPiece, aiPiece, rsToolPiece, rsToolPieceHint);
    ctNotch: Result := Info(kcToolNotch, aiNotch, rsToolNotch, rsToolNotchHint);
    ctSeam: Result := Info(kcToolSeam, aiSeam, rsToolSeam, rsToolSeamHint);
    ctText: Result := Info(kcToolText, aiText, rsToolText, rsToolTextHint);
    ctCallout: Result := Info(kcToolCallout, aiCallout, rsToolCallout, rsToolCalloutHint);
  end;
end;

end.
