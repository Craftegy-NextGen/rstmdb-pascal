unit TestClient;

{$I rstmdb.inc}

interface

procedure RegisterClientTests;

implementation

uses
  SysUtils,
  SyncObjs,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Protocol,
  Rstmdb.Json,
  Rstmdb.Transport,
  Rstmdb.Client,
  Rstmdb.TestRunner;

type
  TClientMockTransport = class(TRstmdbTransport)
  private
    FLock: TCriticalSection;
    FDataEvent: TEvent;
    FInBuf: TBytes;
    FConnected: Boolean;
    FApplyCallCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const Host: string; Port: Word; TimeoutMs: Integer;
      const Tls: TRstmdbTlsOptions); override;
    procedure Close; override;
    function IsConnected: Boolean; override;
    procedure WriteAll(const Data: TBytes); override;
    function ReadExact(Count: Integer; TimeoutMs: Integer): TBytes; override;
    procedure PushFrame(const JsonText: string);
  end;

constructor TClientMockTransport.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FDataEvent := TEvent.Create(nil, True, False, '');
  FConnected := False;
  FApplyCallCount := 0;
end;

destructor TClientMockTransport.Destroy;
begin
  Close;
  FDataEvent.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TClientMockTransport.Connect(const Host: string; Port: Word;
  TimeoutMs: Integer; const Tls: TRstmdbTlsOptions);
begin
  FLock.Enter;
  try
    FConnected := True;
  finally
    FLock.Leave;
  end;
end;

procedure TClientMockTransport.Close;
begin
  FLock.Enter;
  try
    FConnected := False;
    FDataEvent.SetEvent;
  finally
    FLock.Leave;
  end;
end;

function TClientMockTransport.IsConnected: Boolean;
begin
  FLock.Enter;
  try
    Result := FConnected;
  finally
    FLock.Leave;
  end;
end;

procedure TClientMockTransport.PushFrame(const JsonText: string);
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

procedure TClientMockTransport.WriteAll(const Data: TBytes);
var
  Buf, SampleArchive: TBytes;
  Frame: TRstmdbFrame;
  JsonStr, Op, ReqId, IdemKey: string;
  Doc: TRstmdbJsonDoc;
  ParamsNode: TRstmdbNativeJson;
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

      if Op = OP_HELLO then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{' +
          '"protocol_version":1,"wire_mode":"binary_json","server_name":"rstmdb",' +
          '"server_version":"0.3.0","features":["idempotency","durable_idempotency","batch"]}}',
          [ReqId]))
      else if Op = OP_PUT_MACHINE then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{' +
          '"machine":"order","version":1,"stored_checksum":"abc123","created":true}}',
          [ReqId]))
      else if Op = OP_CREATE_INSTANCE then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{' +
          '"instance_id":"ord-100","state":"pending","wal_offset":10}}',
          [ReqId]))
      else if Op = OP_APPLY_EVENT then
      begin
        Inc(FApplyCallCount);
        IdemKey := JsonGetString(ParamsNode, 'idempotency_key', '');
        if IdemKey = 'conflict-key' then
          PushFrame(Format(
            '{"type":"response","id":"%s","status":"error","error":{' +
            '"code":"IDEMPOTENCY_CONFLICT","message":"Reused key with different request","retryable":false}}',
            [ReqId]))
        else if FApplyCallCount = 1 then
          PushFrame(Format(
            '{"type":"response","id":"%s","status":"ok","result":{' +
            '"from_state":"pending","to_state":"paid","ctx":{"amount":42},' +
            '"wal_offset":11,"applied":true,"event_id":"evt-1"}}',
            [ReqId]))
        else
          PushFrame(Format(
            '{"type":"response","id":"%s","status":"ok","result":{' +
            '"from_state":"pending","to_state":"paid","ctx":{"amount":42},' +
            '"wal_offset":11,"applied":false,"event_id":"evt-1"}}',
            [ReqId]));
      end
      else if Op = OP_BATCH then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{"results":[' +
          '{"status":"ok","result":{"from_state":"pending","to_state":"paid","wal_offset":12,"applied":true}},' +
          '{"status":"error","error":{"code":"INSTANCE_NOT_FOUND","message":"Missing","retryable":false}}' +
          ']}}', [ReqId]))
      else if Op = OP_REPLICATION_STATUS then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{"role":"standalone"}}',
          [ReqId]))
      else if Op = OP_BACKUP_BEGIN then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{' +
          '"backup_id":"bkp-1","manifest":{"version":1},"total_bytes":5,"chunk_size":1024}}',
          [ReqId]))
      else if Op = OP_BACKUP_CHUNK then
      begin
        SetLength(SampleArchive, 5);
        SampleArchive[0] := Ord('H'); SampleArchive[1] := Ord('E');
        SampleArchive[2] := Ord('L'); SampleArchive[3] := Ord('L');
        SampleArchive[4] := Ord('O');
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{"bytes":"%s","eof":true}}',
          [ReqId, Base64EncodeBytes(SampleArchive)]));
      end
      else if Op = OP_BACKUP_END then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{"ok":true}}',
          [ReqId]))
      else if Op = OP_FLUSH_ALL then
        PushFrame(Format(
          '{"type":"response","id":"%s","status":"ok","result":{' +
          '"flushed":true,"instances_removed":3,"machines_removed":1}}',
          [ReqId]));
    finally
      Doc.Free;
    end;
  end;
end;

function TClientMockTransport.ReadExact(Count: Integer; TimeoutMs: Integer): TBytes;
var
  Remaining, WaitMs: Integer;
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
        raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Closed', True);
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
      WaitMs := TimeoutMs
    else
      WaitMs := 1000;
    WaitRes := FDataEvent.WaitFor(Cardinal(WaitMs));
    if WaitRes <> wrSignaled then
      raise ERstmdbTimeoutError.Create(ERR_TIMEOUT, 'Timeout', True);
  end;
end;

procedure TestClientRpcFamilies;
var
  Mock: TClientMockTransport;
  Client: TRstmdbClient;
  PutRes: TRstmdbPutMachineResult;
  CrRes: TRstmdbCreateInstanceResult;
  Ap1, Ap2: TRstmdbApplyEventResult;
  Ops: TRstmdbBatchOpArray;
  BatchRes: TRstmdbBatchResult;
  Rep: TRstmdbReplicationStatus;
  BkpBegin: TRstmdbBackupBeginResult;
  BkpChunk: TRstmdbBackupChunkResult;
  BkpEnd: TRstmdbBackupEndResult;
  Flushed: TRstmdbFlushAllResult;
  ConflictRaised: Boolean;
begin
  Mock := TClientMockTransport.Create;
  Client := TRstmdbClient.Create(TRstmdbOptions.Default, Mock, True);
  try
    Client.Connect;

    PutRes := Client.PutMachine('order', 1, '{"states":["pending","paid"],"initial":"pending","transitions":[]}');
    CheckEquals('order', PutRes.Machine, 'PutMachine');
    CheckEquals(True, PutRes.Created, 'PutMachine created');

    CrRes := Client.CreateInstance('order', 1, 'ord-100', '{"customer":"alice"}', 'idem-create-1');
    CheckEquals('ord-100', CrRes.InstanceId, 'CreateInstance');
    CheckEquals(Int64(10), CrRes.WalOffset, 'CreateInstance WalOffset');

    Ap1 := Client.ApplyEvent('ord-100', 'PAY', '{"amount":42}', 'idem-pay-1');
    CheckEquals(True, Ap1.Applied, 'First ApplyEvent Applied=True');
    CheckEquals('paid', Ap1.ToState, 'ToState');

    Ap2 := Client.ApplyEvent('ord-100', 'PAY', '{"amount":42}', 'idem-pay-1');
    CheckEquals(False, Ap2.Applied, 'Replayed ApplyEvent Applied=False');
    CheckEquals(Int64(11), Ap2.WalOffset, 'Replayed WalOffset preserved');

    ConflictRaised := False;
    try
      Client.ApplyEvent('ord-100', 'SHIP', '{}', 'conflict-key');
    except
      on E: ERstmdbServerError do
      begin
        ConflictRaised := IsIdempotencyConflict(E) and (not IsRetryable(E));
      end;
    end;
    Check(ConflictRaised, 'IDEMPOTENCY_CONFLICT raised and non-retryable');

    SetLength(Ops, 2);
    Ops[0].Op := OP_APPLY_EVENT;
    Ops[0].ParamsJson := '{"instance_id":"ord-100","event":"PAY"}';
    Ops[1].Op := OP_APPLY_EVENT;
    Ops[1].ParamsJson := '{"instance_id":"missing","event":"PAY"}';
    BatchRes := Client.Batch(Ops, bmBestEffort);
    CheckEquals(Int64(2), Int64(Length(BatchRes.Results)), 'Batch results count');
    CheckEquals('ok', BatchRes.Results[0].Status, 'Batch item 0 ok');
    CheckEquals('error', BatchRes.Results[1].Status, 'Batch item 1 error');
    CheckEquals(ERR_INSTANCE_NOT_FOUND, BatchRes.Results[1].ErrorCode, 'Batch item 1 error code');

    Rep := Client.ReplicationStatus;
    CheckEquals('standalone', Rep.Role, 'ReplicationStatus standalone');

    BkpBegin := Client.BackupBegin('gzip');
    CheckEquals('bkp-1', BkpBegin.BackupId, 'BackupBegin id');
    CheckEquals(Int64(5), BkpBegin.TotalBytes, 'BackupBegin total_bytes');
    BkpChunk := Client.BackupChunk(BkpBegin.BackupId, 0, 1024);
    CheckEquals(True, BkpChunk.Eof, 'BackupChunk eof');
    CheckEquals(Int64(5), Int64(Length(BkpChunk.Data)), 'BackupChunk decoded bytes');
    BkpEnd := Client.BackupEnd(BkpBegin.BackupId);
    CheckEquals(True, BkpEnd.Ok, 'BackupEnd ok');

    Flushed := Client.FlushAll;
    CheckEquals(True, Flushed.Flushed, 'FlushAll flushed');
    CheckEquals(Int64(3), Flushed.InstancesRemoved, 'FlushAll instances_removed');
  finally
    Client.Free;
  end;
end;

procedure RegisterClientTests;
begin
  RegisterTest('Client.RpcFamilies', TestClientRpcFamilies);
end;

end.
