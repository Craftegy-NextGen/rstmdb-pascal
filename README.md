# rstmdb-pascal

Unified Object Pascal client SDK for [**rstmdb**](https://github.com/rstmdb/rstmdb) supporting **Delphi (11 Alexandria and newer)** and **Free Pascal (FPC 3.2.2+ / 3.3.1)** from a **single shared codebase** controlled via compiler directives (`src/rstmdb.inc`).

## Highlights

- **Single-Codebase Dual-Compiler Design**: Shared `.pas` units include `src/rstmdb.inc` to compile cleanly under Delphi 11+ (`{$IF CompilerVersion >= 35.0}`) and FPC (`{$MODE DELPHI}{$H+}{$CODEPAGE UTF8}{$MODESWITCH ADVANCEDRECORDS}`).
- **100% Open-Source Cross-OS Transport & JSON**:
  - Default `RSTMDB_TRANSPORT_RTL`: zero third-party dependencies — FPC `ssockets` + `opensslsockets` (plain TCP + TLS/mTLS) and Delphi `System.Net.Socket` (plain TCP).
  - Optional `RSTMDB_TRANSPORT_SYNAPSE`: open-source Ararat Synapse (`blcksock` + `ssl_openssl3`) for unified cross-OS TLS/mTLS under both Delphi 11+ and FPC.
  - Built-in JSON adapters (`fpjson`/`jsonparser` on FPC, `System.JSON` on Delphi) with explicit UTF-8 `TBytes` wire conversion.
- **Full RCP v1 Wire Protocol**: Binary 18-byte big-endian `"RCPX"` framing, Castagnoli CRC32C (`$82F63B78`) verification, `16 MiB` pre-allocation bounds check, and header-extension skip.
- **v0.3.0 & v1.0 Protocol Parity**:
  - `HELLO` capability negotiation (`idempotency`, `durable_idempotency`, `batch`) and bearer `AUTH`
  - Machine & instance lifecycle (`PUT_MACHINE`, `GET_MACHINE`, `LIST_MACHINES`, `CREATE_INSTANCE`, `GET_INSTANCE`, `LIST_INSTANCES`, `DELETE_INSTANCE`)
  - `APPLY_EVENT` (`applied`, `expected_state`, `expected_wal_offset`, `event_id`, `idempotency_key`), `BATCH` (`bmAtomic` and `bmBestEffort`)
  - Filtered real-time streaming (`WATCH_INSTANCE`, `WATCH_ALL`, `UNWATCH`) via a headless background reader `TThread` and thread-safe FIFO queue
  - WAL, compaction, replication status, hot backups (`BACKUP_BEGIN`, `BACKUP_CHUNK`, `BACKUP_END`), and `FLUSH_ALL`
- **Forward-Compatible Errors**: Open string-backed `ERR_*` constants and predicates (`IsIdempotencyConflict`, `IsGuardUnknown`, `IsRetryable`, etc.) preserve unrecognized server error codes intact.
- **Framework-Agnostic Core**: Zero VCL, FMX, or LCL dependencies.

## Supported Compilers & Platforms

| Compiler / Toolchain | Minimum Version | Mode / Requirement | Target OS |
|---|---|---|---|
| **Embarcadero Delphi** | Delphi 11 Alexandria (`VER350` / `CompilerVersion >= 35.0`) | `System.Net.Socket` / `System.JSON` (or `-DRSTMDB_TRANSPORT_SYNAPSE` for TLS/mTLS) | Windows (Win32/Win64), Linux64, macOS |
| **Free Pascal (FPC)** | FPC 3.2.2+ / 3.3.1 trunk | `{$MODE DELPHI}{$H+}{$CODEPAGE UTF8}{$MODESWITCH ADVANCEDRECORDS}` | Linux (`x86_64`/`aarch64`), Windows, macOS, FreeBSD |

## Unit Structure

```text
src/
├── rstmdb.inc                # Compiler version guard, {$MODE DELPHI}, and backend defines
├── Rstmdb.Types.pas          # Operations, options, and value-record DTOs
├── Rstmdb.Errors.pas         # Open ERR_* constants, exception hierarchy, and predicates
├── Rstmdb.Protocol.pas       # Castagnoli CRC32C ($82F63B78), 18-byte "RCPX" frame codec
├── Rstmdb.Json.pas           # Dual-compiler JSON adapter (System.JSON / fpjson) & UTF-8 boundary
├── Rstmdb.Transport.pas      # TCP / TLS / mTLS socket abstraction (RTL / Synapse)
├── Rstmdb.Connection.pas     # Multiplexed request correlation, HELLO/AUTH handshake, reader thread
└── Rstmdb.Client.pas         # High-level TRstmdbClient API
```

## Installation

### Delphi (Boss Package Manager / `.dpk`)

```bash
boss install github.com/Craftegy-NextGen/rstmdb-pascal
```

Or open `packages/rstmdb_pascal.dpk` in Delphi 11+ / run `scripts/check-delphi.ps1`.

### Free Pascal / Lazarus

Add `./src` to your unit search path (`-Fu./src -Fi./src`) or open `packages/rstmdb_pascal.lpk`:

```bash
make build
make test
make examples
```

To run the gated live-server integration suite:

```bash
RSTMDB_HOST=127.0.0.1 RSTMDB_PORT=7401 make live-test
```

## Quick Start

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
    Client.PutMachine('order', 1,
      '{"states":["pending","paid"],"initial":"pending",' +
      '"transitions":[{"from":"pending","event":"PAY","to":"paid"}]}');
    Created := Client.CreateInstance('order', 1, 'order-100', '{"customer":"alice"}', 'create-order-100');
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
