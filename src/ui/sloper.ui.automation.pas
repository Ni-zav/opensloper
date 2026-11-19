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

// The design window's automation mode: an AI assistant, any MCP client such
// as Claude Code, works through opensloper-cli serve --connect on the
// pattern open in the window. The user turns it on, is asked before the
// assistant first reads or changes anything, and before a file is written
// outside the pattern's folder; each change is one undo step labelled
// "Assistant: ...", and the user can disconnect at any time.
unit Sloper.UI.Automation;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Sloper.Document.PatternDocument, Sloper.API.Server, Sloper.API.Rpc, Sloper.API.Listener;

type
  TAutomationState = (asOff, asListening, asConnected);

  TAutomation = class
  private
    FApi: TApiServer;
    FListener: TAutomationListener;
    FConnected: boolean;
    FAllowedForSession, FAllowedForClient: boolean;
    FOnChange: TNotifyEvent;
    function HandleRequest(const Line: string): string;
    procedure ClientChanged(Connected: boolean);
    function ConfirmWrite(const Path: string): boolean;
    // Asks the user, once a connection or once a session
    function Allowed: boolean;
    procedure Changed;
    function GetSharesMeasurements: boolean;
    procedure SetSharesMeasurements(Value: boolean);
  public
    // WindowState answers ui_state
    constructor Create(ADocument: TPatternDocument; AWindowState: TApiWindowState);
    destructor Destroy; override;
    function Start(out ErrorMessage: string): boolean;
    procedure Stop;
    // Drops the client; it may connect again, and is asked again
    procedure Disconnect;
    function State: TAutomationState;
    // After the state changes, and after each request the assistant makes
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    // Whether a connected assistant may read and change the measurement
    // values, from the preferences
    property SharesMeasurements: boolean read GetSharesMeasurements write SetSharesMeasurements;
  end;

// Asks before Who (Claude in the side panel, or an assistant connected)
// writes Path outside the folder of the pattern open in Document
function ConfirmAssistantWrite(Document: TPatternDocument; const Who, Path: string): boolean;

resourcestring
  // Undo steps of the in-app Claude, and of an assistant connected
  rsClaudeChange = 'Claude: ';
  rsConnectedChange = 'Assistant: ';
  rsConnectedWho = 'An assistant';
  rsConnectedConsentTitle = 'AI Assistant';
  rsConnectedConsent = 'Allow the AI assistant connected through opensloper-cli to read and edit this pattern?' + LineEnding +
    LineEnding + 'Each change is one step you can undo, labelled "Assistant".';
  rsConnectedAllowOnce = 'Allow Once';
  rsConnectedAllowSession = 'Allow Until I Close OpenSloper';
  rsConnectedDeny = 'Don''t Allow';
  rsConnectedDenied = 'The user did not allow the assistant to work on this pattern';
  rsAssistantWriteTitle = '%s wants to write a file';
  rsAssistantWrite = '%s wants to write' + LineEnding + '%s' + LineEnding + 'outside the pattern''s folder. Allow it?';

implementation

uses
  Controls, Dialogs, fpjson, Sloper.Core.JSON;

constructor TAutomation.Create(ADocument: TPatternDocument; AWindowState: TApiWindowState);
begin
  inherited Create;
  FApi := TApiServer.CreateFor(ADocument);
  FApi.ChangePrefix := rsConnectedChange;
  FApi.OpensFiles := False;
  // What it reads goes on to Claude, or another assistant (see Privacy in the design)
  FApi.WithholdsFiles := True;
  FApi.OnConfirmWrite := @ConfirmWrite;
  FApi.OnWindowState := AWindowState;
end;

function TAutomation.GetSharesMeasurements: boolean;
begin
  Result := FApi.SharesMeasurements;
end;

procedure TAutomation.SetSharesMeasurements(Value: boolean);
begin
  FApi.SharesMeasurements := Value;
end;

destructor TAutomation.Destroy;
begin
  FOnChange := nil;
  Stop;
  FreeAndNil(FApi);
  inherited Destroy;
end;

function TAutomation.Start(out ErrorMessage: string): boolean;
begin
  ErrorMessage := '';
  if Assigned(FListener) then
    Exit(True);
  FListener := TAutomationListener.Start(@HandleRequest, @ClientChanged, True, ErrorMessage);
  Result := Assigned(FListener);
  Changed;
end;

procedure TAutomation.Stop;
begin
  FreeAndNil(FListener);
  FConnected := False;
  FAllowedForSession := False;
  Changed;
end;

procedure TAutomation.Disconnect;
begin
  if Assigned(FListener) then
    FListener.Disconnect;
end;

function TAutomation.State: TAutomationState;
begin
  if not Assigned(FListener) then
    Result := asOff
  else if FConnected then
    Result := asConnected
  else
    Result := asListening;
end;

procedure TAutomation.Changed;
begin
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TAutomation.ClientChanged(Connected: boolean);
begin
  FConnected := Connected;
  FAllowedForClient := False;
  Changed;
end;

function TAutomation.Allowed: boolean;
begin
  if FAllowedForSession or FAllowedForClient then
    Exit(True);
  case QuestionDlg(rsConnectedConsentTitle, rsConnectedConsent, mtConfirmation, [mrYes, rsConnectedAllowOnce, mrAll,
      rsConnectedAllowSession, mrNo, rsConnectedDeny, 'IsDefault'], 0) of
    mrYes: FAllowedForClient := True;
    mrAll: FAllowedForSession := True;
  end;
  Result := FAllowedForSession or FAllowedForClient;
end;

// On the main thread, between the user's own edits
function TAutomation.HandleRequest(const Line: string): string;
var
  Request: TJSONObject;
  Err: string;
begin
  if not Allowed then
  begin
    Result := '';
    if ParseJSONObject(Line, Request, Err) then
    try
      if Assigned(Request.Find('id')) then
        Result := RpcErrorResponse(Request.Find('id'), RPC_REFUSED, rsConnectedDenied);
    finally
      FreeAndNil(Request);
    end;
    Disconnect;
    Exit;
  end;
  Result := FApi.HandleLine(Line);
  Changed;
end;

// Writing beside the pattern is what saving it means; anywhere else is asked
function ConfirmAssistantWrite(Document: TPatternDocument; const Who, Path: string): boolean;
var
  PatternFile: string;
begin
  PatternFile := Document.FileName;
  if (PatternFile <> '') and SameFileName(ExtractFileDir(ExpandFileName(PatternFile)), ExtractFileDir(Path)) then
    Exit(True);
  Result := QuestionDlg(Format(rsAssistantWriteTitle, [Who]), Format(rsAssistantWrite, [Who, Path]), mtWarning,
    [mrYes, mrNo, 'IsDefault'], 0) = mrYes;
end;

function TAutomation.ConfirmWrite(const Path: string): boolean;
begin
  Result := ConfirmAssistantWrite(FApi.Document, rsConnectedWho, Path);
end;

end.
