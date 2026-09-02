# Tasks

## 1. Deterministic build identity

- [x] 1.1 Add the standard-library fingerprint calculator over sorted, path-delimited `Sources/`
  content, Git commit, and dirty state.
- [x] 1.2 Inject the four fingerprint fields into the signed main application plist as correctly typed
  plist values.
- [x] 1.3 Add the runtime build-identity DTO, bundle loader, and deterministic loader tests.

## 2. Runtime metadata contract

- [x] 2.1 Add build identity and PID to the runtime manifest while preserving `startedAt` as process
  start time.
- [x] 2.2 Add build identity, PID, and nullable process start time to the unauthenticated health
  response without exposing credentials.
- [x] 2.3 Update `RouteRegistry` and API documentation tests for every added health field.

## 3. Source-runtime freshness

- [x] 3.1 Make source discovery compare the expected checkout fingerprint with the manifest before
  reusing a healthy process.
- [x] 3.2 Stop and rebuild on missing or mismatched source identity, and require the same match while
  waiting for startup.
- [x] 3.3 Preserve existing healthy installed-runtime reuse when `BCU_SOURCE_DIR` is absent.

## 4. Manifest process validation

- [x] 4.1 Load the request manifest once and validate a positive, non-Boolean PID before HTTP.
- [x] 4.2 Treat a missing process as stale, permission-denied probing as alive, malformed PID as
  invalid metadata, and keep explicit `BCU_BASE_URL` manifest-free.
- [x] 4.3 Return recovery guidance naming `ensure-runtime.sh` without printing credentials.

## 5. Regression evidence

- [x] 5.1 Cover clean, dirty, and missing-key bundle identity parsing with Swift Testing.
- [x] 5.2 Cover matching reuse, mismatching restart, and dead-PID request rejection with isolated
  Python subprocess tests and a fake loopback server.
- [x] 5.3 Prove tests never launch, install, or signal a real BackgroundComputerUse process.

## 6. Gates

- [x] 6.1 Run focused Swift build-identity and API-documentation tests.
- [x] 6.2 Run `python3 -m unittest script.test_ensure_runtime -v`.
- [x] 6.3 Run `swift test` and `openspec validate expose-runtime-build-fingerprint --strict` when the
  OpenSpec CLI is available. Signed live smoke is skipped unless the operator explicitly authorizes
  it.
