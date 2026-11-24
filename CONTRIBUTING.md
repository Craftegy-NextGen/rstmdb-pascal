# Contributing to `rstmdb-pascal`

Thank you for contributing! Please follow the dual-compiler guidelines in [`AGENTS.md`](./AGENTS.md) so every change compiles and runs cleanly under both **Delphi 11 Alexandria+** and **Free Pascal (3.2.2+ / 3.3.1)**.

## Checklist

1. Include `{$I rstmdb.inc}` at the top of every unit in `src/` and `tests/`.
2. Isolate compiler/RTL differences behind `Rstmdb.Json.pas` and `Rstmdb.Transport.pas`.
3. Keep core units free of VCL, FMX, or LCL dependencies.
4. Verify zero compiler warnings/notes (`-vewn` in FPC; warnings clean in Delphi) and zero memory leaks (`-gh` heaptrc / `ReportMemoryLeaksOnShutdown := True`).
5. Preserve open string `ErrorCode` forward-compatibility and `Int64`/`UInt64` WAL offset types.
