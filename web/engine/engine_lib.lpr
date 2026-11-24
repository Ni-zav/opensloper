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

// The web engine as a library for the browser: handle() takes one JSON-RPC
// request as UTF-8 and gives back the reply, as opensloper-cli serve does a
// line at a time. The page writes the request into memory from engine_alloc
// and frees the reply with engine_free.
library engine_lib;

{$mode ObjFPC}{$H+}

uses
  Sloper.Core.CodePage,
  SysUtils,
  StrUtils,
  fpjson,
  Sloper.API.EditorServer,
  Sloper.API.PublishServer;

type
  TBrowserEngine = class(TEditorApiServer)
  private
    FPublish: TPublishApiServer;
  protected
    function DispatchMethod(const Method: string; Params: TJSONObject): TJSONData; override;
  public
    destructor Destroy; override;
  end;

const
  PUBLISH_PREFIX = 'publish_';

  function TBrowserEngine.DispatchMethod(const Method: string; Params: TJSONObject): TJSONData;
  begin
    if not StartsStr(PUBLISH_PREFIX, Method) then
      Exit(inherited DispatchMethod(Method, Params));
    if not Assigned(FPublish) then
      FPublish := TPublishApiServer.Create;
    Result := FPublish.CallMethod(Copy(Method, Length(PUBLISH_PREFIX) + 1, MaxInt), Params);
  end;

  destructor TBrowserEngine.Destroy;
  begin
    FreeAndNil(FPublish);
    inherited Destroy;
  end;

var
  Server: TBrowserEngine = nil;

  function engine_alloc(Size: longword): pointer;
  begin
    Result := GetMem(Size);
  end;

  procedure engine_free(Memory: pointer);
  begin
    FreeMem(Memory);
  end;

  // The reply as a 4-byte little-endian length followed by its bytes, in memory
  // the caller frees; an empty reply for a notification
  function engine_handle(Request: pansichar; Size: longword): pointer;
  var
    Line, Reply: rawbytestring;
  begin
    if not Assigned(Server) then
      Server := TBrowserEngine.Create;
    SetString(Line, Request, Size);
    SetCodePage(Line, CP_UTF8, False);
    Reply := UTF8Encode(UTF8Decode(Server.HandleLine(Line)));
    Result := GetMem(4 + Length(Reply));
    PLongWord(Result)^ := NtoLE(longword(Length(Reply)));
    if Reply <> '' then
      Move(Reply[1], (pbyte(Result) + 4)^, Length(Reply));
  end;

exports
  engine_alloc,
  engine_free,
  engine_handle;

end.
