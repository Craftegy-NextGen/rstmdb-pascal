unit Rstmdb.Transport;

{$I rstmdb.inc}

interface

uses
  SysUtils,
  Classes,
  {$IFDEF RSTMDB_TRANSPORT_RTL}
    {$IFDEF FPC}
    {$IFDEF UNIX}
    baseunix,
    {$ENDIF}
    sockets,
    ssockets,
    sslbase,
    sslsockets,
    opensslsockets,
    {$ELSE}
    System.Net.Socket,
    {$ENDIF}
  {$ENDIF}
  {$IFDEF RSTMDB_TRANSPORT_SYNAPSE}
  blcksock,
  ssl_openssl3,
  {$ENDIF}
  Rstmdb.Types,
  Rstmdb.Errors;

type
  TRstmdbTransport = class
  public
    procedure Connect(const Host: string; Port: Word; TimeoutMs: Integer;
      const Tls: TRstmdbTlsOptions); virtual; abstract;
    procedure Close; virtual; abstract;
    function IsConnected: Boolean; virtual; abstract;
    procedure WriteAll(const Data: TBytes); virtual; abstract;
    function ReadExact(Count: Integer; TimeoutMs: Integer): TBytes; virtual; abstract;
  end;

  {$IFDEF RSTMDB_TRANSPORT_RTL}
  TRstmdbRtlTransport = class(TRstmdbTransport)
  private
    {$IFDEF FPC}
    FSocket: TInetSocket;
    {$ELSE}
    FSocket: TSocket;
    {$ENDIF}
    FConnected: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const Host: string; Port: Word; TimeoutMs: Integer;
      const Tls: TRstmdbTlsOptions); override;
    procedure Close; override;
    function IsConnected: Boolean; override;
    procedure WriteAll(const Data: TBytes); override;
    function ReadExact(Count: Integer; TimeoutMs: Integer): TBytes; override;
  end;
  {$ENDIF}

  {$IFDEF RSTMDB_TRANSPORT_SYNAPSE}
  TRstmdbSynapseTransport = class(TRstmdbTransport)
  private
    FSock: TTCPBlockSocket;
    FConnected: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const Host: string; Port: Word; TimeoutMs: Integer;
      const Tls: TRstmdbTlsOptions); override;
    procedure Close; override;
    function IsConnected: Boolean; override;
    procedure WriteAll(const Data: TBytes); override;
    function ReadExact(Count: Integer; TimeoutMs: Integer): TBytes; override;
  end;
  {$ENDIF}

function CreateDefaultTransport: TRstmdbTransport;

implementation

{$IFDEF RSTMDB_TRANSPORT_RTL}
{$IFDEF FPC}
function IsTimeoutSocketError(Err: Integer): Boolean;
begin
  {$IFDEF UNIX}
  Result := (Err = ESysEAGAIN) or (Err = ESysEWOULDBLOCK) or (Err = ESysETIMEDOUT);
  {$ELSE}
  Result := (Err = 10060) or (Err = 10035);
  {$ENDIF}
end;
{$ENDIF}

{ TRstmdbRtlTransport }

constructor TRstmdbRtlTransport.Create;
begin
  inherited Create;
  FSocket := nil;
  FConnected := False;
end;

destructor TRstmdbRtlTransport.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TRstmdbRtlTransport.Connect(const Host: string; Port: Word;
  TimeoutMs: Integer; const Tls: TRstmdbTlsOptions);
{$IFDEF FPC}
var
  SSLHandler: TSSLSocketHandler;
begin
  Close;
  try
    if Tls.Enabled then
    begin
      SSLHandler := TOpenSSLSocketHandler.Create;
      SSLHandler.SSLType := stAny;
      SSLHandler.VerifyPeerCert := not Tls.InsecureSkipVerify;
      if Tls.ServerName <> '' then
        SSLHandler.CertificateData.HostName := Tls.ServerName
      else
        SSLHandler.CertificateData.HostName := Host;
      if Tls.CaCertFile <> '' then
      begin
        SSLHandler.CertificateData.CertCA.FileName := Tls.CaCertFile;
        SSLHandler.CertificateData.TrustedCertsDir := ExtractFilePath(Tls.CaCertFile);
      end;
      if Tls.ClientCertFile <> '' then
        SSLHandler.CertificateData.Certificate.FileName := Tls.ClientCertFile;
      if Tls.ClientKeyFile <> '' then
        SSLHandler.CertificateData.PrivateKey.FileName := Tls.ClientKeyFile;
      if Tls.ClientKeyPassword <> '' then
        SSLHandler.CertificateData.KeyPassword := Tls.ClientKeyPassword;
      FSocket := TInetSocket.Create(Host, Port, SSLHandler);
    end
    else
    begin
      FSocket := TInetSocket.Create(Host, Port);
    end;
    if TimeoutMs > 0 then
      FSocket.IOTimeout := TimeoutMs;
    FConnected := True;
  except
    on E: Exception do
    begin
      FreeAndNil(FSocket);
      FConnected := False;
      raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED,
        Format('Failed to connect to %s:%d: %s', [Host, Port, E.Message]), True);
    end;
  end;
end;
{$ELSE}
begin
  Close;
  if Tls.Enabled then
    raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED,
      'TLS/mTLS under Delphi requires -DRSTMDB_TRANSPORT_SYNAPSE (Ararat Synapse + OpenSSL 3.x).',
      False);
  FSocket := TSocket.Create(TSocketType.TCP, TProtocolType.TCP);
  try
    if TimeoutMs > 0 then
    begin
      FSocket.ReceiveTimeout := TimeoutMs;
      FSocket.SendTimeout := TimeoutMs;
    end;
    FSocket.Connect('', Host, '', Port);
    FConnected := True;
  except
    on E: Exception do
    begin
      FreeAndNil(FSocket);
      FConnected := False;
      raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED,
        Format('Failed to connect to %s:%d: %s', [Host, Port, E.Message]), True);
    end;
  end;
end;
{$ENDIF}

procedure TRstmdbRtlTransport.Close;
begin
  FConnected := False;
  FreeAndNil(FSocket);
end;

function TRstmdbRtlTransport.IsConnected: Boolean;
begin
  Result := FConnected and (FSocket <> nil);
end;

procedure TRstmdbRtlTransport.WriteAll(const Data: TBytes);
var
  Offset, Total, Written: Integer;
begin
  if not IsConnected then
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Not connected', True);
  Total := Length(Data);
  Offset := 0;
  while Offset < Total do
  begin
    {$IFDEF FPC}
    Written := FSocket.Write(Data[Offset], Total - Offset);
    if Written <= 0 then
    begin
      FConnected := False;
      raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED,
        Format('Socket write failed (err=%d)', [FSocket.LastError]), True);
    end;
    {$ELSE}
    Written := FSocket.Send(Data, Offset, Total - Offset);
    if Written <= 0 then
    begin
      FConnected := False;
      raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED,
        'Socket write failed', True);
    end;
    {$ENDIF}
    Inc(Offset, Written);
  end;
end;

function TRstmdbRtlTransport.ReadExact(Count: Integer; TimeoutMs: Integer): TBytes;
var
  Offset, Got: Integer;
  {$IFDEF FPC}
  LastErr: Integer;
  {$ENDIF}
begin
  if Count <= 0 then
  begin
    Result := nil;
    Exit;
  end;
  if not IsConnected then
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Not connected', True);

  Result := nil;
  SetLength(Result, Count);
  Offset := 0;

  {$IFDEF FPC}
  if TimeoutMs > 0 then
    FSocket.IOTimeout := TimeoutMs;
  while Offset < Count do
  begin
    Got := FSocket.Read(Result[Offset], Count - Offset);
    if Got > 0 then
    begin
      Inc(Offset, Got);
      Continue;
    end;
    LastErr := FSocket.LastError;
    if (Got < 0) and IsTimeoutSocketError(LastErr) then
    begin
      if Offset = 0 then
        raise ERstmdbTimeoutError.Create(ERR_TIMEOUT, 'Socket read timed out', True);
      { Partial frame received; keep waiting or fail if connection dropped }
      raise ERstmdbTimeoutError.Create(ERR_TIMEOUT, 'Socket read timed out mid-frame', True);
    end;
    FConnected := False;
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED,
      'Connection closed by peer', True);
  end;
  {$ELSE}
  if TimeoutMs > 0 then
    FSocket.ReceiveTimeout := TimeoutMs;
  while Offset < Count do
  begin
    Got := FSocket.Receive(Result, Offset, Count - Offset, []);
    if Got > 0 then
    begin
      Inc(Offset, Got);
      Continue;
    end;
    if Got = 0 then
    begin
      FConnected := False;
      raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED,
        'Connection closed by peer', True);
    end;
    raise ERstmdbTimeoutError.Create(ERR_TIMEOUT, 'Socket read timed out', True);
  end;
  {$ENDIF}
end;
{$ENDIF}

{$IFDEF RSTMDB_TRANSPORT_SYNAPSE}
{ TRstmdbSynapseTransport }

constructor TRstmdbSynapseTransport.Create;
begin
  inherited Create;
  FSock := nil;
  FConnected := False;
end;

destructor TRstmdbSynapseTransport.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TRstmdbSynapseTransport.Connect(const Host: string; Port: Word;
  TimeoutMs: Integer; const Tls: TRstmdbTlsOptions);
begin
  Close;
  FSock := TTCPBlockSocket.Create;
  try
    if TimeoutMs > 0 then
      FSock.ConnectionTimeout := TimeoutMs;
    FSock.Connect(Host, IntToStr(Port));
    if FSock.LastError <> 0 then
      raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED,
        Format('Failed to connect to %s:%d: %s', [Host, Port, FSock.LastErrorDesc]), True);
    if Tls.Enabled then
    begin
      if Tls.CaCertFile <> '' then
        FSock.SSL.CertCAFile := Tls.CaCertFile;
      if Tls.ClientCertFile <> '' then
        FSock.SSL.CertificateFile := Tls.ClientCertFile;
      if Tls.ClientKeyFile <> '' then
        FSock.SSL.PrivateKeyFile := Tls.ClientKeyFile;
      if Tls.ClientKeyPassword <> '' then
        FSock.SSL.KeyPassword := Tls.ClientKeyPassword;
      FSock.SSL.VerifyCert := not Tls.InsecureSkipVerify;
      if Tls.ServerName <> '' then
        FSock.SSL.SNIHost := Tls.ServerName
      else
        FSock.SSL.SNIHost := Host;
      FSock.SSLDoConnect;
      if FSock.LastError <> 0 then
        raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED,
          Format('TLS handshake failed: %s', [FSock.SSL.LastErrorDesc]), False);
    end;
    FConnected := True;
  except
    on E: ERstmdbError do
    begin
      FreeAndNil(FSock);
      FConnected := False;
      raise;
    end;
    on E: Exception do
    begin
      FreeAndNil(FSock);
      FConnected := False;
      raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED, E.Message, True);
    end;
  end;
end;

procedure TRstmdbSynapseTransport.Close;
begin
  FConnected := False;
  if FSock <> nil then
  begin
    try
      FSock.CloseSocket;
    except
      { ignore close errors }
    end;
    FreeAndNil(FSock);
  end;
end;

function TRstmdbSynapseTransport.IsConnected: Boolean;
begin
  Result := FConnected and (FSock <> nil);
end;

procedure TRstmdbSynapseTransport.WriteAll(const Data: TBytes);
begin
  if not IsConnected then
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Not connected', True);
  if Length(Data) = 0 then
    Exit;
  FSock.SendBuffer(@Data[0], Length(Data));
  if FSock.LastError <> 0 then
  begin
    FConnected := False;
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED,
      FSock.LastErrorDesc, True);
  end;
end;

function TRstmdbSynapseTransport.ReadExact(Count: Integer; TimeoutMs: Integer): TBytes;
var
  Offset, Got, EffTimeout: Integer;
begin
  if Count <= 0 then
  begin
    SetLength(Result, 0);
    Exit;
  end;
  if not IsConnected then
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED, 'Not connected', True);
  SetLength(Result, Count);
  Offset := 0;
  if TimeoutMs > 0 then
    EffTimeout := TimeoutMs
  else
    EffTimeout := 5000;
  while Offset < Count do
  begin
    Got := FSock.RecvBufferEx(@Result[Offset], Count - Offset, EffTimeout);
    if Got > 0 then
    begin
      Inc(Offset, Got);
      Continue;
    end;
    if FSock.LastError = 110 then
      raise ERstmdbTimeoutError.Create(ERR_TIMEOUT, 'Socket read timed out', True);
    FConnected := False;
    raise ERstmdbTransportError.Create(ERR_CONNECTION_CLOSED,
      'Connection closed by peer', True);
  end;
end;
{$ENDIF}

function CreateDefaultTransport: TRstmdbTransport;
begin
  {$IFDEF RSTMDB_TRANSPORT_SYNAPSE}
  Result := TRstmdbSynapseTransport.Create;
  {$ELSE}
    {$IFDEF RSTMDB_TRANSPORT_RTL}
    Result := TRstmdbRtlTransport.Create;
    {$ELSE}
    raise ERstmdbTransportError.Create(ERR_CONNECTION_FAILED,
      'No supported transport backend defined in rstmdb.inc', False);
    {$ENDIF}
  {$ENDIF}
end;

end.
