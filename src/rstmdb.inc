{------------------------------------------------------------------------------
  rstmdb-pascal — Unified Compiler Directives (Delphi 11+ & Free Pascal)
 ------------------------------------------------------------------------------}

{$IFDEF FPC}
  {$MODE DELPHI}
  {$H+}
  {$CODEPAGE UTF8}
  {$MODESWITCH ADVANCEDRECORDS}
  {$IF FPC_FULLVERSION < 30202}
    {$FATAL 'rstmdb-pascal requires Free Pascal 3.2.2 or newer'}
  {$IFEND}
{$ELSE}
  {$IFDEF CONDITIONALEXPRESSIONS}
    {$IF CompilerVersion < 35.0}
      {$MESSAGE ERROR 'rstmdb-pascal requires Delphi 11 Alexandria (CompilerVersion 35.0) or newer'}
    {$IFEND}
  {$ELSE}
    {$MESSAGE ERROR 'rstmdb-pascal requires Delphi 11 Alexandria or newer, or Free Pascal 3.2.2+'}
  {$ENDIF}
  {$DEFINE RSTMDB_DELPHI}
{$ENDIF}

{ Transport backend selection (default: RTL sockets) }
{$IF NOT DEFINED(RSTMDB_TRANSPORT_INDY) AND NOT DEFINED(RSTMDB_TRANSPORT_SYNAPSE)}
  {$DEFINE RSTMDB_TRANSPORT_RTL}
{$IFEND}
