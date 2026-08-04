# runtime-security Specification

## ADDED Requirements

### Requirement: Constant-time auth token comparison

The runtime SHALL compare the supplied auth token to the session token in constant time, so a local process on the same host cannot recover the token by timing.

#### Scenario: Token comparison does not early-exit on mismatch

- **WHEN** an authenticated request's token is compared to the session token
- **THEN** the comparison accumulates over all bytes (constant time) rather than returning at the first differing byte

### Requirement: Sensitive files written with owner-only permissions

Files the runtime writes that carry secrets or screen contents SHALL be created with owner-only permissions, so another local user cannot read them even when `TMPDIR` is redirected outside the per-user directory.

#### Scenario: Manifest and captures are 0600

- **WHEN** the runtime writes the manifest (which carries the auth token) or a window screenshot PNG
- **THEN** the file is created with `0600` permissions inside a `0700` directory

### Requirement: Debug artifacts redact typed input

When debug-artifact recording is enabled, the runtime SHALL redact typed text and set values before persisting, so credentials do not land on disk in cleartext.

#### Scenario: Typed text is redacted

- **WHEN** a `type_text`/`set_value`/`press_key` request (or a `read_text` response) is recorded as a debug artifact
- **THEN** the `text`/`value`/response text is written as `<redacted len=N>` unless an explicit raw override (`DEBUG_ARTIFACTS_RAW=1`) is set

### Requirement: Loopback host guard

The runtime SHALL reject requests whose `Host` header is not a loopback name, so a malicious web page cannot reach the runtime via DNS rebinding.

#### Scenario: Non-loopback Host is rejected

- **WHEN** a request arrives with a `Host` header that does not start with `127.0.0.1` or `localhost`
- **THEN** the runtime rejects it, while loopback Hosts are served normally

### Requirement: Authentication is mandatory by construction

The server and router SHALL require an auth value with no insecure default, so no future call site can start an unauthenticated server by omitting the parameter.

#### Scenario: No default-disabled auth

- **WHEN** a `LoopbackServer` or `Router` is constructed
- **THEN** an auth value must be supplied explicitly (no `.disabled` default); tests that want auth off pass `.disabled` explicitly

### Requirement: Session exclusion survives concurrent requests

The runtime session mutex SHALL use reference counting so its exclusion holds while any request of the holding session is still executing.

#### Scenario: Concurrent requests of one session do not release early

- **WHEN** a session issues two concurrent requests and the first finishes while the second is still executing
- **THEN** the session exclusion remains held (refcount > 0) and another session cannot acquire it until the second request finishes
