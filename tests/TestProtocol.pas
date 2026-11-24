unit TestProtocol;

{$I rstmdb.inc}

interface

procedure RegisterProtocolTests;

implementation

uses
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Protocol,
  Rstmdb.TestRunner;

function AsciiBytes(const S: string): TBytes;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(S));
  for I := 1 to Length(S) do
    Result[I - 1] := Byte(Ord(S[I]) and $FF);
end;

procedure TestCrc32cVector;
var
  Data: TBytes;
  Crc: Cardinal;
begin
  Data := AsciiBytes('123456789');
  Crc := RstmdbCrc32c(Data);
  CheckEquals(Cardinal($E3069283), Crc, 'CRC32C("123456789")');
  CheckEquals(Cardinal($00000000), RstmdbCrc32c(nil), 'CRC32C(empty)');
end;

procedure TestFrameRoundTrip;
var
  Payload, Wire: TBytes;
  Frame: TRstmdbFrame;
begin
  Payload := AsciiBytes('{"type":"request","id":"1","op":"PING","params":{}}');
  Wire := EncodeFrame(Payload, RSTMDB_FLAG_CRC_PRESENT);
  CheckEquals(Int64(RSTMDB_HEADER_SIZE + Length(Payload)), Int64(Length(Wire)), 'Wire length');
  Check(TryDecodeFrame(Wire, Frame), 'TryDecodeFrame');
  CheckEquals(Int64(0), Int64(Length(Wire)), 'Buffer drained');
  CheckEquals(Cardinal(RSTMDB_PROTOCOL_VERSION), Cardinal(Frame.Version), 'Version');
  CheckEquals(Cardinal(RSTMDB_FLAG_CRC_PRESENT), Cardinal(Frame.Flags), 'Flags');
  CheckEquals(Int64(Length(Payload)), Int64(Length(Frame.Payload)), 'Payload length');
  Check(CompareMem(@Payload[0], @Frame.Payload[0], Length(Payload)), 'Payload bytes');
end;

procedure TestFrameHeaderExtensionSkip;
var
  Payload, Ext, Wire: TBytes;
  Frame: TRstmdbFrame;
begin
  Payload := AsciiBytes('{"ok":true}');
  Ext := AsciiBytes('ext_data');
  Wire := EncodeFrame(Payload, RSTMDB_FLAG_CRC_PRESENT or RSTMDB_FLAG_STREAM, Ext);
  Check(TryDecodeFrame(Wire, Frame), 'TryDecodeFrame with ext');
  CheckEquals(Int64(Length(Ext)), Int64(Length(Frame.HeaderExtension)), 'Ext len');
  CheckEquals(Int64(Length(Payload)), Int64(Length(Frame.Payload)), 'Payload len');
end;

procedure TestFrameFragmentationAndMultiFrame;
var
  P1, P2, W1, W2, Buf, Partial: TBytes;
  F1, F2: TRstmdbFrame;
begin
  P1 := AsciiBytes('{"id":"1"}');
  P2 := AsciiBytes('{"id":"2"}');
  W1 := EncodeFrame(P1);
  W2 := EncodeFrame(P2);

  SetLength(Partial, 10);
  Move(W1[0], Partial[0], 10);
  Check(not TryDecodeFrame(Partial, F1), 'Incomplete frame should return False');
  CheckEquals(Int64(10), Int64(Length(Partial)), 'Partial buffer preserved');

  SetLength(Buf, Length(W1) + Length(W2));
  Move(W1[0], Buf[0], Length(W1));
  Move(W2[0], Buf[Length(W1)], Length(W2));
  Check(TryDecodeFrame(Buf, F1), 'Decode frame 1');
  Check(TryDecodeFrame(Buf, F2), 'Decode frame 2');
  CheckEquals(Int64(0), Int64(Length(Buf)), 'Buffer empty after two frames');
end;

procedure TestBadMagicRejected;
var
  Buf: TBytes;
  Frame: TRstmdbFrame;
  Raised: Boolean;
begin
  SetLength(Buf, RSTMDB_HEADER_SIZE);
  FillChar(Buf[0], RSTMDB_HEADER_SIZE, 0);
  Buf[0] := Ord('B'); Buf[1] := Ord('A'); Buf[2] := Ord('D'); Buf[3] := Ord('X');
  Buf[5] := 1;
  Raised := False;
  try
    TryDecodeFrame(Buf, Frame);
  except
    on E: ERstmdbProtocolError do
      Raised := True;
  end;
  Check(Raised, 'Bad magic must raise ERstmdbProtocolError');
end;

procedure TestUnsupportedVersionRejected;
var
  Buf: TBytes;
  Frame: TRstmdbFrame;
  RaisedCode: string;
begin
  SetLength(Buf, RSTMDB_HEADER_SIZE);
  FillChar(Buf[0], RSTMDB_HEADER_SIZE, 0);
  Buf[0] := Ord('R'); Buf[1] := Ord('C'); Buf[2] := Ord('P'); Buf[3] := Ord('X');
  Buf[5] := 99;
  RaisedCode := '';
  try
    TryDecodeFrame(Buf, Frame);
  except
    on E: ERstmdbProtocolError do
      RaisedCode := E.Code;
  end;
  CheckEquals(ERR_UNSUPPORTED_PROTOCOL, RaisedCode, 'Unsupported version code');
end;

procedure TestReservedFlagsRejected;
var
  Buf: TBytes;
  Frame: TRstmdbFrame;
  Raised: Boolean;
begin
  SetLength(Buf, RSTMDB_HEADER_SIZE);
  FillChar(Buf[0], RSTMDB_HEADER_SIZE, 0);
  Buf[0] := Ord('R'); Buf[1] := Ord('C'); Buf[2] := Ord('P'); Buf[3] := Ord('X');
  Buf[5] := 1;
  Buf[6] := $01; { reserved bit outside $000F }
  Raised := False;
  try
    TryDecodeFrame(Buf, Frame);
  except
    on E: ERstmdbProtocolError do
      Raised := True;
  end;
  Check(Raised, 'Reserved flags must raise ERstmdbProtocolError');
end;

procedure TestOversizedPayloadRejectedBeforeAlloc;
var
  Buf: TBytes;
  Frame: TRstmdbFrame;
  TooBig: Cardinal;
  Raised: Boolean;
begin
  SetLength(Buf, RSTMDB_HEADER_SIZE);
  FillChar(Buf[0], RSTMDB_HEADER_SIZE, 0);
  Buf[0] := Ord('R'); Buf[1] := Ord('C'); Buf[2] := Ord('P'); Buf[3] := Ord('X');
  Buf[5] := 1;
  Buf[7] := RSTMDB_FLAG_CRC_PRESENT;
  TooBig := RSTMDB_MAX_PAYLOAD_SIZE + 1;
  Buf[10] := Byte((TooBig shr 24) and $FF);
  Buf[11] := Byte((TooBig shr 16) and $FF);
  Buf[12] := Byte((TooBig shr 8) and $FF);
  Buf[13] := Byte(TooBig and $FF);
  Raised := False;
  try
    TryDecodeFrame(Buf, Frame);
  except
    on E: ERstmdbProtocolError do
      Raised := True;
  end;
  Check(Raised, 'Payload > 16 MiB must raise ERstmdbProtocolError before reading body');
end;

procedure TestBadCrcRejected;
var
  Wire: TBytes;
  Frame: TRstmdbFrame;
  Raised: Boolean;
begin
  Wire := EncodeFrame(AsciiBytes('{"test":"data"}'));
  Wire[Length(Wire) - 1] := Wire[Length(Wire) - 1] xor $FF;
  Raised := False;
  try
    TryDecodeFrame(Wire, Frame);
  except
    on E: ERstmdbProtocolError do
      Raised := True;
  end;
  Check(Raised, 'Corrupted payload must fail CRC32C check');
end;

procedure TestOpenErrorCodeAndPredicates;
var
  Err: ERstmdbServerError;
begin
  Err := ERstmdbServerError.Create('FUTURE_ERROR_CODE', 'Something new', True, '{"hint":1}');
  try
    CheckEquals('FUTURE_ERROR_CODE', Err.Code, 'Future code preserved');
    CheckEquals('Something new', Err.ErrorMessage, 'Error message preserved');
    CheckEquals(True, Err.Retryable, 'Retryable preserved');
    CheckEquals('{"hint":1}', Err.DetailsJson, 'DetailsJson preserved');
    Check(IsRetryable(Err), 'IsRetryable(Err) must honor Retryable flag');
    Check(not IsNotFound(Err), 'Unknown code is not NotFound');
  finally
    Err.Free;
  end;

  Check(IsNotFound(ERR_NOT_FOUND));
  Check(IsNotFound(ERR_INSTANCE_NOT_FOUND));
  Check(IsNotFound(ERR_MACHINE_NOT_FOUND));
  Check(IsInstanceNotFound(ERR_INSTANCE_NOT_FOUND));
  Check(IsMachineNotFound(ERR_MACHINE_NOT_FOUND));
  Check(IsInvalidTransition(ERR_INVALID_TRANSITION));
  Check(IsGuardFailed(ERR_GUARD_FAILED));
  Check(IsGuardUnknown(ERR_GUARD_UNKNOWN));
  Check(IsConflict(ERR_CONFLICT));
  Check(IsConflict(ERR_IDEMPOTENCY_CONFLICT));
  Check(IsIdempotencyConflict(ERR_IDEMPOTENCY_CONFLICT));
  Check(IsReadOnlyMode(ERR_READ_ONLY_MODE));
  Check(IsReplicationTimeout(ERR_REPLICATION_TIMEOUT));
  Check(IsReplicationError(ERR_REPLICATION_ERROR));
  Check(IsRetryable(ERR_WAL_IO_ERROR));
  Check(IsRetryable(ERR_RATE_LIMITED));
  Check(IsRetryable(ERR_INTERNAL_ERROR));
  Check(IsRetryable(ERR_REPLICATION_TIMEOUT));
  Check(not IsRetryable(ERR_IDEMPOTENCY_CONFLICT));
  Check(not IsRetryable(ERR_GUARD_UNKNOWN));
  Check(not IsRetryable(ERR_READ_ONLY_MODE));
end;

procedure RegisterProtocolTests;
begin
  RegisterTest('Protocol.CRC32CVector', TestCrc32cVector);
  RegisterTest('Protocol.FrameRoundTrip', TestFrameRoundTrip);
  RegisterTest('Protocol.FrameHeaderExtensionSkip', TestFrameHeaderExtensionSkip);
  RegisterTest('Protocol.FrameFragmentationAndMultiFrame', TestFrameFragmentationAndMultiFrame);
  RegisterTest('Protocol.BadMagicRejected', TestBadMagicRejected);
  RegisterTest('Protocol.UnsupportedVersionRejected', TestUnsupportedVersionRejected);
  RegisterTest('Protocol.ReservedFlagsRejected', TestReservedFlagsRejected);
  RegisterTest('Protocol.OversizedPayloadRejected', TestOversizedPayloadRejectedBeforeAlloc);
  RegisterTest('Protocol.BadCrcRejected', TestBadCrcRejected);
  RegisterTest('Errors.OpenErrorCodeAndPredicates', TestOpenErrorCodeAndPredicates);
end;

end.
