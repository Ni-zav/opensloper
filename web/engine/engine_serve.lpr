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

// The web engine: the Automation API as a WASI program, one JSON-RPC request a
// line on stdin and one reply a line on stdout, as opensloper-cli serve.
program engine_serve;

{$mode ObjFPC}{$H+}

uses
  Sloper.Core.CodePage,
  SysUtils,
  Sloper.API.EditorServer;

var
  Server: TEditorApiServer;
  Line, Reply: string;
begin
  Server := TEditorApiServer.Create;
  try
    while not EOF(Input) do
    begin
      ReadLn(Input, Line);
      if Trim(Line) = '' then
        Continue;
      Reply := Server.HandleLine(Line);
      if Reply <> '' then
      begin
        WriteLn(Output, Reply);
        Flush(Output);
      end;
    end;
  finally
    FreeAndNil(Server);
  end;
end.
