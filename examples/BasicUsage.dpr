program BasicUsage;

{$I rstmdb.inc}
{$IFDEF RSTMDB_DELPHI}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Errors,
  Rstmdb.Client;

var
  Client: TRstmdbClient;
  Host: string;
  Port: Word;
  Created: TRstmdbCreateInstanceResult;
  Applied1, Applied2: TRstmdbApplyEventResult;
begin
  Host := GetEnvironmentVariable('RSTMDB_HOST');
  if Host = '' then
    Host := '127.0.0.1';
  Port := Word(StrToIntDef(GetEnvironmentVariable('RSTMDB_PORT'), RSTMDB_DEFAULT_PORT));

  Client := TRstmdbClient.Create(Host, Port);
  try
    Client.Connect;
    WriteLn('Connected. Negotiated features: ', Length(Client.NegotiatedFeatures));

    Client.PutMachine(
      'order',
      1,
      '{"states":["pending","paid","shipped"],"initial":"pending",' +
      '"transitions":[{"from":"pending","event":"PAY","to":"paid"},' +
      '{"from":"paid","event":"SHIP","to":"shipped"}]}'
    );

    Created := Client.CreateInstance('order', 1, 'order-100', '{"customer":"alice"}', 'create-order-100');
    WriteLn('Created instance: ', Created.InstanceId, ' state=', Created.State);

    Applied1 := Client.ApplyEvent(Created.InstanceId, 'PAY', '{"amount":42}', 'pay-order-100');
    WriteLn('First PAY: to=', Applied1.ToState, ' applied=', Applied1.Applied, ' wal_offset=', Applied1.WalOffset);

    Applied2 := Client.ApplyEvent(Created.InstanceId, 'PAY', '{"amount":42}', 'pay-order-100');
    WriteLn('Replay PAY: to=', Applied2.ToState, ' applied=', Applied2.Applied, ' wal_offset=', Applied2.WalOffset);

    try
      Client.ApplyEvent(Created.InstanceId, 'SHIP', '{}', 'pay-order-100');
    except
      on E: ERstmdbServerError do
        WriteLn('Expected error: code=', E.Code, ' is_idempotency_conflict=', IsIdempotencyConflict(E));
    end;
  finally
    Client.Free;
  end;
end.
