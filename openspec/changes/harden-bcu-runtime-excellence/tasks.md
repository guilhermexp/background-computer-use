## 1. Shared process supervision

- [x] 1.1 Add RED tests for stdin/stdout/stderr, timeout, output caps, and detached descendants.
- [x] 1.2 Extract one bounded process runner and adapt `run_script` without behavior change.
- [x] 1.3 Run focused process and script parity tests.

## 2. Disposable OCR

- [x] 2.1 Add RED tests for worker protocol, real-text recognition, and parent failure mapping.
- [x] 2.2 Add `--ocr-worker` mode and synchronous Vision engine.
- [x] 2.3 Route all OCR through the bounded worker and remove prewarm/in-process deadline code.
- [x] 2.4 Run focused OCR, click, state, documentation, and release-build gates.

## 3. Exact process discovery

- [x] 3.1 Add RED public-contract and strict-decode tests for PID-only `list_windows`.
- [x] 3.2 Replace fuzzy resolution and app-query coordination metadata with exact PID resolution.
- [x] 3.3 Run discovery, facade, router, and documentation tests.

## 4. Background-safe text

- [x] 4.1 Add RED tests for foreground preservation and removed focus-assist fields.
- [x] 4.2 Centralize WindowServer preparation and require background safety plus exact effect.
- [x] 4.3 Run text, facade, router, and documentation tests.

## 5. Documentation and live proof

- [x] 5.1 Update route docs, skill docs, and PID-driven smoke helpers.
- [x] 5.2 Run `swift build -c release`.
- [x] 5.3 Run `swift test` with zero failures.
- [x] 5.4 Run `openspec validate harden-bcu-runtime-excellence --strict`.
- [x] 5.5 Run signed-app live smoke for duplicate PID selection, repeated OCR, Chrome OCR click, Safari background text, and worker cleanup.
