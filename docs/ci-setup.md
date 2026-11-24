# CI Workflow Setup

GitHub OAuth tokens without the `workflow` scope cannot push `.github/workflows/*.yml` files directly. Once authorized (`gh auth refresh -h github.com -s workflow`), add `.github/workflows/ci.yml` with the following FPC + live `rstmdb` integration pipeline:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  fpc-test:
    runs-on: ubuntu-latest
    container:
      image: freepascal/fpc:trunk-bookworm-full
    steps:
      - uses: actions/checkout@v4
      - name: Verify FPC version
        run: fpc -iV
      - name: Build and run unit tests (with heaptrc) and examples
        run: |
          make clean
          make test
          make examples

  live-integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          path: sdk
      - uses: actions/checkout@v4
        with:
          repository: rstmdb/rstmdb
          ref: main
          path: server
      - uses: dtolnay/rust-toolchain@stable
      - name: Build rstmdb server
        working-directory: server
        run: cargo build --bin rstmdb
      - name: Run unit + live integration tests in FPC container
        run: |
          DATA_DIR=$(mktemp -d)
          RSTMDB_BIND=127.0.0.1:17405 RSTMDB_DATA="$DATA_DIR" ./server/target/debug/rstmdb >/tmp/rstmdb.log 2>&1 &
          SRV_PID=$!
          trap 'kill $SRV_PID 2>/dev/null || true' EXIT
          for i in $(seq 1 60); do (echo >/dev/tcp/127.0.0.1/17405) 2>/dev/null && break; sleep 0.5; done
          docker run --rm --network host -v "$PWD/sdk:/work" -w /work \
            -e RSTMDB_HOST=127.0.0.1 -e RSTMDB_PORT=17405 \
            freepascal/fpc:trunk-bookworm-full \
            bash -lc "make clean && make test && make examples && make live-test"
```

## Delphi 11+ Local / Self-Hosted Runner Verification

Run `scripts/check-delphi.ps1` from PowerShell on Windows with Embarcadero Delphi 11 Alexandria (or newer) installed:

```powershell
.\scripts\check-delphi.ps1 -Platform Win64
# Or with open-source Ararat Synapse TLS/mTLS:
.\scripts\check-delphi.ps1 -Platform Win64 -Synapse -SynapsePath "C:\libs\synapse\source\lib"
```
