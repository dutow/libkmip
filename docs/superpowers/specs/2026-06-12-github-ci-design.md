# GitHub CI for the C++ KMIP libraries — Design

Date: 2026-06-12
Status: approved

## Goal

Add basic GitHub Actions CI for this repository, focused on the new C++
libraries (`kmipcore`, `kmipclient`). CI must run on pushes to `master` and on
pull requests, so behavior can be tested directly on a fork's master branch.

## Scope

- Build all targets (libraries, examples, tests) on Linux.
- Run the full CTest suite, including the kmipclient GoogleTest integration
  tests against a live Cosmian KMS server (PyKMIP is no longer used).
- clang-format check limited to `kmipcore/` and `kmipclient/`.
- Doxygen docs build check.

Out of scope: packaging, release automation, Windows/macOS builds, Sphinx docs,
formatting of legacy code (`libkmip/`, `kmippp/`).

## Layout

```
.github/workflows/ci.yml   # single workflow, three jobs
ci/install-cosmian.sh      # download + install pinned Cosmian KMS .deb
ci/start-cosmian.sh        # certs, kms.toml, start server, readiness poll
```

Helper scripts live in `ci/` (mirroring pg_tde's `ci_scripts/`) so the exact
CI steps are reproducible locally.

## Workflow

Triggers: `push` to `master`, and `pull_request` (no branch filter).
A concurrency group cancels superseded runs on the same ref.
All jobs run on `ubuntu-24.04`.

### Job 1: build-test (matrix, fail-fast: false)

Matrix: `compiler: [gcc, clang]` × `build: [Release, ASAN]`
(ASAN = `CMAKE_BUILD_TYPE=Debug` + `WITH_ASAN=ON`). 4 cells.

Steps per cell:

1. Checkout; `apt-get install libssl-dev ninja-build` (+ `clang` for clang cells).
2. `ci/install-cosmian.sh`:
   - Download `cosmian-kms-server-non-fips-static-openssl_5.21.0` amd64 .deb
     from `https://package.cosmian.com/kms/5.21.0/deb/...` (version pinned,
     same as pg_tde); cache the .deb via `actions/cache` keyed on version.
   - `sudo dpkg -i`; then `chmod 0755 /usr/sbin/cosmian_kms` and
     `/usr/local/cosmian/lib/ossl-modules/legacy.so` (package ships them
     0500 root:root; runner is non-root).
3. Configure:
   `cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=<Release|Debug>
   -DWITH_ASAN=<OFF|ON> -DBUILD_TESTS=ON -DBUILD_KMIP_TESTS=ON`
   with `CC`/`CXX` from the matrix.
4. `cmake --build build -j`.
5. `ci/start-cosmian.sh` (also runnable locally):
   - Generate throwaway certs with openssl into a work dir: self-signed CA;
     server cert `CN=127.0.0.1` with `subjectAltName=IP:127.0.0.1`, exported
     to PKCS#12; client cert/key in PEM.
   - Write `kms.toml`: SQLite DB in the work dir, TLS from the PKCS#12 with
     client-cert verification against the CA, KMIP socket on
     `127.0.0.1:<kmip_port>`, HTTP listener on `127.0.0.1:<http_port>`.
   - Ports: pick free ports dynamically (bind-and-release), like pg_tde's
     helper, so the script never collides with other services locally or on
     the runner.
   - Start `cosmian_kms -c kms.toml` (set `OPENSSL_MODULES` if needed),
     redirect output to a log file.
   - Poll `https://127.0.0.1:<http_port>/version` with curl until ready;
     fail the script (and job) after a 15 s timeout.
   - Export `KMIP_*` values to `$GITHUB_ENV` (or stdout for local use).
6. `ctest --test-dir build --output-on-failure` with environment:
   `KMIP_ADDR=127.0.0.1`, `KMIP_PORT`, `KMIP_CLIENT_CA` (client cert PEM),
   `KMIP_CLIENT_KEY`, `KMIP_SERVER_CA` (test CA), `KMIP_TIMEOUT_MS=5000`,
   `KMIP_RUN_2_0_TESTS=1`.
7. On failure (`if: failure()`): upload artifact with the Cosmian log,
   `kms.toml`, and `build/Testing/`. Certs are throwaway, generated per run;
   nothing sensitive is uploaded.

Guard against silent green runs: the kmipclient integration tests
`GTEST_SKIP()` when `KMIP_*` env vars are missing, so the test step must fail
if ctest output reports skipped kmipclient tests.

KMIP 2.0 note: `KMIP_RUN_2_0_TESTS=1` is enabled on the assumption Cosmian
handles the 2.0 suite. If a specific test proves incompatible with Cosmian
during implementation, surface it explicitly (skip with a tracked reason in
the workflow) rather than disabling the flag silently.

### Job 2: format

- Install the ubuntu-24.04 distro `clang-format` (version 18 — pinned by
  relying on the distro package, not upstream releases).
- Run `clang-format --dry-run --Werror` over all `*.hpp`/`*.cpp` under
  `kmipcore/` and `kmipclient/`, using the repo's `.clang-format`.
- Known risk: the current tree is not clean under clang-format 22 locally.
  Implementation must verify against clang-format 18 first; if violations
  exist, a preparatory reformat commit of `kmipcore`/`kmipclient` lands
  before (or with) the workflow so the job starts green.

### Job 3: docs

- `apt-get install doxygen graphviz` (Doxyfile sets `HAVE_DOT = YES`).
- `cmake -S . -B build-docs -DBUILD_DOCS=ON`, then
  `cmake --build build-docs --target doc`.
- Success criterion: Doxygen completes without error. Warnings are not
  errors for now (`WARN_AS_ERROR` stays off).

## Error handling summary

- Cosmian server fails to become healthy → `start-cosmian.sh` exits non-zero,
  job fails.
- Integration tests skipped due to missing env → test step fails.
- Matrix cells are independent (`fail-fast: false`).
- Failure artifacts give server log + test logs for debugging fork runs.

## Testing the CI itself

Work lands directly on `master` (intentional), validated by pushing to a fork
and observing both the push-triggered run and a PR-triggered run. Helper
scripts are testable locally before pushing: run `ci/install-cosmian.sh` +
`ci/start-cosmian.sh`, then build and run ctest with the printed env vars.
