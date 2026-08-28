# BCU Adaptive WebKit Text Fallback Design

**Date:** 2026-08-28

## Problem

The signed runtime proved that PID-scoped Unicode posting is not a universal background text
transport. On the Safari ignored-AX fixture, `ax_value -> pid_unicode` dispatched while preserving
foreground and exact focus, but the live value remained empty and the route correctly returned
`effect_not_verified`. The same fixture succeeds through the exact-element `AXTextOperation` lane.

Treating PID Unicode as the only acceptable fallback therefore makes the specification stricter than
the macOS renderer and regresses a previously working background operation.

## Selected design

After an AX value write leaves the complete baseline unchanged, `type_text` uses this ordered adaptive
fallback:

1. Attempt the target-bound `AXTextOperation` only when the exact live element advertises the required
   parameterized attribute and marker range.
2. Reread the same live element. If the complete expected value is present, accept that target-bound
   transport and report `ax_text_operation`.
3. If the target-bound operation is unavailable, fails without mutation, or leaves the complete
   baseline unchanged, focus the same exact element and confirm foreground preservation.
4. Post the requested delta once through PID Unicode, report `pid_unicode`, and keep final exact value
   and selection verification authoritative.
5. Any partial or ambiguous mutation fails closed without another text dispatch.

No route may claim success from dispatch alone. Strategy telemetry must name only transports actually
attempted.

## Qualification contract

The signed Safari smoke explicitly proves the target-bound WebKit lane by requiring
`ax_value + ax_text_operation`, `unchanged_ax_noop`, exact value verification, and foreground
preservation. Swift orchestration tests independently prove the focused `pid_unicode` lane, its
single-attempt bound, and the partial-mutation prohibition. Documentation must distinguish those two
evidence levels instead of claiming that Safari accepted PID Unicode.

## Scope

This correction changes only adaptive `type_text` fallback ordering, its smoke assertion, and the
matching OpenSpec/design evidence. Paste keeps its own target-bound/clipboard strategy. The approved
quit command and the Locked Use hardening remain unchanged.
