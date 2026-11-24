program RunLiveIntegration;

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
  TestLiveIntegration;

var
  Host: string;
begin
  {$IFDEF RSTMDB_DELPHI}
  ReportMemoryLeaksOnShutdown := True;
  {$ENDIF}
  Host := GetEnvironmentVariable('RSTMDB_HOST');
  if Host = '' then
  begin
    WriteLn('Skipping live integration tests (RSTMDB_HOST is not set).');
    ExitCode := 0;
    Exit;
  end;
  RegisterLiveIntegrationTests;
  ExitCode := RunAllTests;
end.
