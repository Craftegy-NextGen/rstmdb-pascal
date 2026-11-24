unit Rstmdb.Connection;

{$I rstmdb.inc}

interface

uses
  SysUtils,
  Classes,
  SyncObjs,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Protocol,
  Rstmdb.Json,
  Rstmdb.Transport;

type
  TRstmdbPendingRequest = class
  public
    Id: string;
    Event: TEvent;
    Completed: Boolean;
    Failed: Boolean;
    IsServerError: Boolean;
    IsProtocolError: Boolean;
    ErrorCode: string;
    ErrorMessage: string;
    ErrorRetryable: Boolean;
    ErrorDetailsJson: string;
    ResultJson: string;
    constructor Create(const AId: string);
    destructor Destroy; override;
  end;

  TRstmdbConnection = class;

  TRstmdbReaderThread = class(TThread)
  private
    FConn: TRstmdbConnection;
  protected
    procedure Execute; override;
  public
    constructor Create(AConn: TRstmdbConnection);
  end;

  TRstmdbConnection = class
  private
    FOptions: TRstmdbOptions;
    FTransport: TRstmdbTransport;
    FOwnsTransport: Boolean;
    FWriteLock: TCriticalSection;
    FStateLock: TCriticalSection;
    FStreamLock: TCriticalSection;
    FPending: array of TRstmdbPendingRequest;
    FStreamQueue: array of TRstmdbStreamEvent;
    FReader: TRstmdbReaderThread;
    FNextId: Int64;
    FConnected: Boolean;
    FClosing: Boolean;
    FHelloResult: TRstmdbHelloResult;
    FOnStreamEvent: TRstmdbStreamEventProc;

    procedure LogMsg(const Level, Msg: string);
    function NextRequestId: string;
    function SendSyncRaw(const Op, ParamsJson: string): TRstmdbWireMessage;
    procedure PerformHello;
    procedure PerformAuth;
    procedure AddPending(Req: TRstmdbPendingRequest);
    procedure RemovePending(Req: TRstmdbPendingRequest);
    procedure CompletePendingResponse(const Msg: TRstmdbWireMessage);
    procedure FailAllPending(const ACode, AMsg: string; ARetryable, AProtocolErr: Boolean);
    procedure EnqueueStreamEvent(const Ev: TRstmdbStreamEvent);
    procedure ReaderLoop;
  public
    constructor Create(const AOptions: TRstmdbOptions); overload;
    constructor Create(const AOptions: TRstmdbOptions; ATransport: TRstmdbTransport;
      AOwnsTransport: Boolean = True); overload;
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;

    function SendRequest(const Op: string; const ParamsJson: string = '{}'): string;
    function PollStreamEvent(out Ev: TRstmdbStreamEvent): Boolean;
    function StreamQueueCount: Integer;

    property Options: TRstmdbOptions read FOptions;
    property HelloResult: TRstmdbHelloResult read FHelloResult;
    property NegotiatedFeatures: TRstmdbStringArray read FHelloResult.Features;
    property OnStreamEvent: TRstmdbStreamEventProc read FOnStreamEvent write FOnStreamEvent;
  end;

implementation

{ TRstmdbPendingRequest }

constructor TRstmdbPendingRequest.Create(const AId: string);
begin
  inherited Create;
  Id := AId;
  Event := TEvent.Create(nil, True, False, '');
  Completed := False;
  Failed := False;
  IsServerError := False;
  IsProtocolError := False;
  ErrorRetryable := False;
end;

destructor TRstmdbPendingRequest.Destroy;
begin
  Event.Free;
  inherited Destroy;
end;

{ TRstmdbReaderThread }

constructor TRstmdbReaderThread.Create(AConn: TRstmdbConnection);
begin
  FConn := AConn;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TRstmdbReaderThread.Execute;
begin
  FConn.ReaderLoop;
end;

{ TRstmdbConnection }

constructor TRstmdbConnection.Create(const AOptions: TRstmdbOptions);
begin
  Create(AOptions, CreateDefaultTransport, True);
end;

constructor TRstmdbConnection.Create(const AOptions: TRstmdbOptions;
  ATransport: TRstmdbTransport; AOwnsTransport: Boolean);
begin
  inherited Create;
  FOptions := AOptions;
  FTransport := ATransport;
  FOwnsTransport := AOwnsTransport;
  FWriteLock := TCriticalSection.Create;
  FStateLock := TCriticalSection.Create;
  FStreamLock := TCriticalSection.Create;
  FNextId := 0;
  FConnected := False;
  FClosing := False;
  FHelloResult := System.Default(TRstmdbHelloResult);
end;

destructor TRstmdbConnection.Destroy;
begin
  Disconnect;
  if FOwnsTransport then
    FreeAndNil(FTransport)
  else
    FTransport := nil;
  FStreamLock.Free;
  FStateLock.Free;
  FWriteLock.Free;
  inherited Destroy;
end;

procedure TRstmdbConnection.LogMsg(const Level, Msg: string);
begin
  if Assigned(FOptions.LogProc) then
    FOptions.LogProc(Level, Msg);
end;

function TRstmdbConnection.NextRequestId: string;
begin
  FStateLock.Enter;
  try
    Inc(FNextId);
    Result := IntToStr(FNextId);
  finally
    FStateLock.Leave;
  end;
end;

function TRstmdbConnection.SendSyncRaw(const Op, ParamsJson: string): TRstmdbWireMessage;
var
  ReqId: string;
  FrameBytes, HeaderBytes, PayloadBytes: TBytes;
  Header: TRstmdbFrameHeader;
  ActualCrc: Cardinal;
begin
  ReqId := NextRequestId;
  FrameBytes := EncodeFrame(BuildRequestJson(ReqId, Op, ParamsJson));
  FTransport.WriteAll(FrameBytes);

  HeaderBytes := FTransport.ReadExact(RSTMDB_HEADER_SIZE, FOptions.RequestTimeoutMs);
  Header := DecodeFrameHeader(HeaderBytes, 0);
  if Header.HeaderLen > 0 then
    FTransport.ReadExact(Header.HeaderLen, FOptions.RequestTimeoutMs);
  if Header.PayloadLen > 0 then
    PayloadBytes := FTransport.ReadExact(Integer(Header.PayloadLen), FOptions.RequestTimeoutMs)
  else
    SetLength(PayloadBytes, 0);

  if (Header.Flags and RSTMDB_FLAG_CRC_PRESENT) <> 0 then
  begin
    ActualCrc := RstmdbCrc32c(PayloadBytes);
    if ActualCrc <> Header.Crc32c then
      raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
        Format('CRC32C mismatch during handshake: expected $%.8x, got $%.8x',
          [Header.Crc32c, ActualCrc]));
  end;

  Result := ParseWireMessage(PayloadBytes);
  if Result.Status = 'error' then
    raise ERstmdbServerError.Create(Result.ErrorCode, Result.ErrorMessage,
      Result.ErrorRetryable, Result.ErrorDetailsJson);
end;

procedure TRstmdbConnection.PerformHello;
var
  B: TRstmdbJsonBuilder;
  WireModes: TRstmdbStringArray;
  Features: TRstmdbStringArray;
  Resp: TRstmdbWireMessage;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  SetLength(WireModes, 1);
  WireModes[0] := 'binary_json';

  if Length(FOptions.Features) > 0 then
    Features := FOptions.Features
  else
  begin
    SetLength(Features, 3);
    Features[0] := 'idempotency';
    Features[1] := 'durable_idempotency';
    Features[2] := 'batch';
  end;

  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddInt64('protocol_version', RSTMDB_PROTOCOL_VERSION);
    if FOptions.ClientName <> '' then
      B.AddString('client_name', FOptions.ClientName);
    B.AddStringArray('wire_modes', WireModes);
    B.AddStringArray('features', Features);
    Resp := SendSyncRaw(OP_HELLO, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(Resp.ResultJson);
  try
    Root := Doc.Root;
    FHelloResult.ProtocolVersion := Word(JsonGetInt64(Root, 'protocol_version', 1));
    FHelloResult.WireMode := JsonGetString(Root, 'wire_mode', 'binary_json');
    FHelloResult.ServerName := JsonGetString(Root, 'server_name', '');
    FHelloResult.ServerVersion := JsonGetString(Root, 'server_version', '');
    FHelloResult.Features := JsonGetStringArray(Root, 'features');
  finally
    Doc.Free;
  end;
  LogMsg('INFO', Format('Connected to %s %s', [FHelloResult.ServerName, FHelloResult.ServerVersion]));
end;

procedure TRstmdbConnection.PerformAuth;
var
  B: TRstmdbJsonBuilder;
begin
  if FOptions.AuthToken = '' then
    Exit;
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('method', 'bearer');
    B.AddString('token', FOptions.AuthToken);
    try
      SendSyncRaw(OP_AUTH, B.ToJson);
    except
      on E: ERstmdbError do
      begin
        { Ensure bearer token is never echoed in re-raised diagnostics }
        LogMsg('ERROR', Format('AUTH failed (%s)', [E.Code]));
        raise;
      end;
    end;
  finally
    B.Free;
  end;
end;

procedure TRstmdbConnection.Connect;
begin
  if FConnected then
    Exit;
  FClosing := False;
  FHelloResult := System.Default(TRstmdbHelloResult);
  FTransport.Connect(FOptions.Host, FOptions.Port, FOptions.ConnectTimeoutMs, FOptions.Tls);
  try
    PerformHello;
    PerformAuth;
    FConnected := True;
    FReader := TRstmdbReaderThread.Create(Self);
  except
    FConnected := False;
    FTransport.Close;
    raise;
  end;
end;

procedure TRstmdbConnection.Disconnect;
var
  ReqId: string;
  ByeFrame: TBytes;
  ThreadToWait: TRstmdbReaderThread;
begin
  if FClosing and (FReader = nil) and (not FConnected) then
    Exit;

  FClosing := True;
  if FConnected and FTransport.IsConnected then
  begin
    try
      ReqId := NextRequestId;
      ByeFrame := EncodeFrame(BuildRequestJson(ReqId, OP_BYE, '{}'));
      FWriteLock.Enter;
      try
        FTransport.WriteAll(ByeFrame);
      finally
        FWriteLock.Leave;
      end;
    except
      { Best-effort BYE }
    end;
  end;

  FConnected := False;
  ThreadToWait := FReader;
  FReader := nil;
  if ThreadToWait <> nil then
    ThreadToWait.Terminate;

  FTransport.Close;

  if ThreadToWait <> nil then
  begin
    ThreadToWait.WaitFor;
    ThreadToWait.Free;
  end;

  FailAllPending(ERR_CONNECTION_CLOSED, 'Connection closed', True, False);

  FStreamLock.Enter;
  try
    SetLength(FStreamQueue, 0);
  finally
    FStreamLock.Leave;
  end;
end;

function TRstmdbConnection.IsConnected: Boolean;
begin
  Result := FConnected and (not FClosing) and FTransport.IsConnected;
end;

procedure TRstmdbConnection.AddPending(Req: TRstmdbPendingRequest);
var
  Len: Integer;
begin
  FStateLock.Enter;
  try
    Len := Length(FPending);
    SetLength(FPending, Len + 1);
    FPending[Len] := Req;
  finally
    FStateLock.Leave;
  end;
end;

procedure TRstmdbConnection.RemovePending(Req: TRstmdbPendingRequest);
var
  I, Len: Integer;
begin
  FStateLock.Enter;
  try
    Len := Length(FPending);
    for I := 0 to Len - 1 do
    begin
      if FPending[I] = Req then
      begin
        if I < Len - 1 then
          FPending[I] := FPending[Len - 1];
        SetLength(FPending, Len - 1);
        Break;
      end;
    end;
  finally
    FStateLock.Leave;
  end;
end;

procedure TRstmdbConnection.CompletePendingResponse(const Msg: TRstmdbWireMessage);
var
  I: Integer;
  Req: TRstmdbPendingRequest;
begin
  FStateLock.Enter;
  try
    for I := 0 to Length(FPending) - 1 do
    begin
      Req := FPending[I];
      if Req.Id = Msg.Id then
      begin
        if Msg.Status = 'error' then
        begin
          Req.Failed := True;
          Req.IsServerError := True;
          Req.ErrorCode := Msg.ErrorCode;
          Req.ErrorMessage := Msg.ErrorMessage;
          Req.ErrorRetryable := Msg.ErrorRetryable;
          Req.ErrorDetailsJson := Msg.ErrorDetailsJson;
        end
        else
        begin
          Req.Failed := False;
          Req.ResultJson := Msg.ResultJson;
        end;
        Req.Completed := True;
        Req.Event.SetEvent;
        Break;
      end;
    end;
  finally
    FStateLock.Leave;
  end;
end;

procedure TRstmdbConnection.FailAllPending(const ACode, AMsg: string;
  ARetryable, AProtocolErr: Boolean);
var
  I: Integer;
  Req: TRstmdbPendingRequest;
begin
  FStateLock.Enter;
  try
    for I := 0 to Length(FPending) - 1 do
    begin
      Req := FPending[I];
      if not Req.Completed then
      begin
        Req.Failed := True;
        Req.IsServerError := False;
        Req.IsProtocolError := AProtocolErr;
        Req.ErrorCode := ACode;
        Req.ErrorMessage := AMsg;
        Req.ErrorRetryable := ARetryable;
        Req.Completed := True;
        Req.Event.SetEvent;
      end;
    end;
  finally
    FStateLock.Leave;
  end;
end;

procedure TRstmdbConnection.EnqueueStreamEvent(const Ev: TRstmdbStreamEvent);
var
  Len: Integer;
  CB: TRstmdbStreamEventProc;
begin
  FStreamLock.Enter;
  try
    Len := Length(FStreamQueue);
    SetLength(FStreamQueue, Len + 1);
    FStreamQueue[Len] := Ev;
    CB := FOnStreamEvent;
  finally
    FStreamLock.Leave;
  end;
  if Assigned(CB) then
    CB(Ev);
end;

function TRstmdbConnection.PollStreamEvent(out Ev: TRstmdbStreamEvent): Boolean;
var
  I, Len: Integer;
begin
  Ev := System.Default(TRstmdbStreamEvent);
  FStreamLock.Enter;
  try
    Len := Length(FStreamQueue);
    if Len = 0 then
      Exit(False);
    Ev := FStreamQueue[0];
    for I := 0 to Len - 2 do
      FStreamQueue[I] := FStreamQueue[I + 1];
    SetLength(FStreamQueue, Len - 1);
    Result := True;
  finally
    FStreamLock.Leave;
  end;
end;

function TRstmdbConnection.StreamQueueCount: Integer;
begin
  FStreamLock.Enter;
  try
    Result := Length(FStreamQueue);
  finally
    FStreamLock.Leave;
  end;
end;

procedure TRstmdbConnection.ReaderLoop;
var
  HeaderBytes, PayloadBytes: TBytes;
  Header: TRstmdbFrameHeader;
  ActualCrc: Cardinal;
  Msg: TRstmdbWireMessage;
begin
  while (not FClosing) and (not FReader.CheckTerminated) do
  begin
    try
      HeaderBytes := FTransport.ReadExact(RSTMDB_HEADER_SIZE, 200);
      Header := DecodeFrameHeader(HeaderBytes, 0);
      if Header.HeaderLen > 0 then
        FTransport.ReadExact(Header.HeaderLen, FOptions.RequestTimeoutMs);
      if Header.PayloadLen > 0 then
        PayloadBytes := FTransport.ReadExact(Integer(Header.PayloadLen), FOptions.RequestTimeoutMs)
      else
        SetLength(PayloadBytes, 0);

      if (Header.Flags and RSTMDB_FLAG_CRC_PRESENT) <> 0 then
      begin
        ActualCrc := RstmdbCrc32c(PayloadBytes);
        if ActualCrc <> Header.Crc32c then
          raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
            Format('CRC32C mismatch: expected $%.8x, got $%.8x',
              [Header.Crc32c, ActualCrc]));
      end;

      Msg := ParseWireMessage(PayloadBytes);
      if Msg.MsgType = 'event' then
        EnqueueStreamEvent(Msg.StreamEvent)
      else
        CompletePendingResponse(Msg);
    except
      on E: ERstmdbTimeoutError do
      begin
        if FClosing or FReader.CheckTerminated then
          Break;
        Continue;
      end;
      on E: ERstmdbProtocolError do
      begin
        FConnected := False;
        FailAllPending(E.Code, E.ErrorMessage, False, True);
        Break;
      end;
      on E: ERstmdbError do
      begin
        FConnected := False;
        if not FClosing then
          FailAllPending(E.Code, E.ErrorMessage, E.Retryable, False);
        Break;
      end;
      on E: Exception do
      begin
        FConnected := False;
        if not FClosing then
          FailAllPending(ERR_CONNECTION_CLOSED, E.Message, True, False);
        Break;
      end;
    end;
  end;
end;

function TRstmdbConnection.SendRequest(const Op: string; const ParamsJson: string): string;
var
  ReqId: string;
  FrameBytes: TBytes;
  Req: TRstmdbPendingRequest;
  WaitRes: TWaitResult;
  TimeoutMs: Cardinal;
begin
  if not IsConnected then
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Client is not connected', True);

  ReqId := NextRequestId;
  FrameBytes := EncodeFrame(BuildRequestJson(ReqId, Op, ParamsJson));
  Req := TRstmdbPendingRequest.Create(ReqId);
  try
    AddPending(Req);
    try
      FWriteLock.Enter;
      try
        FTransport.WriteAll(FrameBytes);
      finally
        FWriteLock.Leave;
      end;

      if FOptions.RequestTimeoutMs > 0 then
        TimeoutMs := Cardinal(FOptions.RequestTimeoutMs)
      else
        TimeoutMs := INFINITE;

      WaitRes := Req.Event.WaitFor(TimeoutMs);
      if WaitRes <> wrSignaled then
        raise ERstmdbTimeoutError.Create(ERR_TIMEOUT,
          Format('Request %s (%s) timed out after %d ms', [ReqId, Op, FOptions.RequestTimeoutMs]),
          True);

      if Req.Failed then
      begin
        if Req.IsServerError then
          raise ERstmdbServerError.Create(Req.ErrorCode, Req.ErrorMessage,
            Req.ErrorRetryable, Req.ErrorDetailsJson)
        else if Req.IsProtocolError then
          raise ERstmdbProtocolError.Create(Req.ErrorCode, Req.ErrorMessage,
            Req.ErrorRetryable, Req.ErrorDetailsJson)
        else
          raise ERstmdbTransportError.Create(Req.ErrorCode, Req.ErrorMessage,
            Req.ErrorRetryable, Req.ErrorDetailsJson);
      end;

      Result := Req.ResultJson;
    finally
      RemovePending(Req);
    end;
  finally
    Req.Free;
  end;
end;

end.
