# runtime-bootstrap Specification

## ADDED Requirements

### Requirement: Packaged runtime reports deterministic build provenance

The build pipeline SHALL calculate one deterministic identity from the 12-character Git commit, the
repository dirty state, and the SHA-256 digest of sorted, path-delimited tracked and unignored files
under `Sources/`. The signed main application plist, unauthenticated `/health` response, and owner-only
runtime manifest SHALL report the same identity, commit, dirty flag, and source digest. Health and the
manifest SHALL report the runtime PID and process start time. Health SHALL NOT expose the manifest
credential.

#### Scenario: Packaged runtime reports the exact fingerprint on both surfaces

- **WHEN** the main application is built and starts its loopback runtime
- **THEN** its plist, `/health`, and runtime manifest report the exact same four build fields
- **AND** health and the manifest report the process PID and start time without exposing `authToken`

#### Scenario: Missing development metadata stays explicit

- **WHEN** the runtime executes from a bundle without the injected build keys
- **THEN** it reports the explicit `development-unknown` identity with unknown commit and digest and
  a dirty flag rather than inventing packaged provenance

### Requirement: Source discovery reuses only an exact checkout match

When `BCU_SOURCE_DIR` is set, runtime discovery SHALL compute the checkout identity with the canonical
fingerprint calculator and SHALL reuse a healthy runtime only when its owner manifest contains the
exact same identity. Missing or mismatched identity SHALL be treated as stale. Without
`BCU_SOURCE_DIR`, healthy installed-runtime discovery SHALL retain its existing behavior.

#### Scenario: Exact source identity is reused

- **WHEN** a healthy runtime manifest identity exactly matches the requested source checkout
- **THEN** discovery returns that runtime without invoking the source start script

#### Scenario: Source mismatch stops and rebuilds

- **WHEN** a healthy runtime manifest identity is missing or differs from the requested checkout
- **THEN** discovery reports both non-secret identities, stops the stale runtime, removes its manifest,
  invokes the configured source start path, and waits until the new manifest identity exactly matches

#### Scenario: Unrelated healthy runtime cannot satisfy startup

- **WHEN** the source start path returns while a healthy runtime with another identity is discoverable
- **THEN** the startup wait remains unsatisfied and does not return that unrelated process

### Requirement: Request helper validates manifest process liveness before HTTP

When no explicit `BCU_BASE_URL` override is present, the request helper SHALL load the runtime manifest
once, require a positive non-Boolean PID, and probe that PID before constructing a network request. A
missing process or malformed PID SHALL fail with the manifest path and exact `ensure-runtime.sh`
recovery guidance. Permission denial while probing SHALL mean the process exists. The helper SHALL
never print the manifest credential.

#### Scenario: Dead manifest PID fails before HTTP

- **WHEN** the runtime manifest contains a positive PID that no longer exists
- **THEN** the request fails before network I/O and ends with `Run skills/background-computer-use/scripts/ensure-runtime.sh to start or refresh the runtime.`

#### Scenario: Explicit base URL remains manifest-free

- **WHEN** `BCU_BASE_URL` is explicitly supplied
- **THEN** the request helper does not require or validate runtime manifest process metadata
