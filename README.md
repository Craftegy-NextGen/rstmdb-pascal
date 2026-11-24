# rstmdb-pascal

Unified Object Pascal client SDK for [**rstmdb**](https://github.com/rstmdb/rstmdb) supporting **Delphi (11 Alexandria and newer)** and **Free Pascal (FPC 3.2.2+ / 3.3.1)** from a **single shared codebase** controlled via compiler directives (`src/rstmdb.inc`).

## Highlights

- **Single-Codebase Dual-Compiler Design**: Shared `.pas` units include `src/rstmdb.inc` to compile cleanly under Delphi 11+ (`{$IF CompilerVersion >= 35.0}`) and FPC (`{$MODE DELPHI}{$H+}{$CODEPAGE UTF8}`).
- **Full RCP v1 Wire Protocol**: Binary 18-byte big-endian `"RCPX"` framing, CRC32C (`0x82F63B78` Castagnoli) verification, and UTF-8 JSON payloads.
- **v0.3.0 & v1.0 Protocol Parity Target**:
  - `HELLO` capability negotiation (`idempotency`, `durable_idempotency`, `batch`) and optional `AUTH` (`bearer`)
  - Machine & instance lifecycle (`PUT_MACHINE`, `GET_MACHINE`, `LIST_MACHINES`, `CREATE_INSTANCE`, `GET_INSTANCE`, `LIST_INSTANCES`, `DELETE_INSTANCE`)
  - `APPLY_EVENT` (including `applied` flag, `expected_state`, `expected_wal_offset`, `event_id`, `idempotency_key`), `BATCH` (`atomic` and `best_effort`)
  - Filtered real-time streaming (`WATCH_INSTANCE`, `WATCH_ALL`, `UNWATCH`)
  - WAL, compaction, replication status, hot backups (`BACKUP_BEGIN`, `BACKUP_CHUNK`, `BACKUP_END`), and `FLUSH_ALL`
- **Forward-Compatible Errors**: Open string-backed `ErrorCode` constants + predicates (`IsIdempotencyConflict`, `IsGuardUnknown`, `IsRetryableCode`, etc.) so unrecognized server error codes preserve their wire code and `retryable` flag without crashing older clients.
- **Framework-Agnostic Core**: Compiles without VCL, FMX, or LCL dependencies for headless servers, daemons, CLI tools, and desktop/mobile applications.

## Supported Compilers & Platforms

| Compiler / Toolchain | Minimum Version | Mode / Requirement | Target OS |
|---|---|---|---|
| **Embarcadero Delphi** | Delphi 11 Alexandria (`VER350` / `CompilerVersion >= 35.0`) | `System.Net.Socket`, `System.JSON` / adapter | Windows (Win32/Win64), Linux64, macOS |
| **Free Pascal (FPC)** | FPC 3.2.2+ / 3.3.1 trunk | `{$MODE DELPHI}{$H+}{$CODEPAGE UTF8}` | Linux (`x86_64`/`aarch64`), Windows, macOS, FreeBSD |

## Planned Unit Structure

```text
src/
├── rstmdb.inc                # Compiler version guard, {$MODE DELPHI}, and backend defines
├── Rstmdb.Types.pas          # Operations, open ErrorCode constants, request/result records
├── Rstmdb.Errors.pas         # ERstmdbError, ERstmdbConnectionError, ERstmdbProtocolError, ERstmdbServerError
├── Rstmdb.Protocol.pas       # CRC32C (0x82F63B78), 18-byte "RCPX" frame encoder/decoder
├── Rstmdb.Json.pas           # Dual-compiler JSON abstraction (System.JSON / fpjson)
├── Rstmdb.Transport.pas      # TCP / TLS / mTLS socket abstraction (RTL / Indy / Synapse)
├── Rstmdb.Connection.pas     # Thread-safe request correlation, HELLO/AUTH handshake, reader thread
└── Rstmdb.Client.pas         # High-level TRstmdbClient API
```

## Installation

### Delphi (Boss Package Manager)

```bash
boss install github.com/Craftegy-NextGen/rstmdb-pascal
```

Or add `./src` to your Delphi project's **Search Path** / install the `.dpk` package (Delphi 11 Alexandria or newer).

### Free Pascal / Lazarus

Add `./src` to your compiler unit search path (`-Fu./src`) or open the `.lpk` package in Lazarus:

```bash
make build
make test
```

## Quick Start (Planned API Shape)

```pascal
program BasicUsage;

uses
  SysUtils,
  Rstmdb.Types,
  Rstmdb.Client;

var
  Client: TRstmdbClient;
  Created: TRstmdbCreateInstanceResult;
  Applied: TRstmdbApplyEventResult;
begin
  Client := TRstmdbClient.Create('127.0.0.1', 7401);
  try
    Client.Connect;
    Created := Client.CreateInstance('order', 1, 'order-100');
    Applied := Client.ApplyEvent(Created.InstanceId, 'PAY', '{"amount": 42}', 'pay-order-100');
    WriteLn('State: ', Applied.ToState, ' Applied: ', Applied.Applied);
  finally
    Client.Free;
  end;
end.
```

## Development & Verification

- Read [AGENTS.md](./AGENTS.md) and [CONTRIBUTING.md](./CONTRIBUTING.md) before modifying units or compiler directives.
- Every commit must compile with **0 warnings / 0 notes** and **0 memory leaks** (`fpc -gh` under FPC; `ReportMemoryLeaksOnShutdown := True` under Delphi).
- See [docs/ci-setup.md](./docs/ci-setup.md) for the GitHub Actions FPC + live `rstmdb` integration CI workflow setup.

## License

MIT — see [LICENSE](./LICENSE).
