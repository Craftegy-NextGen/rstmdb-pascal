unit Rstmdb.TestRunner;

{$I rstmdb.inc}

interface

uses
  SysUtils;

type
  TRstmdbTestProc = procedure;

procedure RegisterTest(const Name: string; Proc: TRstmdbTestProc);
procedure Check(Condition: Boolean; const Msg: string = 'Assertion failed');
procedure CheckEquals(const Expected, Actual: string; const Msg: string = ''); overload;
procedure CheckEquals(Expected, Actual: Int64; const Msg: string = ''); overload;
procedure CheckEquals(Expected, Actual: Cardinal; const Msg: string = ''); overload;
procedure CheckEquals(Expected, Actual: Boolean; const Msg: string = ''); overload;
procedure Fail(const Msg: string);
function RunAllTests: Integer;

implementation

type
  TTestEntry = record
    Name: string;
    Proc: TRstmdbTestProc;
  end;

var
  Tests: array of TTestEntry;
  TestCount: Integer = 0;

procedure RegisterTest(const Name: string; Proc: TRstmdbTestProc);
begin
  if TestCount >= Length(Tests) then
    SetLength(Tests, TestCount + 16);
  Tests[TestCount].Name := Name;
  Tests[TestCount].Proc := Proc;
  Inc(TestCount);
end;

procedure Fail(const Msg: string);
begin
  raise Exception.Create(Msg);
end;

procedure Check(Condition: Boolean; const Msg: string);
begin
  if not Condition then
    Fail(Msg);
end;

procedure CheckEquals(const Expected, Actual: string; const Msg: string);
var
  Prefix: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Prefix := Msg + ': '
    else
      Prefix := '';
    Fail(Format('%sexpected "%s", got "%s"', [Prefix, Expected, Actual]));
  end;
end;

procedure CheckEquals(Expected, Actual: Int64; const Msg: string);
var
  Prefix: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Prefix := Msg + ': '
    else
      Prefix := '';
    Fail(Format('%sexpected %d, got %d', [Prefix, Expected, Actual]));
  end;
end;

procedure CheckEquals(Expected, Actual: Cardinal; const Msg: string);
var
  Prefix: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Prefix := Msg + ': '
    else
      Prefix := '';
    Fail(Format('%sexpected %u ($%x), got %u ($%x)',
      [Prefix, Expected, Expected, Actual, Actual]));
  end;
end;

procedure CheckEquals(Expected, Actual: Boolean; const Msg: string);
var
  Prefix: string;
begin
  if Expected <> Actual then
  begin
    if Msg <> '' then
      Prefix := Msg + ': '
    else
      Prefix := '';
    Fail(Format('%sexpected %s, got %s',
      [Prefix, BoolToStr(Expected, True), BoolToStr(Actual, True)]));
  end;
end;

function RunAllTests: Integer;
var
  I, Passed, Failed: Integer;
begin
  Passed := 0;
  Failed := 0;
  for I := 0 to TestCount - 1 do
  begin
    try
      Tests[I].Proc();
      Inc(Passed);
      WriteLn('[PASS] ', Tests[I].Name);
    except
      on E: Exception do
      begin
        Inc(Failed);
        WriteLn('[FAIL] ', Tests[I].Name, ': ', E.Message);
      end;
    end;
  end;
  WriteLn(Format('Summary: %d passed, %d failed, %d total', [Passed, Failed, TestCount]));
  if Failed > 0 then
    Result := 1
  else
    Result := 0;
end;

end.
