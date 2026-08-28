## 1. Adaptive text

- [x] 1.1 Add RED exact/unchanged/partial decision tests.
- [x] 1.2 Implement the pure adaptive fallback planner.
- [x] 1.3 Add RED route orchestration tests and one verified target-bound text-operation fallback.
- [x] 1.4 Run focused text and background-safety gates.

## 2. Paste

- [x] 2.1 Add RED complete pasteboard round-trip tests.
- [x] 2.2 Implement text/Markdown/HTML paste and strict route wiring.
- [x] 2.3 Prove clipboard restoration on success, timeout, and failure.

## 3. Performance

- [x] 3.1 Add RED deterministic-clock condition-wait tests.
- [x] 3.2 Replace fixed type/click settle waits with bounded evidence polling.
- [x] 3.3 Add route-stage performance telemetry.

## 4. Live parity

- [x] 4.1 Add benchmark statistics tests and ignored-AX-write fixture.
- [x] 4.2 Run ten signed warm Safari trials with foreground held by another app.
- [x] 4.3 Pass release build, full Swift suite, Python tests, OpenSpec strict, signed smoke, and benchmark.

Final universal release benchmark with embedded Core XPC authority (end-to-end wall): type_text p50 130.08 ms / p95 148.54 ms; semantic click p50 206.06 ms / p95 210.48 ms; paste p50 204.72 ms / p95 209.03 ms. Every lane completed 10/10 with zero false success and zero foreground violations. Release smoke: 30 pass, 0 fail, 0 skip; three additional cold Chrome runs passed. Benchmark runtime metadata is allowlisted so its ephemeral auth token is never logged.
