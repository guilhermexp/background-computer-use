# action-verification Specification

## ADDED Requirements

### Requirement: type_text adapts only after an exact unchanged AX no-op

When an AX-writable text target reports a successful value write, `type_text` SHALL immediately reread
the same live element. It SHALL accept an exact expected value, SHALL first attempt the exact target's
advertised `AXTextOperation` when available, and MAY perform at most one PID-scoped Unicode fallback
only when the complete value still equals the prepared baseline after target-bound preparation. It
SHALL fail closed without another dispatch when any partial or ambiguous mutation is present.

#### Scenario: WebKit target-bound fallback completes

- **WHEN** the AX value write is ignored and the exact element advertises `AXTextOperation`
- **THEN** the route attempts that target-bound operation, accepts only the exact expected reread, reports `ax_text_operation`, and posts no Unicode event

#### Scenario: Ignored AX write falls back once

- **WHEN** target-bound preparation is unavailable, fails without mutation, or leaves the complete baseline unchanged
- **THEN** the route focuses the exact target, confirms foreground preservation, posts the requested text once to the target PID, reports `pid_unicode`, and performs final exact verification

#### Scenario: Partial AX mutation never retries

- **WHEN** the immediate observed value differs from both baseline and expected value
- **THEN** the route returns `effect_not_verified` without Unicode fallback

#### Scenario: Exact AX mutation stays on the fast path

- **WHEN** the immediate observed value equals the exact expected value
- **THEN** no Unicode event is posted and final verification remains authoritative

### Requirement: paste restores the complete pasteboard

`paste` SHALL support text, Markdown, and HTML, SHALL dispatch only to an approved exact target window,
and SHALL restore every original pasteboard item/type/byte representation on success and every failure.

#### Scenario: Paste failure preserves clipboard

- **WHEN** target preparation, transport, reread, timeout, or verification fails
- **THEN** the complete pasteboard after the response is semantically identical to the captured pasteboard before the request

### Requirement: action settling is condition based and bounded

Type and click routes SHALL poll route-specific evidence until success or the existing maximum settle
deadline. They SHALL report stage timings and SHALL NOT use a shorter fixed sleep as a substitute for
verification.

#### Scenario: Immediate effect returns early

- **WHEN** sound exact or intent evidence appears on the first poll
- **THEN** the action proceeds to final verification without waiting the full settle deadline
