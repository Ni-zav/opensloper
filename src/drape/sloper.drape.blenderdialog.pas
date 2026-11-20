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

// The drape app's window while Blender drapes an export: Blender runs on a
// thread of its own (Sloper.Output.BlenderRun), the window shows the frame
// it is at and can cancel it, and once the result is saved it opens the
// .blend in Blender, or shows what went wrong.
unit Sloper.Drape.BlenderDialog;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, Sloper.Output.DrapeExport;

// Runs Blender on the export's script, frames Frames, while the window shows
// how far it is; modal. True when Blender saved the result.
function DrapeInBlender(AOwner: TComponent; const Blender: string; const Files: TDrapeExportFiles; Frames: integer): boolean;

resourcestring
  rsBlenderTitle = 'Drape in Blender';
  rsBlenderStarting = 'Starting Blender...';
  rsBlenderStep = 'Blender: %s';
  rsBlenderFrame = 'Simulating frame %d of %d';
  rsBlenderDone = 'Draped in %s. Blender saved %s.';
  rsBlenderStopped = 'Cancelled. Nothing was saved.';
  rsBlenderFailed = 'Blender stopped with code %d before it finished. Its last lines:';
  rsBlenderOpen = 'Open in Blender';
  rsBlenderCancel = 'Cancel';
  rsBlenderClose = 'Close';
  rsBlenderOpenFailed = 'Could not start Blender: %s';
  rsSeconds = '%d s';
  rsMinutes = '%d min %d s';

implementation

uses
  SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, Process, Sloper.UI.Spacing, Sloper.Output.BlenderRun;

const
  DIALOG_WIDTH = 520;
  // Lines of Blender's own shown when it fails
  TAIL_HEIGHT = 180;
  SECONDS_PER_MINUTE = 60;
  MS_PER_SECOND = 1000;

type
  TBlenderDialog = class;

  // Runs Blender, passing its lines to the window on the main thread
  TBlenderThread = class(TThread)
  private
    FDialog: TBlenderDialog;
    FBlender, FScript: string;
    FFrames: integer;
    FLine: string;
    procedure Line(const Text: string);
    procedure ShowLine;
    procedure ShowEnd;
  protected
    procedure Execute; override;
  public
    // Set from the main thread to end Blender early
    Stop: boolean;
    Outcome: TBlenderRun;
    ErrorMessage: string;
    // Whether Blender started at all
    Ran: boolean;
    constructor Create(ADialog: TBlenderDialog; const ABlender, AScript: string; AFrames: integer);
  end;

  TBlenderDialog = class(TForm)
  private
    FStatus: TLabel;
    FProgress: TProgressBar;
    FTail: TMemo;
    FCancelButton, FOpenButton: TButton;
    FThread: TBlenderThread;
    FBlender, FBlend, FScript: string;
    // Closing: the thread's last call must not touch the window
    FClosing: boolean;
    FFrames: integer;
    FStartTick: QWord;
    FSaved: boolean;
    procedure CancelClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CloseAsked(Sender: TObject; var CanClose: boolean);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ABlender: string; const Files: TDrapeExportFiles; AFrames: integer);
    destructor Destroy; override;
    procedure ShowProgress(const Line: string);
    procedure Finished;
  end;

function ElapsedText(Milliseconds: QWord): string;
var
  Seconds: integer;
begin
  Seconds := Milliseconds div MS_PER_SECOND;
  if Seconds < SECONDS_PER_MINUTE then
    Result := Format(rsSeconds, [Seconds])
  else
    Result := Format(rsMinutes, [Seconds div SECONDS_PER_MINUTE, Seconds mod SECONDS_PER_MINUTE]);
end;

constructor TBlenderThread.Create(ADialog: TBlenderDialog; const ABlender, AScript: string; AFrames: integer);
begin
  FDialog := ADialog;
  FBlender := ABlender;
  FScript := AScript;
  FFrames := AFrames;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TBlenderThread.Execute;
begin
  Ran := RunBlender(FBlender, FScript, FFrames, @Line, @Stop, Outcome, ErrorMessage);
  Synchronize(@ShowEnd);
end;

procedure TBlenderThread.Line(const Text: string);
begin
  FLine := Text;
  Synchronize(@ShowLine);
end;

procedure TBlenderThread.ShowLine;
begin
  FDialog.ShowProgress(FLine);
end;

procedure TBlenderThread.ShowEnd;
begin
  FDialog.Finished;
end;

constructor TBlenderDialog.CreateDialog(AOwner: TComponent; const ABlender: string; const Files: TDrapeExportFiles; AFrames: integer);
var
  Buttons: TPanel;
begin
  inherited CreateNew(AOwner);
  Caption := rsBlenderTitle;
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  AutoSize := True;
  Constraints.MinWidth := Scale96ToForm(DIALOG_WIDTH);
  FBlender := ABlender;
  FBlend := Files.Blend;
  FScript := Files.Script;
  FFrames := AFrames;
  OnCloseQuery := @CloseAsked;
  FStatus := TLabel.Create(Self);
  FStatus.Caption := rsBlenderStarting;
  FStatus.WordWrap := True;
  FStatus.Align := alTop;
  FStatus.BorderSpacing.Around := ControlGap;
  FStatus.Parent := Self;
  FProgress := TProgressBar.Create(Self);
  FProgress.Max := AFrames;
  FProgress.Align := alTop;
  FProgress.Top := FStatus.Top + FStatus.Height;
  FProgress.BorderSpacing.Around := ControlGap;
  FProgress.Parent := Self;
  FTail := TMemo.Create(Self);
  FTail.ReadOnly := True;
  FTail.ScrollBars := ssAutoBoth;
  FTail.WordWrap := False;
  FTail.Height := Scale96ToForm(TAIL_HEIGHT);
  FTail.Align := alTop;
  FTail.Top := FProgress.Top + FProgress.Height;
  FTail.BorderSpacing.Around := ControlGap;
  FTail.Visible := False;
  FTail.Parent := Self;
  Buttons := TPanel.Create(Self);
  Buttons.BevelOuter := bvNone;
  Buttons.AutoSize := True;
  Buttons.Align := alTop;
  Buttons.Top := FTail.Top + FTail.Height;
  Buttons.BorderSpacing.Around := ControlGap;
  Buttons.Parent := Self;
  FCancelButton := TButton.Create(Self);
  FCancelButton.Caption := rsBlenderCancel;
  FCancelButton.AutoSize := True;
  FCancelButton.Align := alRight;
  FCancelButton.BorderSpacing.Left := ControlGap;
  FCancelButton.Cancel := True;
  FCancelButton.OnClick := @CancelClick;
  FCancelButton.Parent := Buttons;
  FOpenButton := TButton.Create(Self);
  FOpenButton.Caption := rsBlenderOpen;
  FOpenButton.AutoSize := True;
  FOpenButton.Align := alRight;
  FOpenButton.Visible := False;
  FOpenButton.Default := True;
  FOpenButton.OnClick := @OpenClick;
  FOpenButton.Parent := Buttons;
end;

destructor TBlenderDialog.Destroy;
begin
  if Assigned(FThread) then
  begin
    FClosing := True;
    FThread.Stop := True;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  inherited Destroy;
end;

procedure TBlenderDialog.DoShow;
begin
  inherited DoShow;
  if Assigned(FThread) then
    Exit;
  FStartTick := GetTickCount64;
  FThread := TBlenderThread.Create(Self, FBlender, FScript, FFrames);
end;

procedure TBlenderDialog.ShowProgress(const Line: string);
var
  Progress: string;
  Frame, Total: integer;
begin
  if FClosing or not BlenderProgress(Line, Progress) then
    Exit;
  if BlenderFrame(Progress, Frame, Total) then
  begin
    FProgress.Max := Total;
    FProgress.Position := Frame;
    FStatus.Caption := Format(rsBlenderFrame, [Frame, Total]);
  end
  else
    FStatus.Caption := Format(rsBlenderStep, [Progress]);
end;

procedure TBlenderDialog.Finished;
var
  Line: string;
begin
  if FClosing then
    Exit;
  FCancelButton.Caption := rsBlenderClose;
  if not FThread.Ran then
    FStatus.Caption := FThread.ErrorMessage
  else if FThread.Outcome.Stopped then
    FStatus.Caption := rsBlenderStopped
  else if FThread.Outcome.ExitCode <> 0 then
  begin
    FStatus.Caption := Format(rsBlenderFailed, [FThread.Outcome.ExitCode]);
    FTail.Lines.Clear;
    for Line in FThread.Outcome.Tail do
      FTail.Lines.Add(Line);
    FTail.Visible := True;
  end
  else
  begin
    FSaved := True;
    FProgress.Position := FProgress.Max;
    FStatus.Caption := Format(rsBlenderDone, [ElapsedText(GetTickCount64 - FStartTick), ExtractFileName(FBlend)]);
    FOpenButton.Visible := True;
    FOpenButton.SetFocus;
  end;
end;

procedure TBlenderDialog.CancelClick(Sender: TObject);
begin
  Close;
end;

// Stops a running Blender before the window goes
procedure TBlenderDialog.CloseAsked(Sender: TObject; var CanClose: boolean);
begin
  if Assigned(FThread) and not FThread.Finished then
  begin
    FClosing := True;
    FThread.Stop := True;
    FThread.WaitFor;
  end;
  CanClose := True;
end;

// Blender on its own, with the result, left running when this app closes
procedure TBlenderDialog.OpenClick(Sender: TObject);
var
  Runner: TProcess;
begin
  Runner := TProcess.Create(nil);
  try
    Runner.Executable := FBlender;
    Runner.Parameters.Add(FBlend);
    try
      Runner.Execute;
    except
      on Failure: EProcess do
        MessageDlg(Format(rsBlenderOpenFailed, [Failure.Message]), mtError, [mbOK], 0);
    end;
  finally
    FreeAndNil(Runner);
  end;
  Close;
end;

function DrapeInBlender(AOwner: TComponent; const Blender: string; const Files: TDrapeExportFiles; Frames: integer): boolean;
var
  Dialog: TBlenderDialog;
begin
  Dialog := TBlenderDialog.CreateDialog(AOwner, Blender, Files, Frames);
  try
    Dialog.ShowModal;
    Result := Dialog.FSaved;
  finally
    FreeAndNil(Dialog);
  end;
end;

end.
