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

// A TLS server on 127.0.0.1 with the certificates in tests/tls, for the
// tests of the assistant's HTTPS transport and of opensloper-cli
// check-connection.
unit Sloper.Tests.TlsServer;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, ssockets;

type
  // Accepts on 127.0.0.1 with a self-signed certificate and answers each
  // request 200, until stopped
  TTlsTestServer = class(TThread)
  private
    FServer: TInetServer;
    FPort: word;
    FCertificate: string;
    FRequests: integer;
    FLastRequest: string;
    FStall, FCloseEarly: boolean;
    procedure CreateHandler(Sender: TObject; out AHandler: TSocketHandler);
    procedure Connected(Sender: TObject; Data: TSocketStream);
    procedure Idle(Sender: TObject);
  protected
    procedure Execute; override;
  public
    // Certificate: the path of a .pem with its .key beside it. Stall: read
    // the request and never answer, until stopped
    constructor Create(const Certificate: string; Stall: boolean = False);
    destructor Destroy; override;
    property Port: word read FPort;
    property Requests: integer read FRequests;
    // The last request as it came, headers and body
    property LastRequest: string read FLastRequest;
    // Read the request, then reset the connection without answering
    property CloseEarly: boolean read FCloseEarly write FCloseEarly;
  end;

const
  // How often the server looks up from waiting; ms
  TLS_TEST_IDLE_MS = 50;

// The pair of a test certificate in tests/tls
function TlsTestFile(const AName: string): string;

implementation

uses
  {$IFDEF UNIX} BaseUnix, {$ENDIF} Sockets, sslsockets, opensslsockets;

const
  TLS_TEST_FIRST_PORT = 47100;
  TLS_TEST_PORT_TRIES = 50;
  TLS_TEST_READ_MS = 2000;

function TlsTestFile(const AName: string): string;
begin
  Result := ConcatPaths([ExtractFileDir(ExpandFileName(ParamStr(0))), 'tls', AName]);
end;

constructor TTlsTestServer.Create(const Certificate: string; Stall: boolean);
var
  Try_: integer;
begin
  inherited Create(True);
  FCertificate := Certificate;
  FStall := Stall;
  for Try_ := 0 to TLS_TEST_PORT_TRIES - 1 do
  try
    // Bound and listening before the client connects; StartAccepting
    // would bind only in the thread
    FServer := TInetServer.Create('127.0.0.1', TLS_TEST_FIRST_PORT + Try_);
    FServer.ReuseAddress := True;
    FServer.Listen;
    FPort := TLS_TEST_FIRST_PORT + Try_;
    Break;
  except
    on ESocketError do
      FreeAndNil(FServer);
  end;
  if not Assigned(FServer) then
    raise Exception.Create('No free port for the TLS test server');
  FServer.OnCreateClientSocketHandler := @CreateHandler;
  FServer.OnConnect := @Connected;
  FServer.OnIdle := @Idle;
  FServer.AcceptIdleTimeOut := TLS_TEST_IDLE_MS;
  Start;
end;

destructor TTlsTestServer.Destroy;
begin
  Terminate;
  WaitFor;
  FreeAndNil(FServer);
  inherited Destroy;
end;

procedure TTlsTestServer.CreateHandler(Sender: TObject; out AHandler: TSocketHandler);
var
  Handler: TOpenSSLSocketHandler;
begin
  Handler := TOpenSSLSocketHandler.Create;
  Handler.CertificateData.Certificate.FileName := FCertificate;
  Handler.CertificateData.PrivateKey.FileName := ChangeFileExt(FCertificate, '.key');
  AHandler := Handler;
end;

procedure TTlsTestServer.Connected(Sender: TObject; Data: TSocketStream);
const
  ANSWER = 'HTTP/1.1 200 OK'#13#10'Content-Length: 2'#13#10'Connection: close'#13#10#13#10'{}';
var
  Buffer: array[0..4095] of byte;
  Received: string;
  Count: integer;
  Linger: TLinger;
begin
  try
    Inc(FRequests);
    Data.IOTimeout := TLS_TEST_READ_MS;
    Received := '';
    // The request ends with its body, '{}'
    repeat
      Count := Data.Read(Buffer, SizeOf(Buffer));
      if Count > 0 then
        Received := Received + Copy(PChar(@Buffer[0]), 1, Count);
    until (Count <= 0) or (Pos(#13#10#13#10, Received) > 0) and Received.EndsWith('}');
    FLastRequest := Received;
    // A reset, as a proxy dropping the connection gives: no TLS close, and
    // the socket closed with linger 0
    if FCloseEarly then
    begin
      Linger.l_onoff := 1;
      Linger.l_linger := 0;
      fpSetSockOpt(Data.Handle, SOL_SOCKET, SO_LINGER, @Linger, SizeOf(Linger));
      CloseSocket(Data.Handle);
      Exit;
    end;
    while FStall and not Terminated do
      Sleep(TLS_TEST_IDLE_MS);
    if not FStall then
      Data.WriteBuffer(ANSWER[1], Length(ANSWER));
  finally
    FreeAndNil(Data);
  end;
end;

procedure TTlsTestServer.Idle(Sender: TObject);
begin
  if Terminated then
    FServer.StopAccepting;
end;

procedure TTlsTestServer.Execute;
begin
  try
    FServer.StartAccepting;
  except
    // A failed handshake is the client refusing, which is what is tested
  end;
end;

end.
