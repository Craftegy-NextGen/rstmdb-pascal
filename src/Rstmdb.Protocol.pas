unit Rstmdb.Protocol;

{$I rstmdb.inc}

interface

uses
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Errors;

type
  TRstmdbFrameHeader = record
    Version: Word;
    Flags: Word;
    HeaderLen: Word;
    PayloadLen: Cardinal;
    Crc32c: Cardinal;
  end;

  TRstmdbFrame = record
    Version: Word;
    Flags: Word;
    HeaderExtension: TBytes;
    Payload: TBytes;
  end;

function RstmdbCrc32c(const Data: TBytes): Cardinal; overload;
function RstmdbCrc32c(Data: PByte; Len: Integer): Cardinal; overload;

function EncodeFrameHeader(const Header: TRstmdbFrameHeader): TBytes;
function DecodeFrameHeader(const Data: TBytes; Offset: Integer = 0): TRstmdbFrameHeader;

function EncodeFrame(const Payload: TBytes;
  Flags: Word = $0001;
  const HeaderExtension: TBytes = nil): TBytes;

function TryDecodeFrame(var Buffer: TBytes; out Frame: TRstmdbFrame): Boolean;

implementation

const
  CRC32C_POLY = Cardinal($82F63B78);

var
  Crc32cTable: array[0..255] of Cardinal;

procedure InitCrc32cTable;
var
  I, J: Integer;
  C: Cardinal;
begin
  for I := 0 to 255 do
  begin
    C := Cardinal(I);
    for J := 0 to 7 do
    begin
      if (C and 1) <> 0 then
        C := (C shr 1) xor CRC32C_POLY
      else
        C := C shr 1;
    end;
    Crc32cTable[I] := C;
  end;
end;

function RstmdbCrc32c(Data: PByte; Len: Integer): Cardinal;
var
  I: Integer;
  C: Cardinal;
  P: PByte;
begin
  C := $FFFFFFFF;
  P := Data;
  for I := 0 to Len - 1 do
  begin
    C := (C shr 8) xor Crc32cTable[(C xor P^) and $FF];
    Inc(P);
  end;
  Result := C xor $FFFFFFFF;
end;

function RstmdbCrc32c(const Data: TBytes): Cardinal;
begin
  if Length(Data) = 0 then
    Result := RstmdbCrc32c(nil, 0)
  else
    Result := RstmdbCrc32c(@Data[0], Length(Data));
end;

procedure WriteU16BE(var Buf: TBytes; Offset: Integer; Value: Word);
begin
  Buf[Offset] := Byte((Value shr 8) and $FF);
  Buf[Offset + 1] := Byte(Value and $FF);
end;

procedure WriteU32BE(var Buf: TBytes; Offset: Integer; Value: Cardinal);
begin
  Buf[Offset] := Byte((Value shr 24) and $FF);
  Buf[Offset + 1] := Byte((Value shr 16) and $FF);
  Buf[Offset + 2] := Byte((Value shr 8) and $FF);
  Buf[Offset + 3] := Byte(Value and $FF);
end;

function ReadU16BE(const Buf: TBytes; Offset: Integer): Word;
begin
  Result := (Word(Buf[Offset]) shl 8) or Word(Buf[Offset + 1]);
end;

function ReadU32BE(const Buf: TBytes; Offset: Integer): Cardinal;
begin
  Result := (Cardinal(Buf[Offset]) shl 24) or
            (Cardinal(Buf[Offset + 1]) shl 16) or
            (Cardinal(Buf[Offset + 2]) shl 8) or
            Cardinal(Buf[Offset + 3]);
end;

function EncodeFrameHeader(const Header: TRstmdbFrameHeader): TBytes;
begin
  if Header.Version <> RSTMDB_PROTOCOL_VERSION then
    raise ERstmdbProtocolError.Create(ERR_UNSUPPORTED_PROTOCOL,
      Format('Unsupported protocol version: %d', [Header.Version]));
  if (Header.Flags and (not RSTMDB_FLAG_VALID_MASK)) <> 0 then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      Format('Invalid frame flags: $%x', [Header.Flags]));
  if Header.PayloadLen > RSTMDB_MAX_PAYLOAD_SIZE then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      Format('Frame payload too large: %u bytes (max %u)',
        [Header.PayloadLen, RSTMDB_MAX_PAYLOAD_SIZE]));

  Result := nil;
  SetLength(Result, RSTMDB_HEADER_SIZE);
  Result[0] := Ord('R');
  Result[1] := Ord('C');
  Result[2] := Ord('P');
  Result[3] := Ord('X');
  WriteU16BE(Result, 4, Header.Version);
  WriteU16BE(Result, 6, Header.Flags);
  WriteU16BE(Result, 8, Header.HeaderLen);
  WriteU32BE(Result, 10, Header.PayloadLen);
  WriteU32BE(Result, 14, Header.Crc32c);
end;

function DecodeFrameHeader(const Data: TBytes; Offset: Integer): TRstmdbFrameHeader;
begin
  if (Offset < 0) or (Length(Data) - Offset < RSTMDB_HEADER_SIZE) then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Incomplete frame header');

  if (Data[Offset] <> Ord('R')) or
     (Data[Offset + 1] <> Ord('C')) or
     (Data[Offset + 2] <> Ord('P')) or
     (Data[Offset + 3] <> Ord('X')) then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      'Invalid frame magic bytes: expected RCPX');

  Result.Version := ReadU16BE(Data, Offset + 4);
  if Result.Version <> RSTMDB_PROTOCOL_VERSION then
    raise ERstmdbProtocolError.Create(ERR_UNSUPPORTED_PROTOCOL,
      Format('Unsupported protocol version: %d', [Result.Version]));

  Result.Flags := ReadU16BE(Data, Offset + 6);
  if (Result.Flags and (not RSTMDB_FLAG_VALID_MASK)) <> 0 then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      Format('Invalid frame flags: $%.4x', [Result.Flags]));

  Result.HeaderLen := ReadU16BE(Data, Offset + 8);
  Result.PayloadLen := ReadU32BE(Data, Offset + 10);
  if Result.PayloadLen > RSTMDB_MAX_PAYLOAD_SIZE then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      Format('Frame payload too large: %u bytes (max %u)',
        [Result.PayloadLen, RSTMDB_MAX_PAYLOAD_SIZE]));

  Result.Crc32c := ReadU32BE(Data, Offset + 14);
end;

function EncodeFrame(const Payload: TBytes; Flags: Word;
  const HeaderExtension: TBytes): TBytes;
var
  Header: TRstmdbFrameHeader;
  HeaderBytes: TBytes;
  ExtLen, PayloadLen, TotalLen: Integer;
begin
  ExtLen := Length(HeaderExtension);
  if ExtLen > High(Word) then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      Format('Header extension too large: %d bytes', [ExtLen]));

  PayloadLen := Length(Payload);
  if Cardinal(PayloadLen) > RSTMDB_MAX_PAYLOAD_SIZE then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
      Format('Frame payload too large: %d bytes (max %u)',
        [PayloadLen, RSTMDB_MAX_PAYLOAD_SIZE]));

  Header.Version := RSTMDB_PROTOCOL_VERSION;
  Header.Flags := Flags;
  Header.HeaderLen := Word(ExtLen);
  Header.PayloadLen := Cardinal(PayloadLen);
  if (Flags and RSTMDB_FLAG_CRC_PRESENT) <> 0 then
    Header.Crc32c := RstmdbCrc32c(Payload)
  else
    Header.Crc32c := 0;

  HeaderBytes := EncodeFrameHeader(Header);
  TotalLen := RSTMDB_HEADER_SIZE + ExtLen + PayloadLen;
  Result := nil;
  SetLength(Result, TotalLen);
  Move(HeaderBytes[0], Result[0], RSTMDB_HEADER_SIZE);
  if ExtLen > 0 then
    Move(HeaderExtension[0], Result[RSTMDB_HEADER_SIZE], ExtLen);
  if PayloadLen > 0 then
    Move(Payload[0], Result[RSTMDB_HEADER_SIZE + ExtLen], PayloadLen);
end;

function TryDecodeFrame(var Buffer: TBytes; out Frame: TRstmdbFrame): Boolean;
var
  Header: TRstmdbFrameHeader;
  TotalLen, Remaining: Integer;
  ActualCrc: Cardinal;
begin
  Frame := Default(TRstmdbFrame);
  if Length(Buffer) < RSTMDB_HEADER_SIZE then
    Exit(False);

  Header := DecodeFrameHeader(Buffer, 0);
  TotalLen := RSTMDB_HEADER_SIZE + Integer(Header.HeaderLen) + Integer(Header.PayloadLen);
  if Length(Buffer) < TotalLen then
    Exit(False);

  Frame.Version := Header.Version;
  Frame.Flags := Header.Flags;

  if Header.HeaderLen > 0 then
  begin
    SetLength(Frame.HeaderExtension, Header.HeaderLen);
    Move(Buffer[RSTMDB_HEADER_SIZE], Frame.HeaderExtension[0], Header.HeaderLen);
  end;

  if Header.PayloadLen > 0 then
  begin
    SetLength(Frame.Payload, Header.PayloadLen);
    Move(Buffer[RSTMDB_HEADER_SIZE + Integer(Header.HeaderLen)],
      Frame.Payload[0], Header.PayloadLen);
  end;

  if (Header.Flags and RSTMDB_FLAG_CRC_PRESENT) <> 0 then
  begin
    ActualCrc := RstmdbCrc32c(Frame.Payload);
    if ActualCrc <> Header.Crc32c then
      raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
        Format('CRC32C mismatch: expected $%.8x, got $%.8x',
          [Header.Crc32c, ActualCrc]));
  end;

  Remaining := Length(Buffer) - TotalLen;
  if Remaining > 0 then
    Move(Buffer[TotalLen], Buffer[0], Remaining);
  SetLength(Buffer, Remaining);
  Result := True;
end;

initialization
  InitCrc32cTable;

end.
