unit Rstmdb.Types;

{$I rstmdb.inc}

interface

uses
  SysUtils;

const
  RSTMDB_MAGIC = 'RCPX';
  RSTMDB_PROTOCOL_VERSION = 1;
  RSTMDB_HEADER_SIZE = 18;
  RSTMDB_MAX_PAYLOAD_SIZE = 16 * 1024 * 1024;
  RSTMDB_DEFAULT_PORT = 7401;

  RSTMDB_FLAG_CRC_PRESENT = $0001;
  RSTMDB_FLAG_COMPRESSED  = $0002;
  RSTMDB_FLAG_STREAM      = $0004;
  RSTMDB_FLAG_END_STREAM  = $0008;
  RSTMDB_FLAG_VALID_MASK  = $000F;

  { RCP v1 Operations }
  OP_HELLO              = 'HELLO';
  OP_AUTH               = 'AUTH';
  OP_PING               = 'PING';
  OP_BYE                = 'BYE';
  OP_INFO               = 'INFO';
  OP_REPLICATION_STATUS = 'REPLICATION_STATUS';
  OP_PUT_MACHINE        = 'PUT_MACHINE';
  OP_GET_MACHINE        = 'GET_MACHINE';
  OP_LIST_MACHINES      = 'LIST_MACHINES';
  OP_CREATE_INSTANCE    = 'CREATE_INSTANCE';
  OP_GET_INSTANCE       = 'GET_INSTANCE';
  OP_LIST_INSTANCES     = 'LIST_INSTANCES';
  OP_DELETE_INSTANCE    = 'DELETE_INSTANCE';
  OP_APPLY_EVENT        = 'APPLY_EVENT';
  OP_BATCH              = 'BATCH';
  OP_SNAPSHOT_INSTANCE  = 'SNAPSHOT_INSTANCE';
  OP_WAL_READ           = 'WAL_READ';
  OP_WAL_STATS          = 'WAL_STATS';
  OP_COMPACT            = 'COMPACT';
  OP_WATCH_INSTANCE     = 'WATCH_INSTANCE';
  OP_WATCH_ALL          = 'WATCH_ALL';
  OP_UNWATCH            = 'UNWATCH';
  OP_BACKUP_BEGIN       = 'BACKUP_BEGIN';
  OP_BACKUP_CHUNK       = 'BACKUP_CHUNK';
  OP_BACKUP_END         = 'BACKUP_END';
  OP_FLUSH_ALL          = 'FLUSH_ALL';

type
  TRstmdbStringArray = array of string;
  TRstmdbCardinalArray = array of Cardinal;
  TRstmdbBatchMode = (bmBestEffort, bmAtomic);

  TRstmdbLogProc = procedure(const Level, Msg: string);

  TRstmdbTlsOptions = record
    Enabled: Boolean;
    CaCertFile: string;
    ClientCertFile: string;
    ClientKeyFile: string;
    ClientKeyPassword: string;
    ServerName: string;
    InsecureSkipVerify: Boolean;
    class function Default: TRstmdbTlsOptions; static;
  end;

  TRstmdbOptions = record
    Host: string;
    Port: Word;
    ClientName: string;
    AuthToken: string;
    ConnectTimeoutMs: Integer;
    RequestTimeoutMs: Integer;
    Features: TRstmdbStringArray;
    Tls: TRstmdbTlsOptions;
    LogProc: TRstmdbLogProc;
    class function Default(const AHost: string = '127.0.0.1';
      APort: Word = RSTMDB_DEFAULT_PORT): TRstmdbOptions; static;
  end;

  TRstmdbHelloResult = record
    ProtocolVersion: Word;
    WireMode: string;
    ServerName: string;
    ServerVersion: string;
    Features: TRstmdbStringArray;
  end;

  TRstmdbServerInfo = record
    ServerName: string;
    ServerVersion: string;
    ProtocolVersion: Word;
    Features: TRstmdbStringArray;
    MaxFrameBytes: Int64;
    MaxBatchOps: Integer;
    WalWritable: Boolean;
    WalError: string;
    RawJson: string;
  end;

  TRstmdbPutMachineResult = record
    Machine: string;
    Version: Cardinal;
    StoredChecksum: string;
    Created: Boolean;
  end;

  TRstmdbMachineInfo = record
    Machine: string;
    Version: Cardinal;
    DefinitionJson: string;
    Checksum: string;
  end;

  TRstmdbMachineSummary = record
    Machine: string;
    Versions: TRstmdbCardinalArray;
  end;
  TRstmdbMachineSummaryArray = array of TRstmdbMachineSummary;

  TRstmdbCreateInstanceResult = record
    InstanceId: string;
    State: string;
    WalOffset: Int64;
  end;

  TRstmdbInstance = record
    InstanceId: string;
    Machine: string;
    Version: Cardinal;
    State: string;
    CtxJson: string;
    LastEventId: string;
    HasLastEventId: Boolean;
    LastWalOffset: Int64;
  end;

  TRstmdbInstanceSummary = record
    Id: string;
    Machine: string;
    Version: Cardinal;
    State: string;
    CreatedAt: Int64;
    UpdatedAt: Int64;
    LastWalOffset: Int64;
  end;
  TRstmdbInstanceSummaryArray = array of TRstmdbInstanceSummary;

  TRstmdbInstanceList = record
    Instances: TRstmdbInstanceSummaryArray;
    Total: Int64;
    HasMore: Boolean;
  end;

  TRstmdbDeleteInstanceResult = record
    InstanceId: string;
    Deleted: Boolean;
    WalOffset: Int64;
  end;

  TRstmdbApplyEventResult = record
    FromState: string;
    ToState: string;
    CtxJson: string;
    WalOffset: Int64;
    Applied: Boolean;
    EventId: string;
    HasEventId: Boolean;
  end;

  TRstmdbBatchOp = record
    Op: string;
    ParamsJson: string;
  end;
  TRstmdbBatchOpArray = array of TRstmdbBatchOp;

  TRstmdbBatchItemResult = record
    Status: string;
    ResultJson: string;
    ErrorCode: string;
    ErrorMessage: string;
    ErrorRetryable: Boolean;
    ErrorDetailsJson: string;
  end;
  TRstmdbBatchItemResultArray = array of TRstmdbBatchItemResult;

  TRstmdbBatchResult = record
    Results: TRstmdbBatchItemResultArray;
  end;

  TRstmdbWatchInstanceResult = record
    SubscriptionId: string;
    InstanceId: string;
    CurrentState: string;
    CurrentWalOffset: Int64;
  end;

  TRstmdbWatchAllResult = record
    SubscriptionId: string;
    WalOffset: Int64;
  end;

  TRstmdbUnwatchResult = record
    SubscriptionId: string;
    Removed: Boolean;
  end;

  TRstmdbStreamEvent = record
    SubscriptionId: string;
    InstanceId: string;
    Machine: string;
    Version: Cardinal;
    EventName: string;
    FromState: string;
    ToState: string;
    PayloadJson: string;
    CtxJson: string;
    WalOffset: Int64;
  end;
  TRstmdbStreamEventProc = procedure(const Ev: TRstmdbStreamEvent) of object;

  TRstmdbSnapshotResult = record
    InstanceId: string;
    SnapshotId: string;
    WalOffset: Int64;
    SizeBytes: Int64;
    Checksum: string;
  end;

  TRstmdbWalRecord = record
    Sequence: Int64;
    Offset: Int64;
    EntryJson: string;
  end;
  TRstmdbWalRecordArray = array of TRstmdbWalRecord;

  TRstmdbWalReadResult = record
    Records: TRstmdbWalRecordArray;
    NextOffset: Int64;
    HasNextOffset: Boolean;
  end;

  TRstmdbWalStatsResult = record
    EntryCount: Int64;
    SegmentCount: Int64;
    TotalSizeBytes: Int64;
    LatestOffset: Int64;
    HasLatestOffset: Boolean;
    BytesWritten: Int64;
    BytesRead: Int64;
    Writes: Int64;
    Reads: Int64;
    Fsyncs: Int64;
  end;

  TRstmdbCompactResult = record
    SnapshotsCreated: Int64;
    SegmentsDeleted: Int64;
    BytesReclaimed: Int64;
    TotalSnapshots: Int64;
    WalSegments: Int64;
  end;

  TRstmdbFlushAllResult = record
    Flushed: Boolean;
    InstancesRemoved: Int64;
    MachinesRemoved: Int64;
  end;

  TRstmdbReplicaInfo = record
    ReplicaId: string;
    LastAckedSequence: Int64;
    LagEntries: Int64;
  end;
  TRstmdbReplicaInfoArray = array of TRstmdbReplicaInfo;

  TRstmdbReplicationStatus = record
    Role: string;
    Mode: string;
    PrimarySequence: Int64;
    ConnectedReplicas: Int64;
    Replicas: TRstmdbReplicaInfoArray;
    Upstream: string;
    LastAppliedSequence: Int64;
    LagEntries: Int64;
    LagSeconds: Double;
    RawJson: string;
  end;

  TRstmdbBackupBeginResult = record
    BackupId: string;
    ManifestJson: string;
    TotalBytes: Int64;
    ChunkSize: Int64;
  end;

  TRstmdbBackupChunkResult = record
    Data: TBytes;
    Eof: Boolean;
  end;

  TRstmdbBackupEndResult = record
    Ok: Boolean;
  end;

function RstmdbBatchModeToStr(Mode: TRstmdbBatchMode): string;

implementation

function RstmdbBatchModeToStr(Mode: TRstmdbBatchMode): string;
begin
  case Mode of
    bmAtomic: Result := 'atomic';
  else
    Result := 'best_effort';
  end;
end;

{ TRstmdbTlsOptions }

class function TRstmdbTlsOptions.Default: TRstmdbTlsOptions;
begin
  Result := System.Default(TRstmdbTlsOptions);
end;

{ TRstmdbOptions }

class function TRstmdbOptions.Default(const AHost: string; APort: Word): TRstmdbOptions;
begin
  Result := System.Default(TRstmdbOptions);
  Result.Host := AHost;
  Result.Port := APort;
  Result.ClientName := 'rstmdb-pascal';
  Result.ConnectTimeoutMs := 5000;
  Result.RequestTimeoutMs := 30000;
  SetLength(Result.Features, 3);
  Result.Features[0] := 'idempotency';
  Result.Features[1] := 'durable_idempotency';
  Result.Features[2] := 'batch';
  Result.Tls := TRstmdbTlsOptions.Default;
end;

end.
