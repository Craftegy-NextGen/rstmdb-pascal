# AGENTS.md — Working Guide for `rstmdb-pascal`

Architectural rules, compiler directive discipline, wire-protocol invariants, and verification commands for building and maintaining `Craftegy-NextGen/rstmdb-pascal`.

## Compiler Support & Directive Policy

- **Minimum Delphi**: **Delphi 11 Alexandria** (`VER350` / `CompilerVersion >= 35.0`). `src/rstmdb.inc` enforces this with a compile-time `{$MESSAGE ERROR ...}` on older Delphi releases.
- **Free Pascal**: **FPC 3.2.2+** and **FPC 3.3.1 trunk**, compiled in Delphi compatibility mode with UTF-8 `AnsiString`:
  - `{$MODE DELPHI}`
  - `{$H+}`
  - `{$CODEPAGE UTF8}`
  - `{$MODESWITCH ADVANCEDRECORDS}`
- **Single-Codebase Rule**: Never fork separate Delphi and FPC unit trees. Every unit in `src/` and `tests/` starts with `{$I rstmdb.inc}` and isolates compiler/RTL differences cleanly behind small adapter units (`Rstmdb.Json.pas`, `Rstmdb.Transport.pas`).

## Build & Verification Commands

```bash
make build      # Compile library/tests with FPC (-Mdelphi -Sh -O2 -vewn)
make test       # Build and run unit tests with heaptrc (-gh) leak check enabled
make clean      # Remove *.ppu, *.o, *.dcu, and bin/ artifacts (ALWAYS run when switching compilers)
```

Live-server integration tests read `RSTMDB_HOST` (e.g. `127.0.0.1`) and `RSTMDB_PORT` (default `7401`) and skip cleanly when `RSTMDB_HOST` is unset.

See [docs/ci-setup.md](./docs/ci-setup.md) for the container-based CI workflow (`freepascal/fpc:trunk-bookworm-full`) running unit + live `rstmdb` server integration tests.

## String Encoding & JSON Rules

- **Wire encoding is UTF-8**: Delphi `string` is UTF-16 `UnicodeString`, whereas FPC `{$MODE DELPHI}{$H+}` `string` with `{$CODEPAGE UTF8}` is UTF-8 `AnsiString`. Always convert explicitly via `TEncoding.UTF8.GetBytes(...)` / `UTF8Encode` / `UTF8Decode` at the `TBytes` wire codec boundary (`Rstmdb.Protocol.pas`), never by casting `Pointer(S)` directly to bytes!
- **64-bit offsets**: Use `Int64` / `UInt64` for `wal_offset`, `latest_offset`, `from_offset`, `bytes_reclaimed`, and chunk offsets (`32-bit` Win32 Delphi builds must never truncate offsets to `Integer`).
- **Numeric fidelity**: Note that `rstmdb` request fingerprinting treats JSON `10` (integer) and `10.0` (float) distinctly. Serialize integer vs floating-point JSON fields with exact types.
- **Deterministic object freeing**: Own parsed JSON AST nodes inside `try..finally` blocks (for both `TJSONObject` in Delphi and `TJSONData` in `fpjson`).

## RCP v1 Binary Frame & Protocol Rules

1. **18-byte Big-Endian Header**:
   - `magic` (`4` bytes): ASCII `"RCPX"` (`$52, $43, $50, $58`)
   - `version` (`2` bytes big-endian): `1` (`PROTOCOL_VERSION`)
   - `flags` (`2` bytes big-endian): bit `0` = `CRC_PRESENT` (`$0001`), bit `1` = `COMPRESSED` (`$0002`), bit `2` = `STREAM` (`$0004`), bit `3` = `END_STREAM` (`$0008`); validate upper bits (`flags and not $000F = 0`)
   - `header_len` (`2` bytes big-endian): extended header bytes to skip/read
   - `payload_len` (`4` bytes big-endian): bounded by `MAX_PAYLOAD_SIZE` (`16 MiB`, `$01000000`) before allocating buffers
   - `crc32c` (`4` bytes big-endian): **CRC32C (Castagnoli, reflected poly `$82F63B78`)** computed over `payload` when `CRC_PRESENT` is set — **not** zlib/IEEE CRC32 (`$EDB88320`)!
2. **Forward-Compatible Open `ErrorCode`**:
   - Represent error codes as string constants (`Rstmdb.Types.pas`) and helper predicates (`IsRetryableCode`, `IsIdempotencyConflict`, `IsGuardUnknown`, etc.).
   - Never raise a client parse error on unrecognized server error codes; preserve `Code: string`, `Message: string`, `Retryable: Boolean`, and `Details`.
3. **Handshake (`HELLO`) & Parity**:
   - Negotiate `"features": ["idempotency", "durable_idempotency", "batch"]` in `HELLO` and expose negotiated server features on the client.
   - Surface `Applied: Boolean` on `ApplyEvent` results (`False` on idempotent replay).
   - Expose `BACKUP_BEGIN`, `BACKUP_CHUNK`, `BACKUP_END`, `REPLICATION_STATUS`, `BATCH`, and filtered `WATCH_INSTANCE` / `WATCH_ALL`.

## Quality & Git Discipline

- **0 warnings / 0 notes** in both Delphi (`dcc32`/`dcc64 -W+ -H+`) and FPC (`-vewn`).
- **0 memory leaks**: every test binary must exit with 0 unfreed blocks under `-gh` (FPC) and `ReportMemoryLeaksOnShutdown := True` (Delphi).
- Keep the library **free of GUI dependencies** (no `Vcl.*`, `FMX.*`, or `LCL` units in `src/`).
- Always run `make clean` when switching between FPC versions or target triplets (`stale .ppu` files cause subtle runtime crashes).
