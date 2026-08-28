# BCU single transient activity card design

Date: 2026-08-27

## Problem

The activity PiP currently allocates one always-on-top panel per target window and never removes an
entry. Actions across Safari and Chrome therefore accumulate persistent cards across every Space.

## Approved behavior

- Maintain exactly one activity card for the whole BCU session.
- Reuse that card for every action, replacing its action, verdict, summary, app, and screenshot.
- Keep the card nonactivating so it never steals foreground focus.
- Hide it two seconds after the latest activity.
- Cancel or invalidate the previous dismissal whenever a newer activity arrives, so an old timer
  cannot hide newer content.
- Preserve the complete activity history in `ActivityHistoryStore`; only the floating presentation is
  transient.

## Implementation

`PiPWindowController` will replace its dictionary of per-window entries with one optional entry. A
small presentation state will issue a monotonically increasing generation for each activity. The
scheduled dismissal may hide the panel only when its generation still matches the latest one.

## Verification

- RED test: two different window activities still produce one presentation slot containing the latest
  activity.
- RED test: a stale dismissal generation cannot hide the newer activity, while the current generation
  can.
- Focused Swift tests for the PiP presentation state.
- Full Swift suite.
- Signed universal Release smoke with several actions, verifying one visible panel immediately and
  zero panels after more than two seconds.
