unit TestJson;

{$I rstmdb.inc}

interface

procedure RegisterJsonTests;

implementation

uses
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Json,
  Rstmdb.TestRunner;

procedure TestUtf8MultibyteRoundTrip;
var
  Original, Decoded: string;
  Bytes: TBytes;
  B: TRstmdbJsonBuilder;
  Doc: TRstmdbJsonDoc;
begin
  Original := 'Привет 世界 🚀 Café';
  Bytes := StringToUtf8Bytes(Original);
  Decoded := Utf8BytesToString(Bytes);
  CheckEquals(Original, Decoded, 'UTF-8 bytes round-trip');

  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('text', Original);
    Bytes := B.ToUtf8Bytes;
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseBytes(Bytes);
  try
    CheckEquals(Original, JsonGetString(Doc.Root, 'text'), 'UTF-8 JSON round-trip');
  finally
    Doc.Free;
  end;
end;

procedure TestInt64WalOffsetPrecision;
const
  BIG_OFFSET: Int64 = 9000000000123;
var
  B: TRstmdbJsonBuilder;
  Bytes: TBytes;
  Doc: TRstmdbJsonDoc;
begin
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddInt64('wal_offset', BIG_OFFSET);
    Bytes := B.ToUtf8Bytes;
  finally
    B.Free;
  end;

  Doc := TRstmdbJsonDoc.ParseBytes(Bytes);
  try
    CheckEquals(BIG_OFFSET, JsonGetInt64(Doc.Root, 'wal_offset'), 'Int64 > 2^32');
  finally
    Doc.Free;
  end;
end;

procedure TestIntegerVsFloatPreservation;
var
  B: TRstmdbJsonBuilder;
  JsonStr: string;
begin
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddInt64('int_val', 10);
    B.AddDouble('flt_val', 10.0);
    B.AddRaw('raw_ctx', '{"a":10,"b":10.0}');
    JsonStr := B.ToJson;
  finally
    B.Free;
  end;

  Check(Pos('"int_val":10,', JsonStr) > 0, 'Integer 10 must serialize without .0: ' + JsonStr);
  Check(Pos('"flt_val":10.0,', JsonStr) > 0, 'Float 10.0 must preserve .0: ' + JsonStr);
  Check(Pos('"raw_ctx":{"a":10,"b":10.0}', JsonStr) > 0, 'Raw JSON must preserve 10 vs 10.0');
end;

procedure TestUnknownErrorCodeEnvelopeParsing;
var
  Payload: TBytes;
  Msg: TRstmdbWireMessage;
begin
  Payload := StringToUtf8Bytes(
    '{"type":"response","id":"42","status":"error","error":{' +
    '"code":"FUTURE_ERROR_CODE","message":"New constraint","retryable":true,' +
    '"details":{"field":"amount"}}}'
  );
  Msg := ParseWireMessage(Payload);
  CheckEquals('response', Msg.MsgType, 'MsgType');
  CheckEquals('42', Msg.Id, 'Id');
  CheckEquals('error', Msg.Status, 'Status');
  CheckEquals('FUTURE_ERROR_CODE', Msg.ErrorCode, 'Unknown ErrorCode preserved');
  CheckEquals('New constraint', Msg.ErrorMessage, 'ErrorMessage');
  CheckEquals(True, Msg.ErrorRetryable, 'Retryable');
  Check(Pos('"amount"', Msg.ErrorDetailsJson) > 0, 'DetailsJson preserved');
end;

procedure TestStreamEventParsing;
var
  Payload: TBytes;
  Msg: TRstmdbWireMessage;
begin
  Payload := StringToUtf8Bytes(
    '{"type":"event","subscription_id":"sub-1","instance_id":"ord-1",' +
    '"machine":"order","version":2,"event":"PAY","from_state":"pending",' +
    '"to_state":"paid","payload":{"amount":10.0},"ctx":{"ok":true},"wal_offset":5000000000}'
  );
  Msg := ParseWireMessage(Payload);
  CheckEquals('event', Msg.MsgType, 'Event MsgType');
  CheckEquals('sub-1', Msg.StreamEvent.SubscriptionId, 'SubscriptionId');
  CheckEquals('ord-1', Msg.StreamEvent.InstanceId, 'InstanceId');
  CheckEquals('order', Msg.StreamEvent.Machine, 'Machine');
  CheckEquals(Cardinal(2), Msg.StreamEvent.Version, 'Version');
  CheckEquals('PAY', Msg.StreamEvent.EventName, 'EventName');
  CheckEquals('pending', Msg.StreamEvent.FromState, 'FromState');
  CheckEquals('paid', Msg.StreamEvent.ToState, 'ToState');
  CheckEquals(Int64(5000000000), Msg.StreamEvent.WalOffset, 'WalOffset > 2^32');
end;

procedure TestBase64RoundTrip;
var
  Raw, Decoded: TBytes;
  Enc: string;
  I: Integer;
begin
  SetLength(Raw, 256);
  for I := 0 to 255 do
    Raw[I] := Byte(I);
  Enc := Base64EncodeBytes(Raw);
  Decoded := Base64DecodeBytes(Enc);
  CheckEquals(Int64(256), Int64(Length(Decoded)), 'Decoded base64 len');
  Check(CompareMem(@Raw[0], @Decoded[0], 256), 'Decoded base64 bytes match');
end;

procedure RegisterJsonTests;
begin
  RegisterTest('Json.Utf8MultibyteRoundTrip', TestUtf8MultibyteRoundTrip);
  RegisterTest('Json.Int64WalOffsetPrecision', TestInt64WalOffsetPrecision);
  RegisterTest('Json.IntegerVsFloatPreservation', TestIntegerVsFloatPreservation);
  RegisterTest('Json.UnknownErrorCodeEnvelope', TestUnknownErrorCodeEnvelopeParsing);
  RegisterTest('Json.StreamEventParsing', TestStreamEventParsing);
  RegisterTest('Json.Base64RoundTrip', TestBase64RoundTrip);
end;

end.
