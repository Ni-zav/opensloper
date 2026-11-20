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

// Running Blender on a drape export's script (data/blender/drape.py, written
// beside the export as NAME.blender.py) in the background: finding the
// program, its command line, and the script's progress, the lines it starts
// with "OpenSloper:". Described in the design document under "Drape app and
// Blender export". No LCL dependency.
unit Sloper.Output.BlenderRun;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils;

const
  // The Blender version the script is written for
  BLENDER_SCRIPT_VERSION = '5.2';
  DEFAULT_DRAPE_FRAMES = 120;
  MIN_DRAPE_FRAMES = 1;
  MAX_DRAPE_FRAMES = 10000;

type
  // Called with each line Blender writes, as it writes it
  TBlenderLineEvent = procedure(const Line: string) of object;

  TBlenderRun = record
    ExitCode: integer;
    // The last lines Blender wrote that were not progress, to show when it fails
    Tail: TStringArray;
  end;

// The Blender to run: Configured when given, else blender on the path, else
// where its installer puts it on Windows and macOS; '' when none is found
function FindBlender(const Configured: string): string;
// What Blender is given to run Script in the background, Frames frames
function BlenderParameters(const Script: string; Frames: integer): TStringArray;
// The script's progress without its prefix; False for any other line
function BlenderProgress(const Line: string; out Text: string): boolean;
// Runs Blender and waits for it; False, with a message, when it cannot start.
// A script that fails ends Blender with a code other than 0.
function RunBlender(const Blender, Script: string; Frames: integer; OnLine: TBlenderLineEvent; out Run: TBlenderRun;
  out ErrorMessage: string): boolean;

resourcestring
  rsBlenderNotStarted = 'Could not start %s: %s';

implementation

uses
  Classes, Process;

const
  PROGRESS_PREFIX = 'OpenSloper:';
  // Lines kept to show when Blender fails
  TAIL_LINES = 20;
  READ_BUFFER = 4096;
  // ms between reads while Blender has written nothing
  IDLE_WAIT = 20;
  {$IFDEF WINDOWS}
  BLENDER_NAME = 'blender.exe';
  {$ELSE}
  BLENDER_NAME = 'blender';
  {$ENDIF}

function InstalledBlender: string;
{$IF DEFINED(WINDOWS)}
var
  Found: TSearchRec;
  Folder, Best: string;
begin
  // Blender Foundation\Blender 5.2\blender.exe; the highest version wins
  Result := '';
  Folder := ConcatPaths([GetEnvironmentVariable('ProgramFiles'), 'Blender Foundation']);
  Best := '';
  if FindFirst(ConcatPaths([Folder, 'Blender*']), faDirectory, Found) = 0 then
  begin
    repeat
      if FileExists(ConcatPaths([Folder, Found.Name, BLENDER_NAME])) and (CompareText(Found.Name, Best) > 0) then
        Best := Found.Name;
    until FindNext(Found) <> 0;
    FindClose(Found);
  end;
  if Best <> '' then
    Result := ConcatPaths([Folder, Best, BLENDER_NAME]);
end;
  {$ELSEIF DEFINED(DARWIN)}
begin
  Result := ConcatPaths([PathDelim + 'Applications', 'Blender.app', 'Contents', 'MacOS', 'Blender']);
  if not FileExists(Result) then
    Result := '';
end;
  {$ELSE}
begin
  Result := '';
end;
{$ENDIF}

function FindBlender(const Configured: string): string;
begin
  if Configured <> '' then
  begin
    if FileExists(Configured) then
      Exit(ExpandFileName(Configured));
    Exit(ExeSearch(Configured, GetEnvironmentVariable('PATH')));
  end;
  Result := ExeSearch(BLENDER_NAME, GetEnvironmentVariable('PATH'));
  if Result = '' then
    Result := InstalledBlender;
end;

function BlenderParameters(const Script: string; Frames: integer): TStringArray;
begin
  // Factory settings, so the user's add-ons and preferences do not change the
  // result; a failing script ends Blender with 1
  Result := ['--background', '--factory-startup', '--python-exit-code', '1', '--python', Script, '--', '--frames', IntToStr(Frames)];
end;

function BlenderProgress(const Line: string; out Text: string): boolean;
begin
  Result := Line.StartsWith(PROGRESS_PREFIX);
  if Result then
    Text := Trim(Copy(Line, Length(PROGRESS_PREFIX) + 1, MaxInt))
  else
    Text := '';
end;

function RunBlender(const Blender, Script: string; Frames: integer; OnLine: TBlenderLineEvent; out Run: TBlenderRun;
  out ErrorMessage: string): boolean;
var
  Runner: TProcess;
  Parameter, Pending, Line, Progress, Chunk: string;
  Buffer: array[0..READ_BUFFER - 1] of char;
  Count, Ending: integer;

  procedure HandleLine(const Text: string);
  begin
    if not BlenderProgress(Text, Progress) and (Trim(Text) <> '') then
    begin
      Insert(Text, Run.Tail, Length(Run.Tail));
      if Length(Run.Tail) > TAIL_LINES then
        Delete(Run.Tail, 0, 1);
    end;
    if Assigned(OnLine) then
      OnLine(Text);
  end;

  procedure TakeLines;
  begin
    Ending := Pos(#10, Pending);
    while Ending > 0 do
    begin
      Line := Copy(Pending, 1, Ending - 1);
      Delete(Pending, 1, Ending);
      HandleLine(TrimRight(Line));
      Ending := Pos(#10, Pending);
    end;
  end;

  procedure ReadAvailable;
  begin
    while Runner.Output.NumBytesAvailable > 0 do
    begin
      Count := Runner.Output.Read(Buffer[0], SizeOf(Buffer));
      if Count <= 0 then
        Break;
      SetString(Chunk, PChar(@Buffer[0]), Count);
      Pending := Pending + Chunk;
      TakeLines;
    end;
  end;

begin
  Run := Default(TBlenderRun);
  ErrorMessage := '';
  Pending := '';
  Runner := TProcess.Create(nil);
  try
    Runner.Executable := Blender;
    for Parameter in BlenderParameters(Script, Frames) do
      Runner.Parameters.Add(Parameter);
    Runner.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
    try
      Runner.Execute;
    except
      on Failure: Exception do
      begin
        ErrorMessage := Format(rsBlenderNotStarted, [Blender, Failure.Message]);
        Exit(False);
      end;
    end;
    while Runner.Running do
    begin
      if Runner.Output.NumBytesAvailable > 0 then
        ReadAvailable
      else
        Sleep(IDLE_WAIT);
    end;
    ReadAvailable;
    if Pending <> '' then
      HandleLine(TrimRight(Pending));
    Run.ExitCode := Runner.ExitCode;
    Result := True;
  finally
    FreeAndNil(Runner);
  end;
end;

end.
