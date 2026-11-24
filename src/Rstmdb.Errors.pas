unit Rstmdb.Errors;

{$I rstmdb.inc}

interface

uses
  SysUtils;

const
  { Protocol & request errors }
  ERR_UNSUPPORTED_PROTOCOL         = 'UNSUPPORTED_PROTOCOL';
  ERR_BAD_REQUEST                  = 'BAD_REQUEST';

  { Authentication errors }
  ERR_UNAUTHORIZED                 = 'UNAUTHORIZED';
  ERR_AUTH_FAILED                  = 'AUTH_FAILED';

  { Resource errors }
  ERR_NOT_FOUND                    = 'NOT_FOUND';
  ERR_MACHINE_NOT_FOUND            = 'MACHINE_NOT_FOUND';
  ERR_MACHINE_VERSION_EXISTS       = 'MACHINE_VERSION_EXISTS';
  ERR_MACHINE_VERSION_LIMIT_EXCEEDED = 'MACHINE_VERSION_LIMIT_EXCEEDED';
  ERR_INSTANCE_NOT_FOUND           = 'INSTANCE_NOT_FOUND';
  ERR_INSTANCE_EXISTS              = 'INSTANCE_EXISTS';

  { State machine errors }
  ERR_INVALID_TRANSITION           = 'INVALID_TRANSITION';
  ERR_GUARD_FAILED                 = 'GUARD_FAILED';
  ERR_GUARD_UNKNOWN                = 'GUARD_UNKNOWN';
  ERR_CONFLICT                     = 'CONFLICT';
  ERR_IDEMPOTENCY_CONFLICT         = 'IDEMPOTENCY_CONFLICT';

  { System errors }
  ERR_WAL_IO_ERROR                 = 'WAL_IO_ERROR';
  ERR_INTERNAL_ERROR               = 'INTERNAL_ERROR';
  ERR_RATE_LIMITED                 = 'RATE_LIMITED';

  { Replication errors }
  ERR_READ_ONLY_MODE               = 'READ_ONLY_MODE';
  ERR_REPLICATION_TIMEOUT          = 'REPLICATION_TIMEOUT';
  ERR_REPLICATION_ERROR            = 'REPLICATION_ERROR';

  { Client-side error codes }
  ERR_CONNECTION_FAILED            = 'CONNECTION_FAILED';
  ERR_CONNECTION_CLOSED            = 'CONNECTION_CLOSED';
  ERR_TIMEOUT                      = 'TIMEOUT';
  ERR_PROTOCOL_ERROR               = 'PROTOCOL_ERROR';

type
  ERstmdbError = class(Exception)
  private
    FCode: string;
    FErrorMessage: string;
    FRetryable: Boolean;
    FDetailsJson: string;
  public
    constructor Create(const ACode, AMessage: string;
      ARetryable: Boolean = False; const ADetailsJson: string = '');
    property Code: string read FCode;
    property ErrorMessage: string read FErrorMessage;
    property Retryable: Boolean read FRetryable;
    property DetailsJson: string read FDetailsJson;
  end;

  ERstmdbProtocolError = class(ERstmdbError);
  ERstmdbTransportError = class(ERstmdbError);
  ERstmdbConnectionError = ERstmdbTransportError;
  ERstmdbTimeoutError = class(ERstmdbError);
  ERstmdbServerError = class(ERstmdbError);

function IsNotFound(const Code: string): Boolean; overload;
function IsNotFound(E: Exception): Boolean; overload;

function IsInstanceNotFound(const Code: string): Boolean; overload;
function IsInstanceNotFound(E: Exception): Boolean; overload;

function IsMachineNotFound(const Code: string): Boolean; overload;
function IsMachineNotFound(E: Exception): Boolean; overload;

function IsInvalidTransition(const Code: string): Boolean; overload;
function IsInvalidTransition(E: Exception): Boolean; overload;

function IsGuardFailed(const Code: string): Boolean; overload;
function IsGuardFailed(E: Exception): Boolean; overload;

function IsGuardUnknown(const Code: string): Boolean; overload;
function IsGuardUnknown(E: Exception): Boolean; overload;

function IsConflict(const Code: string): Boolean; overload;
function IsConflict(E: Exception): Boolean; overload;

function IsIdempotencyConflict(const Code: string): Boolean; overload;
function IsIdempotencyConflict(E: Exception): Boolean; overload;

function IsReadOnlyMode(const Code: string): Boolean; overload;
function IsReadOnlyMode(E: Exception): Boolean; overload;

function IsReplicationTimeout(const Code: string): Boolean; overload;
function IsReplicationTimeout(E: Exception): Boolean; overload;

function IsReplicationError(const Code: string): Boolean; overload;
function IsReplicationError(E: Exception): Boolean; overload;

function IsRetryable(const Code: string): Boolean; overload;
function IsRetryable(E: Exception): Boolean; overload;

implementation

{ ERstmdbError }

constructor ERstmdbError.Create(const ACode, AMessage: string;
  ARetryable: Boolean; const ADetailsJson: string);
var
  DisplayMsg: string;
begin
  FCode := ACode;
  FErrorMessage := AMessage;
  FRetryable := ARetryable;
  FDetailsJson := ADetailsJson;
  if ACode <> '' then
    DisplayMsg := '[' + ACode + '] ' + AMessage
  else
    DisplayMsg := AMessage;
  inherited Create(DisplayMsg);
end;

function ExtractCode(E: Exception): string;
begin
  if E is ERstmdbError then
    Result := ERstmdbError(E).Code
  else
    Result := '';
end;

function IsNotFound(const Code: string): Boolean;
begin
  Result := (Code = ERR_NOT_FOUND) or
            (Code = ERR_INSTANCE_NOT_FOUND) or
            (Code = ERR_MACHINE_NOT_FOUND);
end;

function IsNotFound(E: Exception): Boolean;
begin
  Result := IsNotFound(ExtractCode(E));
end;

function IsInstanceNotFound(const Code: string): Boolean;
begin
  Result := Code = ERR_INSTANCE_NOT_FOUND;
end;

function IsInstanceNotFound(E: Exception): Boolean;
begin
  Result := IsInstanceNotFound(ExtractCode(E));
end;

function IsMachineNotFound(const Code: string): Boolean;
begin
  Result := Code = ERR_MACHINE_NOT_FOUND;
end;

function IsMachineNotFound(E: Exception): Boolean;
begin
  Result := IsMachineNotFound(ExtractCode(E));
end;

function IsInvalidTransition(const Code: string): Boolean;
begin
  Result := Code = ERR_INVALID_TRANSITION;
end;

function IsInvalidTransition(E: Exception): Boolean;
begin
  Result := IsInvalidTransition(ExtractCode(E));
end;

function IsGuardFailed(const Code: string): Boolean;
begin
  Result := Code = ERR_GUARD_FAILED;
end;

function IsGuardFailed(E: Exception): Boolean;
begin
  Result := IsGuardFailed(ExtractCode(E));
end;

function IsGuardUnknown(const Code: string): Boolean;
begin
  Result := Code = ERR_GUARD_UNKNOWN;
end;

function IsGuardUnknown(E: Exception): Boolean;
begin
  Result := IsGuardUnknown(ExtractCode(E));
end;

function IsConflict(const Code: string): Boolean;
begin
  Result := (Code = ERR_CONFLICT) or (Code = ERR_IDEMPOTENCY_CONFLICT);
end;

function IsConflict(E: Exception): Boolean;
begin
  Result := IsConflict(ExtractCode(E));
end;

function IsIdempotencyConflict(const Code: string): Boolean;
begin
  Result := Code = ERR_IDEMPOTENCY_CONFLICT;
end;

function IsIdempotencyConflict(E: Exception): Boolean;
begin
  Result := IsIdempotencyConflict(ExtractCode(E));
end;

function IsReadOnlyMode(const Code: string): Boolean;
begin
  Result := Code = ERR_READ_ONLY_MODE;
end;

function IsReadOnlyMode(E: Exception): Boolean;
begin
  Result := IsReadOnlyMode(ExtractCode(E));
end;

function IsReplicationTimeout(const Code: string): Boolean;
begin
  Result := Code = ERR_REPLICATION_TIMEOUT;
end;

function IsReplicationTimeout(E: Exception): Boolean;
begin
  Result := IsReplicationTimeout(ExtractCode(E));
end;

function IsReplicationError(const Code: string): Boolean;
begin
  Result := Code = ERR_REPLICATION_ERROR;
end;

function IsReplicationError(E: Exception): Boolean;
begin
  Result := IsReplicationError(ExtractCode(E));
end;

function IsRetryable(const Code: string): Boolean;
begin
  Result := (Code = ERR_WAL_IO_ERROR) or
            (Code = ERR_RATE_LIMITED) or
            (Code = ERR_INTERNAL_ERROR) or
            (Code = ERR_REPLICATION_TIMEOUT) or
            (Code = ERR_TIMEOUT);
end;

function IsRetryable(E: Exception): Boolean;
begin
  if E is ERstmdbError then
    Result := ERstmdbError(E).Retryable
  else
    Result := False;
end;

end.
