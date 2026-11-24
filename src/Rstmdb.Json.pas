unit Rstmdb.Json;

{$I rstmdb.inc}

interface

uses
  SysUtils,
  Classes,
  {$IFDEF FPC}
  fpjson,
  jsonparser,
  base64,
  {$ELSE}
  System.JSON,
  System.NetEncoding,
  {$ENDIF}
  Rstmdb.Types,
  Rstmdb.Errors;

type
  {$IFDEF FPC}
  TRstmdbNativeJson = TJSONData;
  {$ELSE}
  TRstmdbNativeJson = TJSONValue;
  {$ENDIF}

  TRstmdbJsonDoc = class
  private
    FRoot: TRstmdbNativeJson;
  public
    constructor Create(ARoot: TRstmdbNativeJson);
    destructor Destroy; override;
    class function ParseBytes(const Data: TBytes): TRstmdbJsonDoc;
    class function ParseString(const JsonText: string): TRstmdbJsonDoc;
    property Root: TRstmdbNativeJson read FRoot;
  end;

  TRstmdbJsonBuilder = class
  private
    FParts: TStringBuilder;
    FFirst: Boolean;
    FIsArray: Boolean;
    procedure WriteKeyPrefix(const Key: string);
    procedure WriteArrayPrefix;
  public
    constructor CreateObject;
    constructor CreateArray;
    destructor Destroy; override;
    procedure AddString(const Key, Value: string);
    procedure AddInt64(const Key: string; Value: Int64);
    procedure AddUInt64(const Key: string; Value: UInt64);
    procedure AddDouble(const Key: string; Value: Double);
    procedure AddBool(const Key: string; Value: Boolean);
    procedure AddNull(const Key: string);
    procedure AddRaw(const Key, RawJson: string);
    procedure AddStringArray(const Key: string; const Values: TRstmdbStringArray);
    procedure AddArrayRawItem(const RawJson: string);
    procedure AddArrayStringItem(const Value: string);
    function ToJson: string;
    function ToUtf8Bytes: TBytes;
  end;

  TRstmdbWireMessage = record
    MsgType: string;
    Id: string;
    Status: string;
    ResultJson: string;
    ErrorCode: string;
    ErrorMessage: string;
    ErrorRetryable: Boolean;
    ErrorDetailsJson: string;
    StreamEvent: TRstmdbStreamEvent;
  end;

function StringToUtf8Bytes(const S: string): TBytes;
function Utf8BytesToString(const Data: TBytes): string;

function JsonEscapeString(const S: string): string;
function Base64EncodeBytes(const Data: TBytes): string;
function Base64DecodeBytes(const Encoded: string): TBytes;

function JsonIsNull(Node: TRstmdbNativeJson): Boolean;
function JsonIsObject(Node: TRstmdbNativeJson): Boolean;
function JsonIsArray(Node: TRstmdbNativeJson): Boolean;
function JsonFind(Node: TRstmdbNativeJson; const Key: string): TRstmdbNativeJson;
function JsonGetString(Node: TRstmdbNativeJson; const Key: string;
  const DefaultVal: string = ''): string;
function JsonTryGetString(Node: TRstmdbNativeJson; const Key: string;
  out Value: string): Boolean;
function JsonGetInt64(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: Int64 = 0): Int64;
function JsonTryGetInt64(Node: TRstmdbNativeJson; const Key: string;
  out Value: Int64): Boolean;
function JsonGetUInt64(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: UInt64 = 0): UInt64;
function JsonGetDouble(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: Double = 0.0): Double;
function JsonGetBool(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: Boolean = False): Boolean;
function JsonGetRaw(Node: TRstmdbNativeJson; const Key: string;
  const DefaultVal: string = ''): string;
function JsonNodeToString(Node: TRstmdbNativeJson): string;
function JsonGetStringArray(Node: TRstmdbNativeJson; const Key: string): TRstmdbStringArray;
function JsonArrayCount(Node: TRstmdbNativeJson): Integer;
function JsonArrayItem(Node: TRstmdbNativeJson; Index: Integer): TRstmdbNativeJson;

function BuildRequestJson(const Id, Op: string; const ParamsJson: string = '{}'): TBytes;
function ParseWireMessage(const Payload: TBytes): TRstmdbWireMessage;

implementation

function InvariantFormatSettings: TFormatSettings;
begin
  {$IFDEF FPC}
  Result := DefaultFormatSettings;
  {$ELSE}
  Result := TFormatSettings.Invariant;
  {$ENDIF}
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function StringToUtf8Bytes(const S: string): TBytes;
{$IFDEF FPC}
var
  U: UTF8String;
begin
  if S = '' then
  begin
    Result := nil;
    Exit;
  end;
  U := UTF8String(S);
  SetLength(Result, Length(U));
  if Length(U) > 0 then
    Move(U[1], Result[0], Length(U));
end;
{$ELSE}
begin
  if S = '' then
    SetLength(Result, 0)
  else
    Result := TEncoding.UTF8.GetBytes(S);
end;
{$ENDIF}

function Utf8BytesToString(const Data: TBytes): string;
{$IFDEF FPC}
var
  U: UTF8String;
begin
  if Length(Data) = 0 then
    Exit('');
  SetLength(U, Length(Data));
  Move(Data[0], U[1], Length(Data));
  Result := string(U);
end;
{$ELSE}
begin
  if Length(Data) = 0 then
    Exit('');
  Result := TEncoding.UTF8.GetString(Data);
end;
{$ENDIF}

function JsonEscapeString(const S: string): string;
var
  SB: TStringBuilder;
  I: Integer;
  Ch: Char;
  Code: Word;
begin
  SB := TStringBuilder.Create(Length(S) + 8);
  try
    SB.Append('"');
    for I := 1 to Length(S) do
    begin
      Ch := S[I];
      case Ch of
        '"':  SB.Append('\"');
        '\':  SB.Append('\\');
        #8:   SB.Append('\b');
        #9:   SB.Append('\t');
        #10:  SB.Append('\n');
        #12:  SB.Append('\f');
        #13:  SB.Append('\r');
      else
        Code := Ord(Ch);
        if Code < $20 then
          SB.Append('\u' + IntToHex(Code, 4))
        else
          SB.Append(Ch);
      end;
    end;
    SB.Append('"');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function Base64EncodeBytes(const Data: TBytes): string;
{$IFDEF FPC}
var
  Raw: RawByteString;
begin
  if Length(Data) = 0 then
    Exit('');
  SetLength(Raw, Length(Data));
  Move(Data[0], Raw[1], Length(Data));
  Result := string(EncodeStringBase64(Raw));
end;
{$ELSE}
begin
  if Length(Data) = 0 then
    Exit('');
  Result := TNetEncoding.Base64String.EncodeBytesToString(Data);
end;
{$ENDIF}

function Base64DecodeBytes(const Encoded: string): TBytes;
{$IFDEF FPC}
var
  Decoded: RawByteString;
begin
  if Encoded = '' then
  begin
    Result := nil;
    Exit;
  end;
  Decoded := DecodeStringBase64(AnsiString(Encoded));
  SetLength(Result, Length(Decoded));
  if Length(Decoded) > 0 then
    Move(Decoded[1], Result[0], Length(Decoded));
end;
{$ELSE}
begin
  if Encoded = '' then
    SetLength(Result, 0)
  else
    Result := TNetEncoding.Base64String.DecodeStringToBytes(Encoded);
end;
{$ENDIF}

function FormatFloatJson(Value: Double): string;
var
  FS: TFormatSettings;
begin
  FS := InvariantFormatSettings;
  Result := FloatToStr(Value, FS);
  if (Pos('.', Result) = 0) and (Pos('e', Result) = 0) and (Pos('E', Result) = 0) then
    Result := Result + '.0';
end;

{ TRstmdbJsonDoc }

constructor TRstmdbJsonDoc.Create(ARoot: TRstmdbNativeJson);
begin
  inherited Create;
  FRoot := ARoot;
end;

destructor TRstmdbJsonDoc.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

class function TRstmdbJsonDoc.ParseBytes(const Data: TBytes): TRstmdbJsonDoc;
{$IFDEF FPC}
begin
  Result := ParseString(Utf8BytesToString(Data));
end;
{$ELSE}
var
  RootVal: TJSONValue;
begin
  if Length(Data) = 0 then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Empty JSON payload');
  RootVal := TJSONObject.ParseJSONValue(Data, 0, True);
  if RootVal = nil then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Invalid JSON payload');
  Result := TRstmdbJsonDoc.Create(RootVal);
end;
{$ENDIF}

class function TRstmdbJsonDoc.ParseString(const JsonText: string): TRstmdbJsonDoc;
var
  RootVal: TRstmdbNativeJson;
begin
  if Trim(JsonText) = '' then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Empty JSON payload');
  {$IFDEF FPC}
  try
    RootVal := GetJSON(JsonText, True);
  except
    on E: Exception do
      raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR,
        'Invalid JSON payload: ' + E.Message);
  end;
  if RootVal = nil then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Invalid JSON payload');
  {$ELSE}
  RootVal := TJSONObject.ParseJSONValue(JsonText);
  if RootVal = nil then
    raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Invalid JSON payload');
  {$ENDIF}
  Result := TRstmdbJsonDoc.Create(RootVal);
end;

{ TRstmdbJsonBuilder }

constructor TRstmdbJsonBuilder.CreateObject;
begin
  inherited Create;
  FIsArray := False;
  FFirst := True;
  FParts := TStringBuilder.Create;
  FParts.Append('{');
end;

constructor TRstmdbJsonBuilder.CreateArray;
begin
  inherited Create;
  FIsArray := True;
  FFirst := True;
  FParts := TStringBuilder.Create;
  FParts.Append('[');
end;

destructor TRstmdbJsonBuilder.Destroy;
begin
  FParts.Free;
  inherited Destroy;
end;

procedure TRstmdbJsonBuilder.WriteKeyPrefix(const Key: string);
begin
  if not FFirst then
    FParts.Append(',');
  FFirst := False;
  FParts.Append(JsonEscapeString(Key));
  FParts.Append(':');
end;

procedure TRstmdbJsonBuilder.WriteArrayPrefix;
begin
  if not FFirst then
    FParts.Append(',');
  FFirst := False;
end;

procedure TRstmdbJsonBuilder.AddString(const Key, Value: string);
begin
  WriteKeyPrefix(Key);
  FParts.Append(JsonEscapeString(Value));
end;

procedure TRstmdbJsonBuilder.AddInt64(const Key: string; Value: Int64);
begin
  WriteKeyPrefix(Key);
  FParts.Append(IntToStr(Value));
end;

procedure TRstmdbJsonBuilder.AddUInt64(const Key: string; Value: UInt64);
begin
  WriteKeyPrefix(Key);
  FParts.Append(UIntToStr(Value));
end;

procedure TRstmdbJsonBuilder.AddDouble(const Key: string; Value: Double);
begin
  WriteKeyPrefix(Key);
  FParts.Append(FormatFloatJson(Value));
end;

procedure TRstmdbJsonBuilder.AddBool(const Key: string; Value: Boolean);
begin
  WriteKeyPrefix(Key);
  if Value then
    FParts.Append('true')
  else
    FParts.Append('false');
end;

procedure TRstmdbJsonBuilder.AddNull(const Key: string);
begin
  WriteKeyPrefix(Key);
  FParts.Append('null');
end;

procedure TRstmdbJsonBuilder.AddRaw(const Key, RawJson: string);
begin
  WriteKeyPrefix(Key);
  if Trim(RawJson) = '' then
    FParts.Append('null')
  else
    FParts.Append(RawJson);
end;

procedure TRstmdbJsonBuilder.AddStringArray(const Key: string; const Values: TRstmdbStringArray);
var
  I: Integer;
begin
  WriteKeyPrefix(Key);
  FParts.Append('[');
  for I := 0 to Length(Values) - 1 do
  begin
    if I > 0 then
      FParts.Append(',');
    FParts.Append(JsonEscapeString(Values[I]));
  end;
  FParts.Append(']');
end;

procedure TRstmdbJsonBuilder.AddArrayRawItem(const RawJson: string);
begin
  WriteArrayPrefix;
  if Trim(RawJson) = '' then
    FParts.Append('null')
  else
    FParts.Append(RawJson);
end;

procedure TRstmdbJsonBuilder.AddArrayStringItem(const Value: string);
begin
  WriteArrayPrefix;
  FParts.Append(JsonEscapeString(Value));
end;

function TRstmdbJsonBuilder.ToJson: string;
begin
  if FIsArray then
    Result := FParts.ToString + ']'
  else
    Result := FParts.ToString + '}';
end;

function TRstmdbJsonBuilder.ToUtf8Bytes: TBytes;
begin
  Result := StringToUtf8Bytes(ToJson);
end;

{ Native JSON accessors }

function JsonIsNull(Node: TRstmdbNativeJson): Boolean;
begin
  if Node = nil then
    Exit(True);
  {$IFDEF FPC}
  Result := Node.JSONType = jtNull;
  {$ELSE}
  Result := Node is TJSONNull;
  {$ENDIF}
end;

function JsonIsObject(Node: TRstmdbNativeJson): Boolean;
begin
  if Node = nil then
    Exit(False);
  {$IFDEF FPC}
  Result := Node.JSONType = jtObject;
  {$ELSE}
  Result := Node is TJSONObject;
  {$ENDIF}
end;

function JsonIsArray(Node: TRstmdbNativeJson): Boolean;
begin
  if Node = nil then
    Exit(False);
  {$IFDEF FPC}
  Result := Node.JSONType = jtArray;
  {$ELSE}
  Result := Node is TJSONArray;
  {$ENDIF}
end;

function JsonFind(Node: TRstmdbNativeJson; const Key: string): TRstmdbNativeJson;
begin
  Result := nil;
  if not JsonIsObject(Node) then
    Exit;
  {$IFDEF FPC}
  Result := TJSONObject(Node).Find(Key);
  {$ELSE}
  Result := TJSONObject(Node).Values[Key];
  {$ENDIF}
end;

function JsonTryGetString(Node: TRstmdbNativeJson; const Key: string;
  out Value: string): Boolean;
var
  Child: TRstmdbNativeJson;
begin
  Value := '';
  Child := JsonFind(Node, Key);
  if (Child = nil) or JsonIsNull(Child) then
    Exit(False);
  {$IFDEF FPC}
  if Child.JSONType = jtString then
  begin
    Value := Child.AsString;
    Exit(True);
  end;
  {$ELSE}
  if Child is TJSONString then
  begin
    Value := TJSONString(Child).Value;
    Exit(True);
  end;
  {$ENDIF}
  Result := False;
end;

function JsonGetString(Node: TRstmdbNativeJson; const Key: string;
  const DefaultVal: string): string;
begin
  if not JsonTryGetString(Node, Key, Result) then
    Result := DefaultVal;
end;

function JsonTryGetInt64(Node: TRstmdbNativeJson; const Key: string;
  out Value: Int64): Boolean;
var
  Child: TRstmdbNativeJson;
begin
  Value := 0;
  Child := JsonFind(Node, Key);
  if (Child = nil) or JsonIsNull(Child) then
    Exit(False);
  {$IFDEF FPC}
  if Child.JSONType = jtNumber then
  begin
    Value := Child.AsInt64;
    Exit(True);
  end;
  {$ELSE}
  if Child is TJSONNumber then
  begin
    Value := TJSONNumber(Child).AsInt64;
    Exit(True);
  end;
  {$ENDIF}
  Result := False;
end;

function JsonGetInt64(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: Int64): Int64;
begin
  if not JsonTryGetInt64(Node, Key, Result) then
    Result := DefaultVal;
end;

function JsonGetUInt64(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: UInt64): UInt64;
var
  Child: TRstmdbNativeJson;
begin
  Result := DefaultVal;
  Child := JsonFind(Node, Key);
  if (Child = nil) or JsonIsNull(Child) then
    Exit;
  {$IFDEF FPC}
  if Child.JSONType = jtNumber then
    Result := Child.AsQWord;
  {$ELSE}
  if Child is TJSONNumber then
    Result := StrToUInt64Def(TJSONNumber(Child).ToString, DefaultVal);
  {$ENDIF}
end;

function JsonGetDouble(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: Double): Double;
var
  Child: TRstmdbNativeJson;
begin
  Result := DefaultVal;
  Child := JsonFind(Node, Key);
  if (Child = nil) or JsonIsNull(Child) then
    Exit;
  {$IFDEF FPC}
  if Child.JSONType = jtNumber then
    Result := Child.AsFloat;
  {$ELSE}
  if Child is TJSONNumber then
    Result := TJSONNumber(Child).AsDouble;
  {$ENDIF}
end;

function JsonGetBool(Node: TRstmdbNativeJson; const Key: string;
  DefaultVal: Boolean): Boolean;
var
  Child: TRstmdbNativeJson;
begin
  Result := DefaultVal;
  Child := JsonFind(Node, Key);
  if (Child = nil) or JsonIsNull(Child) then
    Exit;
  {$IFDEF FPC}
  if Child.JSONType = jtBoolean then
    Result := Child.AsBoolean;
  {$ELSE}
  if Child is TJSONBool then
    Result := TJSONBool(Child).AsBoolean;
  {$ENDIF}
end;

function JsonNodeToString(Node: TRstmdbNativeJson): string;
begin
  if Node = nil then
    Exit('');
  {$IFDEF FPC}
  Result := Node.AsJSON;
  {$ELSE}
  Result := Node.ToJSON;
  {$ENDIF}
end;

function JsonGetRaw(Node: TRstmdbNativeJson; const Key: string;
  const DefaultVal: string): string;
var
  Child: TRstmdbNativeJson;
begin
  Child := JsonFind(Node, Key);
  if Child = nil then
    Result := DefaultVal
  else
    Result := JsonNodeToString(Child);
end;

function JsonGetStringArray(Node: TRstmdbNativeJson; const Key: string): TRstmdbStringArray;
var
  Arr: TRstmdbNativeJson;
  I, Cnt: Integer;
  Item: TRstmdbNativeJson;
begin
  Result := nil;
  Arr := JsonFind(Node, Key);
  if not JsonIsArray(Arr) then
    Exit;
  Cnt := JsonArrayCount(Arr);
  SetLength(Result, Cnt);
  for I := 0 to Cnt - 1 do
  begin
    Item := JsonArrayItem(Arr, I);
    {$IFDEF FPC}
    if (Item <> nil) and (Item.JSONType = jtString) then
      Result[I] := Item.AsString
    else
      Result[I] := '';
    {$ELSE}
    if Item is TJSONString then
      Result[I] := TJSONString(Item).Value
    else
      Result[I] := '';
    {$ENDIF}
  end;
end;

function JsonArrayCount(Node: TRstmdbNativeJson): Integer;
begin
  if not JsonIsArray(Node) then
    Exit(0);
  {$IFDEF FPC}
  Result := TJSONArray(Node).Count;
  {$ELSE}
  Result := TJSONArray(Node).Count;
  {$ENDIF}
end;

function JsonArrayItem(Node: TRstmdbNativeJson; Index: Integer): TRstmdbNativeJson;
begin
  if not JsonIsArray(Node) then
    Exit(nil);
  {$IFDEF FPC}
  Result := TJSONArray(Node).Items[Index];
  {$ELSE}
  Result := TJSONArray(Node).Items[Index];
  {$ENDIF}
end;

function BuildRequestJson(const Id, Op: string; const ParamsJson: string): TBytes;
var
  B: TRstmdbJsonBuilder;
  ActualParams: string;
begin
  ActualParams := Trim(ParamsJson);
  if ActualParams = '' then
    ActualParams := '{}';
  B := TRstmdbJsonBuilder.CreateObject;
  try
    B.AddString('type', 'request');
    B.AddString('id', Id);
    B.AddString('op', Op);
    B.AddRaw('params', ActualParams);
    Result := B.ToUtf8Bytes;
  finally
    B.Free;
  end;
end;

function ParseWireMessage(const Payload: TBytes): TRstmdbWireMessage;
var
  Doc: TRstmdbJsonDoc;
  Root, ErrNode, DetailsNode: TRstmdbNativeJson;
  VersionVal: Int64;
begin
  Result := Default(TRstmdbWireMessage);
  Doc := TRstmdbJsonDoc.ParseBytes(Payload);
  try
    Root := Doc.Root;
    if not JsonIsObject(Root) then
      raise ERstmdbProtocolError.Create(ERR_PROTOCOL_ERROR, 'Wire message must be a JSON object');

    Result.MsgType := JsonGetString(Root, 'type', '');
    if Result.MsgType = 'event' then
    begin
      Result.StreamEvent.SubscriptionId := JsonGetString(Root, 'subscription_id', '');
      Result.StreamEvent.InstanceId := JsonGetString(Root, 'instance_id', '');
      Result.StreamEvent.Machine := JsonGetString(Root, 'machine', '');
      VersionVal := JsonGetInt64(Root, 'version', 0);
      if VersionVal >= 0 then
        Result.StreamEvent.Version := Cardinal(VersionVal);
      Result.StreamEvent.EventName := JsonGetString(Root, 'event', '');
      Result.StreamEvent.FromState := JsonGetString(Root, 'from_state', '');
      Result.StreamEvent.ToState := JsonGetString(Root, 'to_state', '');
      Result.StreamEvent.PayloadJson := JsonGetRaw(Root, 'payload', '');
      Result.StreamEvent.CtxJson := JsonGetRaw(Root, 'ctx', '');
      Result.StreamEvent.WalOffset := JsonGetInt64(Root, 'wal_offset', 0);
      Exit;
    end;

    Result.Id := JsonGetString(Root, 'id', '');
    Result.Status := JsonGetString(Root, 'status', '');
    if Result.Status = 'ok' then
    begin
      Result.ResultJson := JsonGetRaw(Root, 'result', '{}');
    end
    else if Result.Status = 'error' then
    begin
      ErrNode := JsonFind(Root, 'error');
      if JsonIsObject(ErrNode) then
      begin
        Result.ErrorCode := JsonGetString(ErrNode, 'code', ERR_INTERNAL_ERROR);
        Result.ErrorMessage := JsonGetString(ErrNode, 'message', 'Unknown server error');
        Result.ErrorRetryable := JsonGetBool(ErrNode, 'retryable', False);
        DetailsNode := JsonFind(ErrNode, 'details');
        if DetailsNode <> nil then
          Result.ErrorDetailsJson := JsonNodeToString(DetailsNode);
      end
      else
      begin
        Result.ErrorCode := ERR_INTERNAL_ERROR;
        Result.ErrorMessage := 'Malformed error envelope';
      end;
    end;
  finally
    Doc.Free;
  end;
end;

end.
