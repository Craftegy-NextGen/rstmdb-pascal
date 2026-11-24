unit Rstmdb.Client;

{$I rstmdb.inc}

interface

uses
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Json,
  Rstmdb.Transport,
  Rstmdb.Connection;

type
  TRstmdbClient = class
  private
    FConn: TRstmdbConnection;
    function GetNegotiatedFeatures: TRstmdbStringArray;
    function GetHelloResult: TRstmdbHelloResult;
    function GetOnStreamEvent: TRstmdbStreamEventProc;
    procedure SetOnStreamEvent(const Value: TRstmdbStreamEventProc);
  public
    constructor Create(const AHost: string = '127.0.0.1';
      APort: Word = RSTMDB_DEFAULT_PORT); overload;
    constructor Create(const AOptions: TRstmdbOptions); overload;
    constructor Create(const AOptions: TRstmdbOptions; ATransport: TRstmdbTransport;
      AOwnsTransport: Boolean = True); overload;
    destructor Destroy; override;

    procedure Connect;
    procedure Disconnect;
    function IsConnected: Boolean;

    function ServerInfo: TRstmdbHelloResult;
    function Ping: Boolean;
    function Info: TRstmdbServerInfo;
    function ReplicationStatus: TRstmdbReplicationStatus;

    function PutMachine(const Machine: string; Version: Cardinal;
      const DefinitionJson: string; const Checksum: string = ''): TRstmdbPutMachineResult;
    function GetMachine(const Machine: string; Version: Cardinal): TRstmdbMachineInfo;
    function ListMachines: TRstmdbMachineSummaryArray;

    function CreateInstance(const Machine: string; Version: Cardinal;
      const InstanceId: string = ''; const InitialCtxJson: string = '{}';
      const IdempotencyKey: string = ''): TRstmdbCreateInstanceResult;
    function GetInstance(const InstanceId: string): TRstmdbInstance;
    function ListInstances(const Machine: string = ''; const State: string = '';
      Limit: Integer = -1; Offset: Integer = -1): TRstmdbInstanceList;
    function DeleteInstance(const InstanceId: string;
      const IdempotencyKey: string = ''): TRstmdbDeleteInstanceResult;

    function ApplyEvent(const InstanceId, EventName: string;
      const PayloadJson: string = '{}';
      const IdempotencyKey: string = '';
      const ExpectedState: string = '';
      ExpectedWalOffset: Int64 = -1;
      const EventId: string = ''): TRstmdbApplyEventResult;

    function Batch(const Ops: TRstmdbBatchOpArray;
      Mode: TRstmdbBatchMode = bmBestEffort): TRstmdbBatchResult;

    function WatchInstance(const InstanceId: string; IncludeCtx: Boolean = True;
      FromOffset: Int64 = -1): TRstmdbWatchInstanceResult;
    function WatchAll(IncludeCtx: Boolean = True;
      FromOffset: Int64 = -1): TRstmdbWatchAllResult; overload;
    function WatchAll(const Machines, FromStates, ToStates, Events: TRstmdbStringArray;
      IncludeCtx: Boolean = True;
      FromOffset: Int64 = -1): TRstmdbWatchAllResult; overload;
    function Unwatch(const SubscriptionId: string): TRstmdbUnwatchResult;
    function PollStreamEvent(out Ev: TRstmdbStreamEvent): Boolean;

    function WalRead(FromOffset: Int64 = 0; Limit: Integer = -1): TRstmdbWalReadResult;
    function WalStats: TRstmdbWalStatsResult;
    function SnapshotInstance(const InstanceId: string): TRstmdbSnapshotResult;
    function Compact(ForceSnapshot: Boolean = False): TRstmdbCompactResult;

    function BackupBegin(const Compression: string = 'gzip'): TRstmdbBackupBeginResult;
    function BackupChunk(const BackupId: string; Offset: Int64;
      Len: Int64 = 4194304): TRstmdbBackupChunkResult;
    function BackupEnd(const BackupId: string): TRstmdbBackupEndResult;

    function FlushAll: TRstmdbFlushAllResult;

    property NegotiatedFeatures: TRstmdbStringArray read GetNegotiatedFeatures;
    property HelloResult: TRstmdbHelloResult read GetHelloResult;
    property OnStreamEvent: TRstmdbStreamEventProc read GetOnStreamEvent write SetOnStreamEvent;
  end;

implementation

{ TRstmdbClient }

constructor TRstmdbClient.Create(const AHost: string; APort: Word);
begin
  Create(TRstmdbOptions.Default(AHost, APort));
end;

constructor TRstmdbClient.Create(const AOptions: TRstmdbOptions);
begin
  inherited Create;
  FConn := TRstmdbConnection.Create(AOptions);
end;

constructor TRstmdbClient.Create(const AOptions: TRstmdbOptions;
  ATransport: TRstmdbTransport; AOwnsTransport: Boolean);
begin
  inherited Create;
  FConn := TRstmdbConnection.Create(AOptions, ATransport, AOwnsTransport);
end;

destructor TRstmdbClient.Destroy;
begin
  FConn.Free;
  inherited Destroy;
end;

procedure TRstmdbClient.Connect;
begin
  FConn.Connect;
end;

procedure TRstmdbClient.Disconnect;
begin
  FConn.Disconnect;
end;

function TRstmdbClient.IsConnected: Boolean;
begin
  Result := FConn.IsConnected;
end;

function TRstmdbClient.GetNegotiatedFeatures: TRstmdbStringArray;
begin
  Result := FConn.NegotiatedFeatures;
end;

function TRstmdbClient.GetHelloResult: TRstmdbHelloResult;
begin
  Result := FConn.HelloResult;
end;

function TRstmdbClient.ServerInfo: TRstmdbHelloResult;
begin
  Result := FConn.HelloResult;
end;

function TRstmdbClient.GetOnStreamEvent: TRstmdbStreamEventProc;
begin
  Result := FConn.OnStreamEvent;
end;

procedure TRstmdbClient.SetOnStreamEvent(const Value: TRstmdbStreamEventProc);
begin
  FConn.OnStreamEvent := Value;
end;

function TRstmdbClient.Ping: Boolean;
var
  ResJson: string;
  Doc: TRstmdbJsonDoc;
begin
  ResJson := FConn.SendRequest(OP_PING, '{}');
  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Result := JsonGetBool(Doc.Root, 'pong', False);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.Info: TRstmdbServerInfo;
var
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root, WalNode: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbServerInfo);
  ResJson := FConn.SendRequest(OP_INFO, '{}');
  Result.RawJson := ResJson;
  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.ServerName := JsonGetString(Root, 'server_name', '');
    Result.ServerVersion := JsonGetString(Root, 'server_version', '');
    Result.ProtocolVersion := Word(JsonGetInt64(Root, 'protocol_version', 1));
    Result.Features := JsonGetStringArray(Root, 'features');
    Result.MaxFrameBytes := JsonGetInt64(Root, 'max_frame_bytes', 0);
    Result.MaxBatchOps := Integer(JsonGetInt64(Root, 'max_batch_ops', 0));
    WalNode := JsonFind(Root, 'wal');
    if JsonIsObject(WalNode) then
    begin
      Result.WalWritable := JsonGetBool(WalNode, 'writable', True);
      Result.WalError := JsonGetString(WalNode, 'error', '');
    end
    else
      Result.WalWritable := True;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.ReplicationStatus: TRstmdbReplicationStatus;
var
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root, RepArr, Item: TRstmdbNativeJson;
  I, Cnt: Integer;
begin
  Result := System.Default(TRstmdbReplicationStatus);
  ResJson := FConn.SendRequest(OP_REPLICATION_STATUS, '{}');
  Result.RawJson := ResJson;
  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.Role := JsonGetString(Root, 'role', 'standalone');
    Result.Mode := JsonGetString(Root, 'mode', '');
    Result.PrimarySequence := JsonGetInt64(Root, 'primary_sequence', 0);
    Result.ConnectedReplicas := JsonGetInt64(Root, 'connected_replicas', 0);
    Result.Upstream := JsonGetString(Root, 'upstream', '');
    Result.LastAppliedSequence := JsonGetInt64(Root, 'last_applied_sequence', 0);
    Result.LagEntries := JsonGetInt64(Root, 'lag_entries', 0);
    Result.LagSeconds := JsonGetDouble(Root, 'lag_seconds', 0.0);

    RepArr := JsonFind(Root, 'replicas');
    if JsonIsArray(RepArr) then
    begin
      Cnt := JsonArrayCount(RepArr);
      SetLength(Result.Replicas, Cnt);
      for I := 0 to Cnt - 1 do
      begin
        Item := JsonArrayItem(RepArr, I);
        Result.Replicas[I].ReplicaId := JsonGetString(Item, 'replica_id', '');
        Result.Replicas[I].LastAckedSequence := JsonGetInt64(Item, 'last_acked_sequence', 0);
        Result.Replicas[I].LagEntries := JsonGetInt64(Item, 'lag_entries', 0);
      end;
    end;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.PutMachine(const Machine: string; Version: Cardinal;
  const DefinitionJson: string; const Checksum: string): TRstmdbPutMachineResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbPutMachineResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('machine', Machine);
    B.AddUInt64('version', Version);
    B.AddRaw('definition', DefinitionJson);
    if Checksum <> '' then
      B.AddString('checksum', Checksum);
    ResJson := FConn.SendRequest(OP_PUT_MACHINE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.Machine := JsonGetString(Root, 'machine', Machine);
    Result.Version := Cardinal(JsonGetInt64(Root, 'version', Int64(Version)));
    Result.StoredChecksum := JsonGetString(Root, 'stored_checksum', '');
    Result.Created := JsonGetBool(Root, 'created', False);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.GetMachine(const Machine: string;
  Version: Cardinal): TRstmdbMachineInfo;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbMachineInfo);
  Result.Machine := Machine;
  Result.Version := Version;
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('machine', Machine);
    B.AddUInt64('version', Version);
    ResJson := FConn.SendRequest(OP_GET_MACHINE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.DefinitionJson := JsonGetRaw(Root, 'definition', '{}');
    Result.Checksum := JsonGetString(Root, 'checksum', '');
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.ListMachines: TRstmdbMachineSummaryArray;
var
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  ItemsArr, ItemNode, VerArr, VerItem: TRstmdbNativeJson;
  I, J, Cnt, VerCnt: Integer;
begin
  Result := nil;
  ResJson := FConn.SendRequest(OP_LIST_MACHINES, '{}');
  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    ItemsArr := JsonFind(Doc.Root, 'items');
    if not JsonIsArray(ItemsArr) then
      Exit;
    Cnt := JsonArrayCount(ItemsArr);
    SetLength(Result, Cnt);
    for I := 0 to Cnt - 1 do
    begin
      ItemNode := JsonArrayItem(ItemsArr, I);
      Result[I].Machine := JsonGetString(ItemNode, 'machine', '');
      VerArr := JsonFind(ItemNode, 'versions');
      if JsonIsArray(VerArr) then
      begin
        VerCnt := JsonArrayCount(VerArr);
        SetLength(Result[I].Versions, VerCnt);
        for J := 0 to VerCnt - 1 do
        begin
          VerItem := JsonArrayItem(VerArr, J);
          if (VerItem <> nil) and (not JsonIsNull(VerItem)) then
          begin
            {$IFDEF FPC}
            Result[I].Versions[J] := Cardinal(VerItem.AsInt64);
            {$ELSE}
            if VerItem is TJSONNumber then
              Result[I].Versions[J] := Cardinal(TJSONNumber(VerItem).AsInt64)
            else
              Result[I].Versions[J] := 0;
            {$ENDIF}
          end;
        end;
      end;
    end;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.CreateInstance(const Machine: string; Version: Cardinal;
  const InstanceId, InitialCtxJson, IdempotencyKey: string): TRstmdbCreateInstanceResult;
var
  B: TRstmdbJsonBuilder;
  ResJson, Ctx: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbCreateInstanceResult);
  Ctx := Trim(InitialCtxJson);
  if Ctx = '' then
    Ctx := '{}';

  B := TRstmdbJsonBuilder.CreateObject;
  try
    if InstanceId <> '' then
      B.AddString('instance_id', InstanceId);
    B.AddString('machine', Machine);
    B.AddUInt64('version', Version);
    B.AddRaw('initial_ctx', Ctx);
    if IdempotencyKey <> '' then
      B.AddString('idempotency_key', IdempotencyKey);
    ResJson := FConn.SendRequest(OP_CREATE_INSTANCE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.InstanceId := JsonGetString(Root, 'instance_id', '');
    Result.State := JsonGetString(Root, 'state', '');
    Result.WalOffset := JsonGetInt64(Root, 'wal_offset', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.GetInstance(const InstanceId: string): TRstmdbInstance;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbInstance);
  Result.InstanceId := InstanceId;
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('instance_id', InstanceId);
    ResJson := FConn.SendRequest(OP_GET_INSTANCE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.Machine := JsonGetString(Root, 'machine', '');
    Result.Version := Cardinal(JsonGetInt64(Root, 'version', 0));
    Result.State := JsonGetString(Root, 'state', '');
    Result.CtxJson := JsonGetRaw(Root, 'ctx', '{}');
    Result.HasLastEventId := JsonTryGetString(Root, 'last_event_id', Result.LastEventId);
    Result.LastWalOffset := JsonGetInt64(Root, 'last_wal_offset', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.ListInstances(const Machine, State: string;
  Limit, Offset: Integer): TRstmdbInstanceList;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root, Arr, Item: TRstmdbNativeJson;
  I, Cnt: Integer;
begin
  Result := System.Default(TRstmdbInstanceList);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    if Machine <> '' then
      B.AddString('machine', Machine);
    if State <> '' then
      B.AddString('state', State);
    if Limit >= 0 then
      B.AddInt64('limit', Limit);
    if Offset >= 0 then
      B.AddInt64('offset', Offset);
    ResJson := FConn.SendRequest(OP_LIST_INSTANCES, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.Total := JsonGetInt64(Root, 'total', 0);
    Result.HasMore := JsonGetBool(Root, 'has_more', False);
    Arr := JsonFind(Root, 'instances');
    if JsonIsArray(Arr) then
    begin
      Cnt := JsonArrayCount(Arr);
      SetLength(Result.Instances, Cnt);
      for I := 0 to Cnt - 1 do
      begin
        Item := JsonArrayItem(Arr, I);
        Result.Instances[I].Id := JsonGetString(Item, 'id', '');
        Result.Instances[I].Machine := JsonGetString(Item, 'machine', '');
        Result.Instances[I].Version := Cardinal(JsonGetInt64(Item, 'version', 0));
        Result.Instances[I].State := JsonGetString(Item, 'state', '');
        Result.Instances[I].CreatedAt := JsonGetInt64(Item, 'created_at', 0);
        Result.Instances[I].UpdatedAt := JsonGetInt64(Item, 'updated_at', 0);
        Result.Instances[I].LastWalOffset := JsonGetInt64(Item, 'last_wal_offset', 0);
      end;
    end;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.DeleteInstance(const InstanceId,
  IdempotencyKey: string): TRstmdbDeleteInstanceResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbDeleteInstanceResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('instance_id', InstanceId);
    if IdempotencyKey <> '' then
      B.AddString('idempotency_key', IdempotencyKey);
    ResJson := FConn.SendRequest(OP_DELETE_INSTANCE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.InstanceId := JsonGetString(Root, 'instance_id', InstanceId);
    Result.Deleted := JsonGetBool(Root, 'deleted', False);
    Result.WalOffset := JsonGetInt64(Root, 'wal_offset', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.ApplyEvent(const InstanceId, EventName, PayloadJson,
  IdempotencyKey, ExpectedState: string; ExpectedWalOffset: Int64;
  const EventId: string): TRstmdbApplyEventResult;
var
  B: TRstmdbJsonBuilder;
  ResJson, Payload: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbApplyEventResult);
  Payload := Trim(PayloadJson);
  if Payload = '' then
    Payload := '{}';

  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('instance_id', InstanceId);
    B.AddString('event', EventName);
    B.AddRaw('payload', Payload);
    if ExpectedState <> '' then
      B.AddString('expected_state', ExpectedState);
    if ExpectedWalOffset >= 0 then
      B.AddInt64('expected_wal_offset', ExpectedWalOffset);
    if EventId <> '' then
      B.AddString('event_id', EventId);
    if IdempotencyKey <> '' then
      B.AddString('idempotency_key', IdempotencyKey);
    ResJson := FConn.SendRequest(OP_APPLY_EVENT, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.FromState := JsonGetString(Root, 'from_state', '');
    Result.ToState := JsonGetString(Root, 'to_state', '');
    Result.CtxJson := JsonGetRaw(Root, 'ctx', '{}');
    Result.WalOffset := JsonGetInt64(Root, 'wal_offset', 0);
    Result.Applied := JsonGetBool(Root, 'applied', True);
    Result.HasEventId := JsonTryGetString(Root, 'event_id', Result.EventId);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.Batch(const Ops: TRstmdbBatchOpArray;
  Mode: TRstmdbBatchMode): TRstmdbBatchResult;
var
  B, OpsArr, OpObj: TRstmdbJsonBuilder;
  I, Cnt: Integer;
  ResJson, OpParams: string;
  Doc: TRstmdbJsonDoc;
  ArrNode, ItemNode, ErrNode, DetNode: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbBatchResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('mode', RstmdbBatchModeToStr(Mode));
    OpsArr := TRstmdbJsonBuilder.CreateArray;
    try
      for I := 0 to Length(Ops) - 1 do
      begin
        OpParams := Trim(Ops[I].ParamsJson);
        if OpParams = '' then
          OpParams := '{}';
        OpObj := TRstmdbJsonBuilder.CreateObject;
        try
          OpObj.AddString('op', Ops[I].Op);
          OpObj.AddRaw('params', OpParams);
          OpsArr.AddArrayRawItem(OpObj.ToJson);
        finally
          OpObj.Free;
        end;
      end;
      B.AddRaw('ops', OpsArr.ToJson);
    finally
      OpsArr.Free;
    end;
    ResJson := FConn.SendRequest(OP_BATCH, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    ArrNode := JsonFind(Doc.Root, 'results');
    if JsonIsArray(ArrNode) then
    begin
      Cnt := JsonArrayCount(ArrNode);
      SetLength(Result.Results, Cnt);
      for I := 0 to Cnt - 1 do
      begin
        ItemNode := JsonArrayItem(ArrNode, I);
        Result.Results[I].Status := JsonGetString(ItemNode, 'status', '');
        if Result.Results[I].Status = 'ok' then
          Result.Results[I].ResultJson := JsonGetRaw(ItemNode, 'result', '{}')
        else
        begin
          ErrNode := JsonFind(ItemNode, 'error');
          if JsonIsObject(ErrNode) then
          begin
            Result.Results[I].ErrorCode := JsonGetString(ErrNode, 'code', '');
            Result.Results[I].ErrorMessage := JsonGetString(ErrNode, 'message', '');
            Result.Results[I].ErrorRetryable := JsonGetBool(ErrNode, 'retryable', False);
            DetNode := JsonFind(ErrNode, 'details');
            if DetNode <> nil then
              Result.Results[I].ErrorDetailsJson := JsonNodeToString(DetNode);
          end;
        end;
      end;
    end;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.WatchInstance(const InstanceId: string; IncludeCtx: Boolean;
  FromOffset: Int64): TRstmdbWatchInstanceResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbWatchInstanceResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('instance_id', InstanceId);
    B.AddBool('include_ctx', IncludeCtx);
    if FromOffset >= 0 then
      B.AddInt64('from_offset', FromOffset);
    ResJson := FConn.SendRequest(OP_WATCH_INSTANCE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.SubscriptionId := JsonGetString(Root, 'subscription_id', '');
    Result.InstanceId := JsonGetString(Root, 'instance_id', InstanceId);
    Result.CurrentState := JsonGetString(Root, 'current_state', '');
    Result.CurrentWalOffset := JsonGetInt64(Root, 'current_wal_offset', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.WatchAll(IncludeCtx: Boolean;
  FromOffset: Int64): TRstmdbWatchAllResult;
var
  EmptyArr: TRstmdbStringArray;
begin
  SetLength(EmptyArr, 0);
  Result := WatchAll(EmptyArr, EmptyArr, EmptyArr, EmptyArr, IncludeCtx, FromOffset);
end;

function TRstmdbClient.WatchAll(const Machines, FromStates, ToStates,
  Events: TRstmdbStringArray; IncludeCtx: Boolean;
  FromOffset: Int64): TRstmdbWatchAllResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbWatchAllResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddBool('include_ctx', IncludeCtx);
    if FromOffset >= 0 then
      B.AddInt64('from_offset', FromOffset);
    if Length(Machines) > 0 then
      B.AddStringArray('machines', Machines);
    if Length(FromStates) > 0 then
      B.AddStringArray('from_states', FromStates);
    if Length(ToStates) > 0 then
      B.AddStringArray('to_states', ToStates);
    if Length(Events) > 0 then
      B.AddStringArray('events', Events);
    ResJson := FConn.SendRequest(OP_WATCH_ALL, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.SubscriptionId := JsonGetString(Root, 'subscription_id', '');
    Result.WalOffset := JsonGetInt64(Root, 'wal_offset', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.Unwatch(const SubscriptionId: string): TRstmdbUnwatchResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbUnwatchResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('subscription_id', SubscriptionId);
    ResJson := FConn.SendRequest(OP_UNWATCH, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.SubscriptionId := JsonGetString(Root, 'subscription_id', SubscriptionId);
    Result.Removed := JsonGetBool(Root, 'removed', False);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.PollStreamEvent(out Ev: TRstmdbStreamEvent): Boolean;
begin
  Result := FConn.PollStreamEvent(Ev);
end;

function TRstmdbClient.WalRead(FromOffset: Int64;
  Limit: Integer): TRstmdbWalReadResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root, Arr, Item: TRstmdbNativeJson;
  I, Cnt: Integer;
begin
  Result := System.Default(TRstmdbWalReadResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddInt64('from_offset', FromOffset);
    if Limit >= 0 then
      B.AddInt64('limit', Limit);
    ResJson := FConn.SendRequest(OP_WAL_READ, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.HasNextOffset := JsonTryGetInt64(Root, 'next_offset', Result.NextOffset);
    Arr := JsonFind(Root, 'records');
    if JsonIsArray(Arr) then
    begin
      Cnt := JsonArrayCount(Arr);
      SetLength(Result.Records, Cnt);
      for I := 0 to Cnt - 1 do
      begin
        Item := JsonArrayItem(Arr, I);
        Result.Records[I].Sequence := JsonGetInt64(Item, 'sequence', 0);
        Result.Records[I].Offset := JsonGetInt64(Item, 'offset', 0);
        Result.Records[I].EntryJson := JsonGetRaw(Item, 'entry', '{}');
      end;
    end;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.WalStats: TRstmdbWalStatsResult;
var
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root, IoNode: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbWalStatsResult);
  ResJson := FConn.SendRequest(OP_WAL_STATS, '{}');
  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.EntryCount := JsonGetInt64(Root, 'entry_count', 0);
    Result.SegmentCount := JsonGetInt64(Root, 'segment_count', 0);
    Result.TotalSizeBytes := JsonGetInt64(Root, 'total_size_bytes', 0);
    Result.HasLatestOffset := JsonTryGetInt64(Root, 'latest_offset', Result.LatestOffset);
    IoNode := JsonFind(Root, 'io_stats');
    if JsonIsObject(IoNode) then
    begin
      Result.BytesWritten := JsonGetInt64(IoNode, 'bytes_written', 0);
      Result.BytesRead := JsonGetInt64(IoNode, 'bytes_read', 0);
      Result.Writes := JsonGetInt64(IoNode, 'writes', 0);
      Result.Reads := JsonGetInt64(IoNode, 'reads', 0);
      Result.Fsyncs := JsonGetInt64(IoNode, 'fsyncs', 0);
    end;
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.SnapshotInstance(
  const InstanceId: string): TRstmdbSnapshotResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbSnapshotResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('instance_id', InstanceId);
    ResJson := FConn.SendRequest(OP_SNAPSHOT_INSTANCE, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.InstanceId := JsonGetString(Root, 'instance_id', InstanceId);
    Result.SnapshotId := JsonGetString(Root, 'snapshot_id', '');
    Result.WalOffset := JsonGetInt64(Root, 'wal_offset', 0);
    Result.SizeBytes := JsonGetInt64(Root, 'size_bytes', 0);
    Result.Checksum := JsonGetString(Root, 'checksum', '');
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.Compact(ForceSnapshot: Boolean): TRstmdbCompactResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbCompactResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddBool('force_snapshot', ForceSnapshot);
    ResJson := FConn.SendRequest(OP_COMPACT, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.SnapshotsCreated := JsonGetInt64(Root, 'snapshots_created', 0);
    Result.SegmentsDeleted := JsonGetInt64(Root, 'segments_deleted', 0);
    Result.BytesReclaimed := JsonGetInt64(Root, 'bytes_reclaimed', 0);
    Result.TotalSnapshots := JsonGetInt64(Root, 'total_snapshots', 0);
    Result.WalSegments := JsonGetInt64(Root, 'wal_segments', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.BackupBegin(
  const Compression: string): TRstmdbBackupBeginResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbBackupBeginResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    if Compression <> '' then
      B.AddString('compression', Compression);
    ResJson := FConn.SendRequest(OP_BACKUP_BEGIN, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.BackupId := JsonGetString(Root, 'backup_id', '');
    Result.ManifestJson := JsonGetRaw(Root, 'manifest', '{}');
    Result.TotalBytes := JsonGetInt64(Root, 'total_bytes', 0);
    Result.ChunkSize := JsonGetInt64(Root, 'chunk_size', 0);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.BackupChunk(const BackupId: string; Offset,
  Len: Int64): TRstmdbBackupChunkResult;
var
  B: TRstmdbJsonBuilder;
  ResJson, Encoded: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbBackupChunkResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('backup_id', BackupId);
    B.AddInt64('offset', Offset);
    B.AddInt64('len', Len);
    ResJson := FConn.SendRequest(OP_BACKUP_CHUNK, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Encoded := JsonGetString(Root, 'bytes', '');
    Result.Data := Base64DecodeBytes(Encoded);
    Result.Eof := JsonGetBool(Root, 'eof', False);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.BackupEnd(const BackupId: string): TRstmdbBackupEndResult;
var
  B: TRstmdbJsonBuilder;
  ResJson: string;
  Doc: TRstmdbJsonDoc;
begin
  Result := System.Default(TRstmdbBackupEndResult);
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('backup_id', BackupId);
    ResJson := FConn.SendRequest(OP_BACKUP_END, B.ToJson);
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Result.Ok := JsonGetBool(Doc.Root, 'ok', True);
  finally
    Doc.Free;
  end;
end;

function TRstmdbClient.FlushAll: TRstmdbFlushAllResult;
var
  ResJson: string;
  Doc: TRstmdbJsonDoc;
  Root: TRstmdbNativeJson;
begin
  Result := System.Default(TRstmdbFlushAllResult);
  ResJson := FConn.SendRequest(OP_FLUSH_ALL, '{}');
  Doc := TRstmdbJsonDoc.ParseString(ResJson);
  try
    Root := Doc.Root;
    Result.Flushed := JsonGetBool(Root, 'flushed', False);
    Result.InstancesRemoved := JsonGetInt64(Root, 'instances_removed', 0);
    Result.MachinesRemoved := JsonGetInt64(Root, 'machines_removed', 0);
  finally
    Doc.Free;
  end;
end;

end.
