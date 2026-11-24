program WatchEvents;

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
  Rstmdb.Client;

var
  Client: TRstmdbClient;
  Host: string;
  Port: Word;
  Machines, EmptyArr: TRstmdbStringArray;
  WatchRes: TRstmdbWatchAllResult;
  Ev: TRstmdbStreamEvent;
  Tries: Integer;
begin
  Host := GetEnvironmentVariable('RSTMDB_HOST');
  if Host = '' then
    Host := '127.0.0.1';
  Port := Word(StrToIntDef(GetEnvironmentVariable('RSTMDB_PORT'), RSTMDB_DEFAULT_PORT));

  Client := TRstmdbClient.Create(Host, Port);
  try
    Client.Connect;

    Client.PutMachine(
      'order',
      1,
      '{"states":["pending","paid"],"initial":"pending",' +
      '"transitions":[{"from":"pending","event":"PAY","to":"paid"}]}'
    );

    SetLength(Machines, 1);
    Machines[0] := 'order';
    SetLength(EmptyArr, 0);
    WatchRes := Client.WatchAll(Machines, EmptyArr, EmptyArr, EmptyArr, True, -1);
    WriteLn('Subscribed: ', WatchRes.SubscriptionId);

    Client.CreateInstance('order', 1, 'watch-order-1', '{"customer":"bob"}');
    Client.ApplyEvent('watch-order-1', 'PAY', '{"amount":99}');

    for Tries := 1 to 20 do
    begin
      if Client.PollStreamEvent(Ev) then
      begin
        WriteLn('Stream event: ', Ev.InstanceId, ' ', Ev.FromState, ' -> ', Ev.ToState,
          ' offset=', Ev.WalOffset);
        Break;
      end;
      Sleep(25);
    end;

    Client.Unwatch(WatchRes.SubscriptionId);
  finally
    Client.Free;
  end;
end.
