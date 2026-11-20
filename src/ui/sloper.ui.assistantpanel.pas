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

// The Claude section of the side panel: the user asks in their own words and
// Claude works on what the window has open, with that app's tools: in the
// design app the Automation API's methods on the pattern, in the publish and
// drape apps their own (see Sloper.UI.AssistantHosts). A host says which. The
// conversation runs on a thread of its own, so the window stays usable; each
// tool call comes back to the main thread and is one undo step labelled
// "Claude: ...", as in live editing.
unit Sloper.UI.AssistantPanel;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Controls, ExtCtrls, StdCtrls, fpjson, Sloper.Document.PatternDocument, Sloper.API.Server,
  Sloper.API.Methods, Sloper.Assistant.Conversation, Sloper.Assistant.Http;

type
  TAssistantPanel = class;

  // What the Claude tab works on in one app: its tools, what Claude is told,
  // and what the tab says before the first question. The panel owns it.
  TAssistantHost = class
  public
    // Something is open to work on
    function Ready: boolean; virtual; abstract;
    // Changes when the window opens another file, whose IDs and indexes are
    // not the ones Claude learned
    function Generation: integer; virtual; abstract;
    function Methods: TApiMethodArray; virtual; abstract;
    function SystemPrompt: string; virtual; abstract;
    // The opening text, and what goes to Anthropic
    function Welcome(SharesMeasurements: boolean): string; virtual; abstract;
    // A new conversation starts on the file as it is now
    procedure Restart; virtual;
    // On the main thread. Raises EApiError when refused; the reply is the caller's.
    function CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData; virtual; abstract;
  end;

  // The design app's: the Automation API on the open pattern
  TPatternAssistantHost = class(TAssistantHost)
  private
    FDocument: TPatternDocument;
    FApi: TApiServer;
    FWindowState: TApiWindowState;
    function ConfirmWrite(const Path: string): boolean;
  public
    constructor Create(ADocument: TPatternDocument);
    destructor Destroy; override;
    function Ready: boolean; override;
    function Generation: integer; override;
    function Methods: TApiMethodArray; override;
    function SystemPrompt: string; override;
    function Welcome(SharesMeasurements: boolean): string; override;
    procedure Restart; override;
    function CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData; override;
    property WindowState: TApiWindowState read FWindowState write FWindowState;
  end;

  // Runs one question; its events come back to the panel on the main thread
  TAssistantWorker = class(TThread)
  private
    FPanel: TAssistantPanel;
    FConversation: TAssistantConversation;
    FQuestion, FProblem, FText: string;
    FAnswered: boolean;
    FLock: TRTLCriticalSection;
    FToolName: string;
    FToolInput: TJSONObject;
    FToolOutput: TJSONArray;
    FToolError: boolean;
    procedure Text(const AText: string);
    procedure Note(const AText: string);
    function Tool(const ToolName: string; Input: TJSONObject; out IsError: boolean): TJSONArray;
    procedure FlushText;
    procedure CallTool;
    procedure Finished;
  protected
    procedure Execute; override;
  public
    constructor Create(APanel: TAssistantPanel; AConversation: TAssistantConversation; const AQuestion: string);
    destructor Destroy; override;
  end;

  TAssistantPanel = class(TPanel)
  private
    FDocument: TPatternDocument;
    FHost: TAssistantHost;
    FConversation: TAssistantConversation;
    // The conversation's, which owns it; given the key at each question
    FTransport: THttpsTransport;
    FWorker: TAssistantWorker;
    // The worker answered and is ending; freed before the next question
    FWorkerDone: boolean;
    // The host's Generation the conversation began on; New or Open in the
    // window ends the conversation, whose IDs belong to that file
    FGeneration: integer;
    FTranscript, FInput: TMemo;
    FSendButton, FStopButton, FNewButton: TButton;
    FWindowState: TApiWindowState;
    // An API key is set, in Preferences or ANTHROPIC_API_KEY
    FHasKey: boolean;
    // The transcript is still the opening text, with nothing asked
    FFresh: boolean;
    FSharesMeasurements: boolean;
    procedure SetSharesMeasurements(Value: boolean);
    procedure ShowOpening;
    procedure SetDocument(Value: TPatternDocument);
    procedure SetHost(Value: TAssistantHost);
    procedure SetWindowState(Value: TApiWindowState);
    function HostReady: boolean;
    procedure SendClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure InputKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure Append(const AText: string);
    procedure StopWorker;
    procedure UpdateButtons;
    function Running: boolean;
    procedure Build;
  protected
    procedure SetParent(NewParent: TWinControl); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // On the main thread: runs a tool for Claude on the document
    function RunTool(const ToolName: string; Input: TJSONObject; out IsError: boolean): TJSONArray;
    procedure ShowText(const AText: string);
    procedure ShowNote(const AText: string);
    procedure QuestionDone(Answered: boolean; const Problem: string);
    // Reads again whether a key is set, after Preferences; without one the
    // question and buttons are off and the panel says where to set it
    procedure KeyChanged;
    // Puts the cursor in the question, when one can be asked
    procedure FocusQuestion;
    property HasKey: boolean read FHasKey;
    // The design app's: works on the pattern; nil stops any conversation in progress
    property Document: TPatternDocument read FDocument write SetDocument;
    // Another app's: what the tab works on, which the panel takes over; nil
    // stops any conversation in progress
    property Host: TAssistantHost read FHost write SetHost;
    // Answers ui_state, in the design app
    property WindowState: TApiWindowState read FWindowState write SetWindowState;
    // Whether Claude may read and change the measurement values, from the
    // preferences; True unless set. Takes effect at the next question.
    property SharesMeasurements: boolean read FSharesMeasurements write SetSharesMeasurements;
  end;

resourcestring
  rsAssistantSend = 'Ask';
  rsAssistantStop = 'Stop';
  rsAssistantNew = 'New Conversation';
  rsAssistantWelcome = 'Ask Claude to draft or change the pattern, or why something is wrong: "add 2 cm ease at the hip", ' +
    '"why is point C invalid?". Each change is one step you can undo.';
  rsAssistantPrivacyShared = 'What goes to Anthropic: your questions, the pattern''s names, formulas, values and drawings, ' +
    'and the measurement values, which Claude can also change. Folders and the measurement file''s name are never sent. ' +
    'To keep the measurement values back, turn off "Let AI assistants read the measurements" in Edit → Preferences, General.';
  rsAssistantPrivacyWithheld = 'What goes to Anthropic: your questions and the pattern''s names, formulas, values and ' +
    'drawings. The measurement values are kept back, as set in Edit → Preferences, but the pattern''s sizes are worked ' +
    'out from them. Folders and the measurement file''s name are never sent.';
  rsAssistantNoKeyYet = 'Claude needs your Anthropic API key. Set it in Edit → Preferences, General.';
  rsAssistantYou = 'You: %s';
  rsAssistantClaude = 'Claude: ';
  // Who asks to write a file
  rsAssistantWho = 'Claude';
  rsAssistantTool = '  › %s';
  rsAssistantProblem = '(%s)';
  rsAssistantNoPattern = 'Nothing is open';
  rsAssistantAnotherPattern = 'Another file is open now, so this question was stopped: what Claude knew was about the ' +
    'one open before.';
  rsAssistantNewForPattern = '(Another file is open, so this is a new conversation.)';

implementation

uses
  LCLType, Sloper.Assistant.Key, Sloper.UI.Automation, Sloper.UI.Spacing;

const
  INPUT_HEIGHT96 = 64;

constructor TAssistantWorker.Create(APanel: TAssistantPanel; AConversation: TAssistantConversation; const AQuestion: string);
begin
  FPanel := APanel;
  FConversation := AConversation;
  FQuestion := AQuestion;
  InitCriticalSection(FLock);
  FConversation.OnText := @Text;
  FConversation.OnNote := @Note;
  FConversation.OnTool := @Tool;
  inherited Create(False);
end;

destructor TAssistantWorker.Destroy;
begin
  DoneCriticalSection(FLock);
  inherited Destroy;
end;

procedure TAssistantWorker.Execute;
begin
  try
    FAnswered := FConversation.Ask(FQuestion, FProblem);
  except
    on Failure: Exception do
    begin
      FAnswered := False;
      FProblem := Failure.Message;
    end;
  end;
  Synchronize(@FlushText);
  Synchronize(@Finished);
end;

// Text piles up here and the main thread takes it, so a fast stream does
// not queue a call per word
procedure TAssistantWorker.Text(const AText: string);
var
  First: boolean;
begin
  EnterCriticalSection(FLock);
  try
    First := FText = '';
    FText := FText + AText;
  finally
    LeaveCriticalSection(FLock);
  end;
  if First then
    Queue(@FlushText);
end;

procedure TAssistantWorker.FlushText;
var
  Taken: string;
begin
  EnterCriticalSection(FLock);
  try
    Taken := FText;
    FText := '';
  finally
    LeaveCriticalSection(FLock);
  end;
  if Taken <> '' then
    FPanel.ShowText(Taken);
end;

procedure TAssistantWorker.Note(const AText: string);
begin
  FToolName := AText;
  Synchronize(@CallTool);
end;

function TAssistantWorker.Tool(const ToolName: string; Input: TJSONObject; out IsError: boolean): TJSONArray;
begin
  Synchronize(@FlushText);
  FToolName := ToolName;
  FToolInput := Input;
  FToolOutput := nil;
  Synchronize(@CallTool);
  IsError := FToolError;
  Result := FToolOutput;
end;

procedure TAssistantWorker.CallTool;
begin
  if Assigned(FToolInput) then
    FToolOutput := FPanel.RunTool(FToolName, FToolInput, FToolError)
  else
    FPanel.ShowNote(FToolName);
  FToolInput := nil;
end;

procedure TAssistantWorker.Finished;
begin
  FPanel.QuestionDone(FAnswered, FProblem);
end;

procedure TAssistantHost.Restart;
begin
end;

constructor TPatternAssistantHost.Create(ADocument: TPatternDocument);
begin
  inherited Create;
  FDocument := ADocument;
  Restart;
end;

destructor TPatternAssistantHost.Destroy;
begin
  FreeAndNil(FApi);
  inherited Destroy;
end;

function TPatternAssistantHost.Ready: boolean;
begin
  Result := Assigned(FDocument);
end;

function TPatternAssistantHost.Generation: integer;
begin
  Result := FDocument.Generation;
end;

function TPatternAssistantHost.Methods: TApiMethodArray;
begin
  Result := ApiMethods;
end;

function TPatternAssistantHost.SystemPrompt: string;
begin
  Result := AssistantSystemPrompt;
end;

function TPatternAssistantHost.Welcome(SharesMeasurements: boolean): string;
begin
  if SharesMeasurements then
    Result := rsAssistantWelcome + LineEnding + LineEnding + rsAssistantPrivacyShared
  else
    Result := rsAssistantWelcome + LineEnding + LineEnding + rsAssistantPrivacyWithheld;
end;

// The API server for the document, starting from its pattern as it is now
procedure TPatternAssistantHost.Restart;
begin
  FreeAndNil(FApi);
  FApi := TApiServer.CreateFor(FDocument);
  FApi.ChangePrefix := rsClaudeChange;
  FApi.OpensFiles := False;
  FApi.WithholdsFiles := True;
  FApi.OnConfirmWrite := @ConfirmWrite;
end;

function TPatternAssistantHost.ConfirmWrite(const Path: string): boolean;
begin
  Result := ConfirmAssistantWrite(FDocument, rsAssistantWho, Path);
end;

function TPatternAssistantHost.CallTool(const ToolName: string; Input: TJSONObject; SharesMeasurements: boolean): TJSONData;
begin
  FApi.SharesMeasurements := SharesMeasurements;
  FApi.OnWindowState := FWindowState;
  Result := FApi.CallMethod(ToolName, Input);
end;

constructor TAssistantPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  FSharesMeasurements := True;
end;

// Once on a form, as sizes scale with the screen
procedure TAssistantPanel.SetParent(NewParent: TWinControl);
begin
  inherited SetParent(NewParent);
  if Assigned(NewParent) and not Assigned(FTranscript) then
    Build;
end;

procedure TAssistantPanel.Build;
var
  Buttons: TPanel;

  function NewButton(const ACaption: string; AHandler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Buttons;
    Result.Caption := ACaption;
    Result.AutoSize := True;
    Result.Align := alLeft;
    Result.OnClick := AHandler;
  end;

begin
  SpaceChildren(Self);
  FInput := TMemo.Create(Self);
  FInput.Parent := Self;
  FInput.Align := alBottom;
  FInput.Height := Scale96ToForm(INPUT_HEIGHT96);
  FInput.WordWrap := True;
  FInput.ScrollBars := ssAutoVertical;
  FInput.OnKeyDown := @InputKeyDown;
  Buttons := TPanel.Create(Self);
  Buttons.Parent := Self;
  Buttons.Align := alBottom;
  Buttons.AutoSize := True;
  Buttons.BevelOuter := bvNone;
  SpaceBetween(Buttons);
  FNewButton := NewButton(rsAssistantNew, @NewClick);
  FStopButton := NewButton(rsAssistantStop, @StopClick);
  FSendButton := NewButton(rsAssistantSend, @SendClick);
  // The buttons below the input: bottom-aligned controls stack by their Top
  Buttons.Top := FInput.Top + FInput.Height + 1;
  FTranscript := TMemo.Create(Self);
  FTranscript.Parent := Self;
  FTranscript.Align := alClient;
  FTranscript.ReadOnly := True;
  FTranscript.WordWrap := True;
  FTranscript.ScrollBars := ssAutoVertical;
  KeyChanged;
end;

// What to ask, or where to set the key first
procedure TAssistantPanel.ShowOpening;
begin
  if not FHasKey then
    FTranscript.Text := rsAssistantNoKeyYet
  else if Assigned(FHost) then
    FTranscript.Text := FHost.Welcome(FSharesMeasurements)
  else
    FTranscript.Text := rsAssistantWelcome;
  FFresh := True;
end;

procedure TAssistantPanel.SetSharesMeasurements(Value: boolean);
begin
  if Value = FSharesMeasurements then
    Exit;
  FSharesMeasurements := Value;
  if Assigned(FTranscript) and FFresh then
    ShowOpening;
end;

procedure TAssistantPanel.KeyChanged;
var
  Source: TKeySource;
begin
  FHasKey := AssistantKey(Source) <> '';
  if not Assigned(FTranscript) then
    Exit;
  // A conversation stays on screen; only the opening text changes
  if FFresh or (FTranscript.Text = '') then
    ShowOpening;
  UpdateButtons;
end;

procedure TAssistantPanel.FocusQuestion;
begin
  if Assigned(FInput) and FInput.Enabled and FInput.CanFocus then
    FInput.SetFocus;
end;

destructor TAssistantPanel.Destroy;
begin
  Host := nil;
  FreeAndNil(FConversation);
  inherited Destroy;
end;

procedure TAssistantPanel.SetDocument(Value: TPatternDocument);
var
  PatternHost: TPatternAssistantHost;
begin
  if Value = FDocument then
    Exit;
  FDocument := Value;
  if not Assigned(Value) then
  begin
    Host := nil;
    Exit;
  end;
  PatternHost := TPatternAssistantHost.Create(Value);
  PatternHost.WindowState := FWindowState;
  Host := PatternHost;
end;

procedure TAssistantPanel.SetHost(Value: TAssistantHost);
begin
  if Value = FHost then
    Exit;
  StopWorker;
  FreeAndNil(FConversation);
  FreeAndNil(FHost);
  FHost := Value;
  if Assigned(FTranscript) and FFresh then
    ShowOpening;
  UpdateButtons;
end;

procedure TAssistantPanel.SetWindowState(Value: TApiWindowState);
begin
  FWindowState := Value;
  if FHost is TPatternAssistantHost then
    TPatternAssistantHost(FHost).WindowState := Value;
end;

function TAssistantPanel.HostReady: boolean;
begin
  Result := Assigned(FHost) and FHost.Ready;
end;

function TAssistantPanel.Running: boolean;
begin
  Result := Assigned(FWorker) and not FWorkerDone;
end;

procedure TAssistantPanel.UpdateButtons;
begin
  if not Assigned(FSendButton) then
    Exit;
  FSendButton.Enabled := FHasKey and not Running and HostReady;
  FStopButton.Enabled := Running;
  FNewButton.Enabled := FHasKey and not Running;
  // A question in progress keeps going if the key is removed meanwhile
  FInput.Enabled := FHasKey or Running;
  FInput.ReadOnly := Running;
end;

procedure TAssistantPanel.Append(const AText: string);
begin
  FTranscript.SelStart := Length(FTranscript.Text);
  FTranscript.SelText := AText;
  FTranscript.SelStart := Length(FTranscript.Text);
end;

procedure TAssistantPanel.ShowText(const AText: string);
begin
  Append(AText);
end;

procedure TAssistantPanel.ShowNote(const AText: string);
begin
  Append(LineEnding + Format(rsAssistantTool, [AText]) + LineEnding);
end;

procedure TAssistantPanel.SendClick(Sender: TObject);
var
  Question, Key: string;
  Source: TKeySource;
begin
  Question := Trim(FInput.Text);
  if (Question = '') or Running or not HostReady then
    Exit;
  Key := AssistantKey(Source);
  if Key = '' then
  begin
    // Removed since the panel last looked; the opening text says so already
    KeyChanged;
    if not FFresh then
      Append(LineEnding + LineEnding + rsAssistantNoKeyYet);
    Exit;
  end;
  FFresh := False;
  StopWorker;
  if Assigned(FConversation) and (FGeneration <> FHost.Generation) then
  begin
    FreeAndNil(FConversation);
    Append(LineEnding + LineEnding + rsAssistantNewForPattern);
  end;
  if not Assigned(FConversation) then
  begin
    FTransport := THttpsTransport.Create(Key);
    FConversation := TAssistantConversation.CreateFor(FTransport, FHost.Methods, FHost.SystemPrompt);
    FGeneration := FHost.Generation;
    FHost.Restart;
  end;
  // The key and the measurements choice as Preferences has them now, so a
  // change works at once; no request is running between questions
  FTransport.Key := Key;
  FConversation.SharesMeasurements := FSharesMeasurements;
  FInput.Clear;
  Append(LineEnding + LineEnding + Format(rsAssistantYou, [Question]) + LineEnding + LineEnding + rsAssistantClaude);
  FWorkerDone := False;
  FWorker := TAssistantWorker.Create(Self, FConversation, Question);
  UpdateButtons;
end;

procedure TAssistantPanel.StopClick(Sender: TObject);
begin
  if Assigned(FConversation) then
    FConversation.Cancel;
end;

procedure TAssistantPanel.NewClick(Sender: TObject);
begin
  if Running then
    Exit;
  StopWorker;
  FreeAndNil(FConversation);
  ShowOpening;
end;

// Enter asks; Shift+Enter starts a new line
procedure TAssistantPanel.InputKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    SendClick(nil);
  end;
end;

// Cancels a question in progress and frees the worker once it has ended
procedure TAssistantPanel.StopWorker;
begin
  if not Assigned(FWorker) then
    Exit;
  FConversation.Cancel;
  // WaitFor keeps answering the worker's Synchronize calls meanwhile
  FWorker.WaitFor;
  TThread.RemoveQueuedEvents(FWorker);
  FreeAndNil(FWorker);
  FWorkerDone := False;
end;

procedure TAssistantPanel.QuestionDone(Answered: boolean; const Problem: string);
begin
  if not Answered and (Problem <> '') then
    Append(LineEnding + Format(rsAssistantProblem, [Problem]));
  // The worker is still inside this call, so it is freed later, by StopWorker
  FWorkerDone := True;
  UpdateButtons;
end;

// The reply as tool_result content: a PNG as an image, so Claude sees the
// draft; the SVG as it is; anything else as JSON. A refusal is the API's error.
function TAssistantPanel.RunTool(const ToolName: string; Input: TJSONObject; out IsError: boolean): TJSONArray;
var
  Output: TJSONData;
begin
  ShowNote(ToolName);
  IsError := True;
  if not HostReady then
    Exit(TJSONArray.Create([TJSONObject.Create(['type', 'text', 'text', rsAssistantNoPattern])]));
  // A call still pending when the user opened another file would act on it
  // with what Claude learned from the one before; the question stops
  if FHost.Generation <> FGeneration then
  begin
    FConversation.Cancel;
    Append(LineEnding + rsAssistantAnotherPattern + LineEnding);
    Exit(TJSONArray.Create([TJSONObject.Create(['type', 'text', 'text', rsAssistantAnotherPattern])]));
  end;
  try
    Output := FHost.CallTool(ToolName, Input, FSharesMeasurements);
    try
      Result := ToolContent(Output);
      IsError := False;
    finally
      FreeAndNil(Output);
    end;
  except
    on Failure: Exception do
      Result := ToolFailureContent(Failure);
  end;
end;

end.
