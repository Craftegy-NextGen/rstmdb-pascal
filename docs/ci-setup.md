# CI Workflow Setup

GitHub OAuth tokens without the `workflow` scope cannot push `.github/workflows/*.yml` files directly. Once authorized (`gh auth refresh -h github.com -s workflow`), add `.github/workflows/ci.yml` with the following FPC + live `rstmdb` integration pipeline (modeled after the workspace `freepascal/fpc:trunk-bookworm-full` setup):

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
      - name: Build and run unit tests (with heaptrc)
        run: |
          make clean
          make test

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
      - name: Run integration tests under FPC container or host FPC
        working-directory: sdk
        run: |
          DATA_DIR=$(mktemp -d)
          RSTMDB_BIND=127.0.0.1:17405 RSTMDB_DATA="$DATA_DIR" ../server/target/debug/rstmdb >/tmp/rstmdb.log 2>&1 &
          SRV_PID=$!
          trap 'kill $SRV_PID 2>/dev/null || true' EXIT
          for i in $(seq 1 60); do (echo >/dev/tcp/127.0.0.1/17405) 2>/dev/null && break; sleep 0.5; done
          RSTMDB_HOST=127.0.0.1 RSTMDB_PORT=17405 make test
```
