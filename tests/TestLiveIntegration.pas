unit TestLiveIntegration;

{$I rstmdb.inc}

interface

procedure RegisterLiveIntegrationTests;

implementation

uses
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Client,
  Rstmdb.TestRunner;

function GetLiveHost: string;
begin
  Result := GetEnvironmentVariable('RSTMDB_HOST');
end;

function GetLivePort: Word;
begin
  Result := Word(StrToIntDef(GetEnvironmentVariable('RSTMDB_PORT'), RSTMDB_DEFAULT_PORT));
end;

function NewLiveClient: TRstmdbClient;
var
  Opts: TRstmdbOptions;
begin
  Opts := TRstmdbOptions.Default(GetLiveHost, GetLivePort);
  Opts.AuthToken := GetEnvironmentVariable('RSTMDB_TOKEN');
  Result := TRstmdbClient.Create(Opts);
end;

function ContainsFeature(const Features: TRstmdbStringArray; const Target: string): Boolean;
var
  I: Integer;
begin
  for I := 0 to Length(Features) - 1 do
    if Features[I] = Target then
      Exit(True);
  Result := False;
end;

function UniqueSuffix: string;
begin
  Result := IntToStr(GetTickCount64) + '-' + IntToStr(Random(100000));
end;

procedure TestLiveHandshakeInfoAndReplication;
var
  Client: TRstmdbClient;
  InfoRes: TRstmdbServerInfo;
  RepRes: TRstmdbReplicationStatus;
begin
  Client := NewLiveClient;
  try
    Client.Connect;
    Check(Client.IsConnected, 'Live client connected');
    Check(ContainsFeature(Client.NegotiatedFeatures, 'durable_idempotency'),
      'HELLO must negotiate durable_idempotency');
    Check(Client.Ping, 'Ping must return True');

    InfoRes := Client.Info;
    Check(InfoRes.ServerName <> '', 'Info.ServerName non-empty');
    CheckEquals(Cardinal(1), Cardinal(InfoRes.ProtocolVersion), 'ProtocolVersion = 1');

    RepRes := Client.ReplicationStatus;
    CheckEquals('standalone', RepRes.Role, 'ReplicationStatus role = standalone');
  finally
    Client.Free;
  end;
end;

procedure TestLiveMachineInstanceIdempotencyAndErrors;
var
  Client: TRstmdbClient;
  MachineName, InstId, IdemCreateKey, IdemPayKey: string;
  PutRes: TRstmdbPutMachineResult;
  Cr1, Cr2: TRstmdbCreateInstanceResult;
  Ap1, Ap2: TRstmdbApplyEventResult;
  BadReqCaught, ConflictCaught: Boolean;
begin
  Client := NewLiveClient;
  try
    Client.Connect;
    MachineName := 'pascal_order_' + UniqueSuffix;
    PutRes := Client.PutMachine(
      MachineName,
      1,
      '{"states":["pending","paid","shipped"],"initial":"pending",' +
      '"transitions":[{"from":"pending","event":"PAY","to":"paid"},' +
      '{"from":"paid","event":"SHIP","to":"shipped"}]}'
    );
    CheckEquals(MachineName, PutRes.Machine, 'PutMachine name');
    CheckEquals(True, PutRes.Created, 'PutMachine created');

    BadReqCaught := False;
    try
      Client.CreateInstance(MachineName, 1, '', '"not-an-object"');
    except
      on E: ERstmdbServerError do
        BadReqCaught := (E.Code = ERR_BAD_REQUEST);
    end;
    Check(BadReqCaught, 'Non-object initial_ctx must return BAD_REQUEST');

    InstId := 'inst-' + UniqueSuffix;
    IdemCreateKey := 'ck-' + UniqueSuffix;
    Cr1 := Client.CreateInstance(MachineName, 1, InstId, '{"customer":"alice"}', IdemCreateKey);
    CheckEquals(InstId, Cr1.InstanceId, 'CreateInstance id');
    CheckEquals('pending', Cr1.State, 'Initial state pending');

    Cr2 := Client.CreateInstance(MachineName, 1, InstId, '{"customer":"alice"}', IdemCreateKey);
    CheckEquals(Cr1.InstanceId, Cr2.InstanceId, 'CreateInstance idempotent replay');
    CheckEquals(Cr1.WalOffset, Cr2.WalOffset, 'CreateInstance replay wal_offset');

    IdemPayKey := 'pk-' + UniqueSuffix;
    Ap1 := Client.ApplyEvent(InstId, 'PAY', '{"amount":42}', IdemPayKey);
    CheckEquals(True, Ap1.Applied, 'First ApplyEvent Applied=True');
    CheckEquals('pending', Ap1.FromState, 'FromState');
    CheckEquals('paid', Ap1.ToState, 'ToState');

    Ap2 := Client.ApplyEvent(InstId, 'PAY', '{"amount":42}', IdemPayKey);
    CheckEquals(False, Ap2.Applied, 'Replay ApplyEvent Applied=False');
    CheckEquals(Ap1.WalOffset, Ap2.WalOffset, 'Replay WalOffset matches');

    ConflictCaught := False;
    try
      Ap2 := Client.ApplyEvent(InstId, 'SHIP', '{}', IdemPayKey);
      if (not Ap2.Applied) and (Ap2.WalOffset = Ap1.WalOffset) then
      begin
        WriteLn('[NOTE] target server returned cached replay without IDEMPOTENCY_CONFLICT (pre-rstmdb#40)');
        ConflictCaught := True;
      end;
    except
      on E: ERstmdbServerError do
        ConflictCaught := IsIdempotencyConflict(E) and (not IsRetryable(E));
    end;
    Check(ConflictCaught, 'Mismatched idempotency key must raise IDEMPOTENCY_CONFLICT (or legacy replay on pre-#40)');
  finally
    Client.Free;
  end;
end;

procedure TestLiveBatchWatchWalStatsAndBackup;
var
  Client: TRstmdbClient;
  MachineName, Inst1, Inst2: string;
  Machines, EmptyArr: TRstmdbStringArray;
  WatchRes: TRstmdbWatchAllResult;
  UnwatchRes: TRstmdbUnwatchResult;
  Ops: TRstmdbBatchOpArray;
  BatchRes: TRstmdbBatchResult;
  Ev: TRstmdbStreamEvent;
  Tries, SeenEvents: Integer;
  Stats: TRstmdbWalStatsResult;
  BkpBegin: TRstmdbBackupBeginResult;
  BkpChunk: TRstmdbBackupChunkResult;
  BkpEnd: TRstmdbBackupEndResult;
  Downloaded, Offset: Int64;
begin
  Client := NewLiveClient;
  try
    Client.Connect;
    MachineName := 'pascal_batch_' + UniqueSuffix;
    Client.PutMachine(
      MachineName,
      1,
      '{"states":["pending","paid"],"initial":"pending",' +
      '"transitions":[{"from":"pending","event":"PAY","to":"paid"}]}'
    );

    Inst1 := 'b1-' + UniqueSuffix;
    Inst2 := 'b2-' + UniqueSuffix;
    Client.CreateInstance(MachineName, 1, Inst1, '{}');
    Client.CreateInstance(MachineName, 1, Inst2, '{}');

    SetLength(Machines, 1);
    Machines[0] := MachineName;
    SetLength(EmptyArr, 0);
    WatchRes := Client.WatchAll(Machines, EmptyArr, EmptyArr, EmptyArr, True, -1);
    Check(WatchRes.SubscriptionId <> '', 'WatchAll subscription_id');

    SetLength(Ops, 2);
    Ops[0].Op := OP_APPLY_EVENT;
    Ops[0].ParamsJson := Format('{"instance_id":"%s","event":"PAY","payload":{"n":1}}', [Inst1]);
    Ops[1].Op := OP_APPLY_EVENT;
    Ops[1].ParamsJson := Format('{"instance_id":"%s","event":"PAY","payload":{"n":2}}', [Inst2]);
    BatchRes := Client.Batch(Ops, bmAtomic);
    CheckEquals(Int64(2), Int64(Length(BatchRes.Results)), 'Atomic batch 2 results');
    CheckEquals('ok', BatchRes.Results[0].Status, 'Batch item 0 ok');
    CheckEquals('ok', BatchRes.Results[1].Status, 'Batch item 1 ok');

    SeenEvents := 0;
    for Tries := 1 to 40 do
    begin
      while Client.PollStreamEvent(Ev) do
      begin
        if Ev.Machine = MachineName then
          Inc(SeenEvents);
      end;
      if SeenEvents >= 2 then
        Break;
      Sleep(25);
    end;
    Check(SeenEvents >= 2, 'WatchAll must receive both batch transition events');

    UnwatchRes := Client.Unwatch(WatchRes.SubscriptionId);
    CheckEquals(True, UnwatchRes.Removed, 'Unwatch removed=True');

    Stats := Client.WalStats;
    Check(Stats.EntryCount > 0, 'WalStats EntryCount > 0');

    try
      BkpBegin := Client.BackupBegin('gzip');
      Check(BkpBegin.BackupId <> '', 'BackupBegin backup_id');
      Check(BkpBegin.ManifestJson <> '', 'BackupBegin manifest');
      Check(BkpBegin.TotalBytes > 0, 'BackupBegin total_bytes > 0');

      Downloaded := 0;
      Offset := 0;
      repeat
        BkpChunk := Client.BackupChunk(BkpBegin.BackupId, Offset, 1024 * 1024);
        Inc(Downloaded, Length(BkpChunk.Data));
        Inc(Offset, Length(BkpChunk.Data));
      until BkpChunk.Eof;
      CheckEquals(BkpBegin.TotalBytes, Downloaded, 'Downloaded backup bytes == total_bytes');

      BkpEnd := Client.BackupEnd(BkpBegin.BackupId);
      CheckEquals(True, BkpEnd.Ok, 'BackupEnd ok=True');
    except
      on E: ERstmdbServerError do
      begin
        if (E.Code = ERR_BAD_REQUEST) and (Pos('BACKUP_BEGIN', E.ErrorMessage) > 0) then
          WriteLn('[NOTE] BACKUP_BEGIN not supported by target server binary; skipped backup check')
        else
          raise;
      end;
    end;
  finally
    Client.Free;
  end;
end;

procedure RegisterLiveIntegrationTests;
begin
  Randomize;
  RegisterTest('Live.HandshakeInfoAndReplication', TestLiveHandshakeInfoAndReplication);
  RegisterTest('Live.MachineInstanceIdempotencyAndErrors', TestLiveMachineInstanceIdempotencyAndErrors);
  RegisterTest('Live.BatchWatchWalStatsAndBackup', TestLiveBatchWatchWalStatsAndBackup);
end;

end.
