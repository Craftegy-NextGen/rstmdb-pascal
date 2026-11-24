unit TestConnection;

{$I rstmdb.inc}

interface

procedure RegisterConnectionTests;

implementation

uses
  SysUtils,
  SyncObjs,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Protocol,
  Rstmdb.Json,
  Rstmdb.Transport,
  Rstmdb.Connection,
  Rstmdb.TestRunner;

type
  TMockTransport = class(TRstmdbTransport)
  private
    FLock: TCriticalSection;
    FDataEvent: TEvent;
    FInBuf: TBytes;
    FConnected: Boolean;
    FAutoRespondHello: Boolean;
    FAutoRespondAuth: Boolean;
    FRequireAuthFail: Boolean;
    FDropResponsesForTimeout: Boolean;
  public
    SentOps: array of string;
    SentPayloads: array of string;
    LastAuthTokenSeen: string;
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const Host: string; Port: Word; TimeoutMs: Integer;
      const Tls: TRstmdbTlsOptions); override;
    procedure Close; override;
    function IsConnected: Boolean; override;
    procedure WriteAll(const Data: TBytes); override;
    function ReadExact(Count: Integer; TimeoutMs: Integer): TBytes; override;
    procedure PushIncomingFrame(const JsonText: string);
    property AutoRespondHello: Boolean read FAutoRespondHello write FAutoRespondHello;
    property AutoRespondAuth: Boolean read FAutoRespondAuth write FAutoRespondAuth;
    property RequireAuthFail: Boolean read FRequireAuthFail write FRequireAuthFail;
    property DropResponsesForTimeout: Boolean read FDropResponsesForTimeout write FDropResponsesForTimeout;
  end;

constructor TMockTransport.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDataEvent := TEvent.Create(nil, True, False, '');
  FConnected := False;
  FAutoRespondHello := True;
  FAutoRespondAuth := True;
  FRequireAuthFail := False;
  FDropResponsesForTimeout := False;
end;

destructor TMockTransport.Destroy;
begin
  Close;
  FDataEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TMockTransport.Connect(const Host: string; Port: Word; TimeoutMs: Integer;
  const Tls: TRstmdbTlsOptions);
begin
  FLock.Enter;
  try
    FConnected := True;
  finally
    FLock.Leave;
  end;
end;

procedure TMockTransport.Close;
begin
  FLock.Enter;
  try
    FConnected := False;
    FDataEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TMockTransport.IsConnected: Boolean;
begin
  FLock.Enter;
  try
    Result := FConnected;
  finally
    FLock.Leave;
  end;
end;

procedure TMockTransport.PushIncomingFrame(const JsonText: string);
var
  FrameBytes: TBytes;
  OldLen: Integer;
begin
  FrameBytes := EncodeFrame(StringToUtf8Bytes(JsonText));
  FLock.Enter;
  try
    OldLen := Length(FInBuf);
    SetLength(FInBuf, OldLen + Length(FrameBytes));
    Move(FrameBytes[0], FInBuf[OldLen], Length(FrameBytes));
    FDataEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

procedure TMockTransport.WriteAll(const Data: TBytes);
var
  Buf: TBytes;
  Frame: TRstmdbFrame;
  JsonStr, Op, ReqId: string;
  Doc: TRstmdbJsonDoc;
  ParamsNode: TRstmdbNativeJson;
  Len: Integer;
begin
  Buf := Copy(Data, 0, Length(Data));
  while TryDecodeFrame(Buf, Frame) do
  begin
    JsonStr := Utf8BytesToString(Frame.Payload);
    Doc := TRstmdbJsonDoc.ParseString(JsonStr);
    try
      Op := JsonGetString(Doc.Root, 'op', '');
      ReqId := JsonGetString(Doc.Root, 'id', '');
      ParamsNode := JsonFind(Doc.Root, 'params');

      FLock.Enter;
      try
        Len := Length(SentOps);
        SetLength(SentOps, Len + 1);
        SentOps[Len] := Op;
        SetLength(SentPayloads, Len + 1);
        SentPayloads[Len] := JsonStr;
      finally
        FLock.Leave;
      end;

      if (Op = OP_HELLO) and FAutoRespondHello then
      begin
        PushIncomingFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{' +
          '"protocol_version":1,"wire_mode":"binary_json",' +
          '"server_name":"rstmdb-mock","server_version":"1.0.0",' +
          '"features":["idempotency","durable_idempotency","batch"]}}', [ReqId]));
      end
      else if (Op = OP_AUTH) and FAutoRespondAuth then
      begin
        LastAuthTokenSeen := JsonGetString(ParamsNode, 'token', '');
        if FRequireAuthFail then
          PushIncomingFrame(Format(
            '{"type":"response","id":"%s","status":"error","error":{' +
            '"code":"AUTH_FAILED","message":"Invalid token","retryable":false}}', [ReqId]))
        else
          PushIncomingFrame(Format(
            '{"type":"response","id":"%s","status":"ok","result":{"authenticated":true}}', [ReqId]));
      end
      else if Op = OP_PING then
      begin
        if not FDropResponsesForTimeout then
          PushIncomingFrame(Format(
            '{"type":"response","id":"%s","status":"ok","result":{"pong":true}}', [ReqId]));
      end
      else if Op = OP_WATCH_ALL then
      begin
        PushIncomingFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{"subscription_id":"sub-1","wal_offset":10}}',
          [ReqId]));
        PushIncomingFrame(
          '{"type":"event","subscription_id":"sub-1","instance_id":"ord-1",' +
          '"machine":"order","version":1,"event":"PAY","from_state":"pending",' +
          '"to_state":"paid","payload":{"amount":42},"ctx":{"paid":true},"wal_offset":11}');
      end;
    finally
      Doc.Free;
    end;
  end;
end;

function TMockTransport.ReadExact(Count: Integer; TimeoutMs: Integer): TBytes;
var
  Remaining, WaitResLen: Integer;
  WaitRes: TWaitResult;
begin
  Result := nil;
  if Count <= 0 then
    Exit;

  while True do
  begin
    FLock.Enter;
    try
      if not FConnected then
        raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Mock transport closed', True);
      if Length(FInBuf) >= Count then
      begin
        SetLength(Result, Count);
        Move(FInBuf[0], Result[0], Count);
        Remaining := Length(FInBuf) - Count;
        if Remaining > 0 then
          Move(FInBuf[Count], FInBuf[0], Remaining);
        SetLength(FInBuf, Remaining);
        if Remaining = 0 then
          FDataEvent.ResetEvent;
        Exit;
      end;
    finally
      FLock.Leave;
    end;

    if TimeoutMs > 0 then
      WaitResLen := TimeoutMs
    else
      WaitResLen := 1000;
    WaitRes := FDataEvent.WaitFor(Cardinal(WaitResLen));
    if WaitRes <> wrSignaled then
      raise ERstmdbTimeoutError.Create(ERR_TIMEOUT, 'Mock read timed out', True);
  end;
end;

procedure TestHelloAndAuthNegotiation;
var
  Mock: TMockTransport;
  Opts: TRstmdbOptions;
  Conn: TRstmdbConnection;
  PingRes: string;
  Doc: TRstmdbJsonDoc;
begin
  Mock := TMockTransport.Create;
  Opts := TRstmdbOptions.Default('127.0.0.1', 7401);
  Opts.AuthToken := 'super-secret-token-123';
  Conn := TRstmdbConnection.Create(Opts, Mock, True);
  try
    Conn.Connect;
    Check(Conn.IsConnected, 'Connection should be connected');
    CheckEquals('rstmdb-mock', Conn.HelloResult.ServerName, 'ServerName');
    CheckEquals(Int64(3), Int64(Length(Conn.NegotiatedFeatures)), '3 negotiated features');
    CheckEquals('durable_idempotency', Conn.NegotiatedFeatures[1], 'durable_idempotency negotiated');
    CheckEquals('super-secret-token-123', Mock.LastAuthTokenSeen, 'Bearer token sent');

    PingRes := Conn.SendRequest(OP_PING);
    Doc := TRstmdbJsonDoc.ParseString(PingRes);
    try
      Check(JsonGetBool(Doc.Root, 'pong', False), 'PING correlated response');
    finally
      Doc.Free;
    end;
    Conn.Disconnect;
    Check(not Conn.IsConnected, 'Disconnected cleanly');
    CheckEquals(OP_BYE, Mock.SentOps[Length(Mock.SentOps) - 1], 'BYE sent on disconnect');
  finally
    Conn.Free;
  end;
end;

procedure TestAuthFailureRedactsSecret;
var
  Mock: TMockTransport;
  Opts: TRstmdbOptions;
  Conn: TRstmdbConnection;
  RaisedCode, RaisedMsg: string;
begin
  Mock := TMockTransport.Create;
  Mock.RequireAuthFail := True;
  Opts := TRstmdbOptions.Default;
  Opts.AuthToken := 'secret-xyz-999';
  Conn := TRstmdbConnection.Create(Opts, Mock, True);
  try
    RaisedCode := '';
    RaisedMsg := '';
    try
      Conn.Connect;
    except
      on E: ERstmdbServerError do
      begin
        RaisedCode := E.Code;
        RaisedMsg := E.Message;
      end;
    end;
    CheckEquals(ERR_AUTH_FAILED, RaisedCode, 'Auth failed code');
    Check(Pos('secret-xyz-999', RaisedMsg) = 0, 'Token must never appear in error message');
  finally
    Conn.Free;
  end;
end;

procedure TestStreamEventQueueAndCorrelation;
var
  Mock: TMockTransport;
  Opts: TRstmdbOptions;
  Conn: TRstmdbConnection;
  Resp: string;
  Ev: TRstmdbStreamEvent;
  Tries: Integer;
  GotEv: Boolean;
begin
  Mock := TMockTransport.Create;
  Opts := TRstmdbOptions.Default;
  Conn := TRstmdbConnection.Create(Opts, Mock, True);
  try
    Conn.Connect;
    Resp := Conn.SendRequest(OP_WATCH_ALL, '{}');
    Check(Pos('sub-1', Resp) > 0, 'WATCH_ALL response correlated');

    GotEv := False;
    for Tries := 1 to 50 do
    begin
      if Conn.PollStreamEvent(Ev) then
      begin
        GotEv := True;
        Break;
      end;
      Sleep(10);
    end;
    Check(GotEv, 'Stream event arrived in FIFO queue');
    CheckEquals('ord-1', Ev.InstanceId, 'StreamEvent InstanceId');
    CheckEquals('PAY', Ev.EventName, 'StreamEvent EventName');
    CheckEquals(Int64(11), Ev.WalOffset, 'StreamEvent WalOffset');
  finally
    Conn.Free;
  end;
end;

procedure TestRequestTimeout;
var
  Mock: TMockTransport;
  Opts: TRstmdbOptions;
  Conn: TRstmdbConnection;
  TimedOut: Boolean;
begin
  Mock := TMockTransport.Create;
  Mock.DropResponsesForTimeout := True;
  Opts := TRstmdbOptions.Default;
  Opts.RequestTimeoutMs := 120;
  Conn := TRstmdbConnection.Create(Opts, Mock, True);
  try
    Conn.Connect;
    TimedOut := False;
    try
      Conn.SendRequest(OP_PING);
    except
      on E: ERstmdbTimeoutError do
        TimedOut := True;
    end;
    Check(TimedOut, 'Timed out PING must raise ERstmdbTimeoutError');
  finally
    Conn.Free;
  end;
end;

procedure RegisterConnectionTests;
begin
  RegisterTest('Connection.HelloAndAuth', TestHelloAndAuthNegotiation);
  RegisterTest('Connection.AuthFailureRedactsSecret', TestAuthFailureRedactsSecret);
  RegisterTest('Connection.StreamEventQueue', TestStreamEventQueueAndCorrelation);
  RegisterTest('Connection.RequestTimeout', TestRequestTimeout);
end;

end.
