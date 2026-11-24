program RunTests;

{$I rstmdb.inc}
{$IFDEF RSTMDB_DELPHI}
  {$APPTYPE CONSOLE}
{$ENDIF}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Rstmdb.TestRunner,
  TestProtocol,
  TestJson,
  TestConnection,
  TestClient;

begin
  {$IFDEF RSTMDB_DELPHI}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  RegisterProtocolTests;
  RegisterJsonTests;
  RegisterConnectionTests;
  RegisterClientTests;
  ExitCode := RunAllTests;
end.
