# BCU activity card preference and compact layout design

Date: 2026-08-28

## Approved behavior

- Add a `Mostrar cartão de atividades` toggle to BCU Control settings.
- The preference is enabled by default and persists across app restarts.
- Disabling it hides the current card immediately and suppresses future floating presentation.
- Activity history continues to be recorded while the card is disabled.
- Re-enabling does not resurrect an old activity; the next activity presents normally.
- Preserve the existing single-card, latest-action-wins, two-second auto-hide behavior.

## Layout correction

The panel combines a hidden transparent title bar with a full-size content view, but SwiftUI still
respects the title-bar safe area. This creates a large empty strip above the first row. Keep the native
panel style and make the card root consume the full panel area, ignoring that invisible safe-area
inset. Keep the existing internal padding, rounded native window treatment, shadow, nonactivation,
and foreground preservation.

## Data flow

`BCUControlRuntime` loads `BCUActivityCardEnabled` from `UserDefaults`, defaulting to `true` when the
key has never been written. `ControlViewModel` owns the observable value and publishes changes through
a callback. Runtime persists the value and tells `PiPWindowController` to enable or disable
presentation. The controller always receives history events only when enabled; disabling also cancels
the pending dismissal and orders the current panel out.

## Verification

- View-model TDD proves the callback and current state.
- Presentation-state TDD proves disabling clears the current card and blocks presentation until
  re-enabled without affecting history.
- Signed Release QA proves the setting is visible, the disabled state produces zero cards during
  actions, re-enabling produces one card, the card has no large top inset, and it returns to zero after
  two seconds.
