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

// What the Claude tab works on in the publish and drape apps: their open
// layout or drape, with the tools of Sloper.API.LayoutServer and
// Sloper.API.DrapeServer. The design app's is in Sloper.UI.AssistantPanel.
unit Sloper.UI.AssistantHosts;

{$mode ObjFPC}{$H+}

interface

uses
  fpjson, Sloper.API.Methods, Sloper.API.LayoutServer, Sloper.API.DrapeServer, Sloper.Output.LayoutDocument,
  Sloper.Document.DrapeDocument, Sloper.UI.AssistantPanel;

type
  TLayoutAssistantHost = class(TAssistantHost)
  private
    FDocument: TLayoutDocument;
    FServer: TLayoutApiServer;
  public
    constructor Create(ADocument: TLayoutDocument);
    destructor Destroy; override;
    function Ready: boolean; override;
    function Generation: integer; override;
    function Methods: TApiMethodArray; override;
    function SystemPrompt: string; override;
    function Welcome(SharesMeasurements: boolean): string; override;
    function CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData; override;
  end;

  TDrapeAssistantHost = class(TAssistantHost)
  private
    FDocument: TDrapeDocument;
    FServer: TDrapeApiServer;
  public
    constructor Create(ADocument: TDrapeDocument);
    destructor Destroy; override;
    function Ready: boolean; override;
    function Generation: integer; override;
    function Methods: TApiMethodArray; override;
    function SystemPrompt: string; override;
    function Welcome(SharesMeasurements: boolean): string; override;
    function CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData; override;
  end;

resourcestring
  rsLayoutWelcome = 'Ask Claude to arrange the layout, or why something is wrong: "pack the pieces on 150 cm material", ' +
    '"why does the front overlap the facing?". Each change is one step you can undo. Claude cannot save, export or print.';
  rsLayoutPrivacy = 'What goes to Anthropic: your questions, the layout''s settings and notes, its pieces'' names, places ' +
    'and sizes, and images of the sheet. File names are sent; folders, the measurement files and their values are never ' +
    'sent, though the pieces'' sizes are worked out from them.';
  rsDrapeWelcome = 'Ask Claude to place the pieces round the body, or why something is wrong: "wrap the back round to ' +
    'the back of the body", "which seams are left open?". Each change is one step you can undo. Claude cannot save or ' +
    'run Blender.';
  rsDrapePrivacy = 'What goes to Anthropic: your questions, the pieces'' names and placements, the drape''s problems, and ' +
    'images of the body and pieces. File names are sent; folders, the measurement files and their values are never ' +
    'sent, though the body''s shape and the pieces'' sizes are worked out from them.';

implementation

uses
  SysUtils, Sloper.UI.Automation;

constructor TLayoutAssistantHost.Create(ADocument: TLayoutDocument);
begin
  inherited Create;
  FDocument := ADocument;
  FServer := TLayoutApiServer.Create(ADocument);
  FServer.ChangePrefix := rsClaudeChange;
end;

destructor TLayoutAssistantHost.Destroy;
begin
  FreeAndNil(FServer);
  inherited Destroy;
end;

function TLayoutAssistantHost.Ready: boolean;
begin
  Result := Assigned(FDocument);
end;

function TLayoutAssistantHost.Generation: integer;
begin
  Result := FDocument.Generation;
end;

function TLayoutAssistantHost.Methods: TApiMethodArray;
begin
  Result := LayoutMethods;
end;

function TLayoutAssistantHost.SystemPrompt: string;
begin
  Result := LayoutSystemPrompt;
end;

function TLayoutAssistantHost.Welcome(SharesMeasurements: boolean): string;
begin
  Result := rsLayoutWelcome + LineEnding + LineEnding + rsLayoutPrivacy;
end;

function TLayoutAssistantHost.CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData;
begin
  Result := FServer.CallMethod(ToolName, Input);
end;

constructor TDrapeAssistantHost.Create(ADocument: TDrapeDocument);
begin
  inherited Create;
  FDocument := ADocument;
  FServer := TDrapeApiServer.Create(ADocument);
  FServer.ChangePrefix := rsClaudeChange;
end;

destructor TDrapeAssistantHost.Destroy;
begin
  FreeAndNil(FServer);
  inherited Destroy;
end;

function TDrapeAssistantHost.Ready: boolean;
begin
  Result := Assigned(FDocument);
end;

function TDrapeAssistantHost.Generation: integer;
begin
  Result := FDocument.Generation;
end;

function TDrapeAssistantHost.Methods: TApiMethodArray;
begin
  Result := DrapeMethods;
end;

function TDrapeAssistantHost.SystemPrompt: string;
begin
  Result := DrapeSystemPrompt;
end;

function TDrapeAssistantHost.Welcome(SharesMeasurements: boolean): string;
begin
  Result := rsDrapeWelcome + LineEnding + LineEnding + rsDrapePrivacy;
end;

function TDrapeAssistantHost.CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData;
begin
  Result := FServer.CallMethod(ToolName, Input);
end;

end.
