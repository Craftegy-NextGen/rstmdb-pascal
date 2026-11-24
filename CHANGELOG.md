# Changelog

All notable changes to `rstmdb-pascal` will be documented in this file.

## [Unreleased]

- Implement RCP v1 protocol core (`Rstmdb.Types`, `Rstmdb.Errors`, `Rstmdb.Protocol` with Castagnoli CRC32C `$82F63B78` and 18-byte `"RCPX"` framing).
- Implement dual-compiler JSON adapter & UTF-8 `TBytes` boundary (`Rstmdb.Json` for `fpjson` and `System.JSON`).
- Implement open-source cross-OS transport layer (`Rstmdb.Transport` with `RTL` and `Synapse` backends) and multiplexed `Rstmdb.Connection` (`HELLO durable_idempotency`, bearer `AUTH`, headless reader `TThread`, and watch FIFO queue).
- Implement full `v0.3.0`/`v1.0` `TRstmdbClient` (`Rstmdb.Client`) and runnable `examples/BasicUsage.dpr` + `examples/WatchEvents.dpr`.
- Add Delphi `.dpk` / Lazarus `.lpk` packages, `scripts/check-delphi.ps1`, live-server integration test suite (`tests/TestLiveIntegration.pas`, `tests/RunLiveIntegration.dpr`), and CI setup docs.
