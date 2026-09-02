## Why

A healthy loopback endpoint proves only that some BCU runtime is alive. When `BCU_SOURCE_DIR` is set,
the helper can currently reuse an older installed or source-built process after the checkout changes,
so validation may exercise code other than the code under test. A stale manifest also reaches HTTP
before its process identity is checked, producing misleading connection failures.

BCU needs one deterministic source identity carried from the checkout into the signed application,
the open health response, and the owner-only runtime manifest. Source discovery must compare that
identity before reuse, and request helpers must reject dead or malformed manifest process metadata
before network I/O.

## What Changes

- Compute one deterministic fingerprint from the Git commit, dirty state, and path-delimited contents
  of tracked and unignored `Sources/` files.
- Inject the fingerprint into the main application plist and expose the same value through `/health`
  and the runtime manifest.
- Add PID and process start time metadata so clients can distinguish runtime instances and reject a
  dead manifest before HTTP.
- When `BCU_SOURCE_DIR` is set, reuse a healthy runtime only when its manifest fingerprint exactly
  matches the checkout; otherwise stop the stale process, remove its manifest, and rebuild/start.
- Keep installed-runtime discovery unchanged when no source checkout is requested, and keep `/health`
  unauthenticated without exposing the manifest credential.

## Impact

- **API:** additive required `/health` fields for build identity and PID, plus nullable process start
  time; no request fields or authentication rules change.
- **Manifest:** additive owner-only build identity and PID fields; existing `startedAt` becomes the
  explicit process start time.
- **Runtime tooling:** source helpers fail closed on fingerprint mismatch and request tooling validates
  manifest process liveness before issuing HTTP.
- **Security:** the fingerprint records provenance but is not authentication; existing signing and
  Control peer-identity checks remain authoritative.
- **Evidence:** deterministic Swift and Python tests cover plist parsing, health metadata, exact source
  matching, mismatch restart, and dead-PID rejection without launching or signaling the real app.
