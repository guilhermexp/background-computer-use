# Plan 012: Anchor global coordinate flips to the primary display

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 0110ffb..HEAD -- Sources/BackgroundComputerUse/Shared/DesktopGeometry.swift Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift Tests/BackgroundComputerUseTests/DesktopGeometryTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. Also run `git status --short` and
> STOP if the working tree does not contain (or HEAD does not already include)
> the planned-at fixes to `Router.swift`, `BackgroundComputerUseControlBridge.swift`,
> `CodeSignatureIdentity.swift`, `RuntimeExecutionQueue.swift`,
> `AdaptiveTextDispatcher.swift`, `InteractionToken.swift`,
> `BoundedProcessRunner.swift`, `bcu-request.py`, `InteractionTokenTests.swift`,
> and `RuntimeExecutionQueueTests.swift`.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: `plans/004-real-app-ax-fixture-corpus.md`
- **Category**: bug
- **Planned at**: commit `0110ffb`, 2026-09-02

## Why this matters

AppKit global coordinates are bottom-left based around the primary display, while Quartz/AX global coordinates are top-left based around that same display. The current flip uses the highest `maxY` across all screens, so placing a monitor above the primary display adds that monitor's height to every converted AX frame and native click point. The fix makes the transform deterministic and testable without attaching displays, while preserving x coordinates and valid negative coordinates for displays above, below, or left of the primary.

## Current state

- `Sources/BackgroundComputerUse/Shared/DesktopGeometry.swift` owns every shared AppKit↔Quartz/AX rectangle/origin conversion.
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift` performs two additional global point flips for semantic telemetry and native coordinate dispatch.
- `Sources/BackgroundComputerUse/Shared/DesktopGeometry.swift:5-13` currently uses the desktop union's highest edge:

```swift
enum DesktopGeometry {
    static func desktopTop() -> CGFloat {
        NSScreen.screens.map(\.frame.maxY).max() ?? 0
    }

    static func appKitRect(fromQuartz rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: desktopTop() - rect.minY - rect.height,
```

- The remaining shared conversions repeat the same constant at `DesktopGeometry.swift:20-34`: `appKitRect(fromAXOrigin:size:)` subtracts AX y and height; `axOrigin(fromAppKitFrame:)` performs the inverse.
- The complete `desktopTop(` caller audit from the live tree is:
  - `DesktopGeometry.swift:13` — Quartz global rectangle to AppKit global rectangle; this is a global-space conversion.
  - `DesktopGeometry.swift:23` — AX global origin/size to AppKit global rectangle; this is a global-space conversion.
  - `DesktopGeometry.swift:33` — AppKit global frame to AX global origin; this is a global-space conversion.
  - `ClickRouteService.swift:1258` — AppKit cursor target to top-left global point in semantic-click transport telemetry; this is a global-space conversion.
  - `ClickRouteService.swift:2577-2580` — AppKit target to the event-tap point sent to the native click transport; this is a global-space conversion.
- `ClickRouteService.swift:2573-2587` separately maps window-local screenshot pixels and the global event point. Only the latter needs the primary-display flip:

```swift
let modelPoint = CGPoint(
    x: (appKitPoint.x - frame.minX) * scale.x,
    y: (frame.maxY - appKitPoint.y) * scale.y
)
let eventTapPoint = CGPoint(
    x: appKitPoint.x,
    y: DesktopGeometry.desktopTop() - appKitPoint.y
)
```

- `openspec/project.md:7-15` fixes the environment and safety contract: Swift 6.2, macOS 14, Apple runtime SDKs only, Swift Testing rather than XCTest, and verifier-first read-act-read actions that report background errors instead of hiding them by stealing focus.
- Use `Tests/BackgroundComputerUseTests/WindowStatePayloadParityTests.swift:407-493` as the local Swift Testing/helper style exemplar: private fixture helpers, `@Test`, and `#expect` under `@testable import BackgroundComputerUse`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Locate old callers | `grep -R "desktopTop(" Sources/BackgroundComputerUse Tests/BackgroundComputerUseTests` | five current source matches before the change; no matches after the clean cutover |
| Focused tests | `swift test --filter DesktopGeometryTests` | exit 0; all geometry tests pass |
| Build | `swift build` | exit 0, no Swift errors |
| Full regression gate | `swift test` | exit 0; all tests pass (391 baseline plus the new tests) |
| Display inventory (optional live check) | `system_profiler SPDisplaysDataType` | exit 0; two display entries are required to perform the optional checklist |

## Scope

**In scope** (the only source/test files you should modify):
- `Sources/BackgroundComputerUse/Shared/DesktopGeometry.swift`
- `Sources/BackgroundComputerUse/Actions/Click/ClickRouteService.swift`
- `Tests/BackgroundComputerUseTests/DesktopGeometryTests.swift` (create)
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though they look related):
- Screenshot scaling, Retina pixel conversion, cursor compositing, and window-local model coordinates; their transforms do not use `desktopTop()`.
- Native click transport ordering, private WindowServer symbols, and click verification policy; plan 014 handles private-symbol capability degradation.
- `NSScreen.main`; it follows the screen containing the key window and can change as focus changes. Use `NSScreen.screens.first`, which represents the primary/menu-bar display and is the stable global-space reference.
- Adding display mocks around AppKit. The pure `primaryTop` parameter is the test seam.

## Git workflow

- Branch: `advisor/012-multi-display-geometry`
- Commit logical units with the repository's conventional style, for example `fix: anchor coordinate flips to the primary display`.
- Do NOT push or open a PR unless the operator instructs it.

## Steps

### Step 1: Add failing synthetic-layout tests

Create `Tests/BackgroundComputerUseTests/DesktopGeometryTests.swift`. Use the following fixture shape; secondary frames are deliberately retained to document the layout while `primaryTop` remains independent of their extrema:

```swift
import CoreGraphics
import Testing
@testable import BackgroundComputerUse

private struct ScreenLayoutFixture {
    let primary: CGRect
    let secondary: [CGRect]

    var primaryTop: CGFloat { primary.maxY }
}

@Suite
struct DesktopGeometryTests {
    private let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test
    func displayAboveDoesNotChangeFlipAxis() {
        let layout = ScreenLayoutFixture(
            primary: primary,
            secondary: [CGRect(x: 0, y: 1080, width: 2560, height: 1440)]
        )
        #expect(layout.secondary[0].maxY == 2520)
        #expect(DesktopGeometry.flip(y: 100, primaryTop: layout.primaryTop) == 980)
        #expect(DesktopGeometry.flip(y: 1200, primaryTop: layout.primaryTop) == -120)
    }

    @Test
    func displaysBelowAndLeftPreserveNegativeCoordinates() {
        let layout = ScreenLayoutFixture(
            primary: primary,
            secondary: [
                CGRect(x: 0, y: -900, width: 1600, height: 900),
                CGRect(x: -2560, y: 0, width: 2560, height: 1440),
            ]
        )
        #expect(DesktopGeometry.flip(y: -400, primaryTop: layout.primaryTop) == 1480)
        let quartz = CGRect(x: -2500, y: 100, width: 400, height: 200)
        let appKit = DesktopGeometry.appKitRect(fromQuartz: quartz, primaryTop: layout.primaryTop)
        #expect(appKit == CGRect(x: -2500, y: 780, width: 400, height: 200))
    }

    @Test
    func axAndAppKitRectConversionRoundTrips() {
        let layout = ScreenLayoutFixture(primary: primary, secondary: [])
        let axOrigin = CGPoint(x: 320, y: 175)
        let size = CGSize(width: 640, height: 480)
        let appKit = DesktopGeometry.appKitRect(
            fromAXOrigin: axOrigin,
            size: size,
            primaryTop: layout.primaryTop
        )
        #expect(DesktopGeometry.axOrigin(fromAppKitFrame: appKit, primaryTop: layout.primaryTop) == axOrigin)
    }
}
```

**Verify**: `swift test --filter DesktopGeometryTests` → compilation fails because the injected `flip` and `primaryTop` overloads do not exist yet.

### Step 2: Replace the desktop-union constant with a pure primary-display transform

In `DesktopGeometry.swift`, delete `desktopTop()`. Add the exact pure function and make all three rectangle/origin APIs injectable while retaining no-argument production call sites:

```swift
static func primaryScreenTop() -> CGFloat {
    // `screens.first` is the primary/menu-bar display. `NSScreen.main` follows
    // the key window and is therefore not a stable global-coordinate reference.
    NSScreen.screens.first?.frame.maxY ?? 0
}

static func flip(y: CGFloat, primaryTop: CGFloat) -> CGFloat {
    primaryTop - y
}

static func appKitRect(
    fromQuartz rect: CGRect,
    primaryTop: CGFloat = DesktopGeometry.primaryScreenTop()
) -> CGRect {
    CGRect(
        x: rect.minX,
        y: flip(y: rect.minY + rect.height, primaryTop: primaryTop),
        width: rect.width,
        height: rect.height
    ).standardized
}

static func appKitRect(
    fromAXOrigin origin: CGPoint,
    size: CGSize,
    primaryTop: CGFloat = DesktopGeometry.primaryScreenTop()
) -> CGRect {
    CGRect(
        x: origin.x,
        y: flip(y: origin.y + size.height, primaryTop: primaryTop),
        width: size.width,
        height: size.height
    ).standardized
}

static func axOrigin(
    fromAppKitFrame frame: CGRect,
    primaryTop: CGFloat = DesktopGeometry.primaryScreenTop()
) -> CGPoint {
    CGPoint(x: frame.minX, y: flip(y: frame.minY + frame.height, primaryTop: primaryTop))
}
```

Do not use `max(NSScreen.screens.map(\.frame.maxY))`, `NSScreen.main`, or the desktop union. The fallback `0` preserves the current no-screen behavior.

**Verify**: `swift test --filter DesktopGeometryTests` → exit 0; the above/left/below and round-trip tests pass.

### Step 3: Migrate both click point conversions

In `ClickRouteService.swift:1258` and `ClickRouteService.swift:2577-2580`, replace subtraction against `desktopTop()` with `DesktopGeometry.flip(y:primaryTop:)`. Read `primaryScreenTop()` once in `coordinatePlan` before creating `eventTapPoint`; the semantic telemetry map may call it inline because it evaluates once per optional point:

```swift
eventTapPointTopLeft: cursor.targetPointAppKit.map {
    PointDTO(
        x: $0.x,
        y: DesktopGeometry.flip(y: $0.y, primaryTop: DesktopGeometry.primaryScreenTop())
    )
},
```

```swift
let primaryTop = DesktopGeometry.primaryScreenTop()
let eventTapPoint = CGPoint(
    x: appKitPoint.x,
    y: DesktopGeometry.flip(y: appKitPoint.y, primaryTop: primaryTop)
)
```

Do not alter the screenshot/model-point calculation at lines 2573-2576.

**Verify**: `grep -R "desktopTop(" Sources/BackgroundComputerUse Tests/BackgroundComputerUseTests` → no output and exit 1; `swift build` → exit 0.

### Step 4: Run focused and full regression gates

Run the new suite first, then the repository suite once. Do not launch or install the app for this step.

**Verify**: `swift test --filter DesktopGeometryTests && swift test` → both commands exit 0; the full count is the 391-test baseline plus the new geometry tests.

### Step 5: Perform the optional two-display live checklist only when available and authorized

If the machine has two displays and the operator authorizes signed-app live testing, arrange the secondary display above the primary in System Settings and use a harmless control in a disposable test app. Confirm: (1) `get_window_state` AX frames overlay the correct visible controls on both displays; (2) one semantic click and one direct coordinate click land on the intended control; (3) moving the target window between primary and upper displays does not introduce a vertical offset; (4) the user's frontmost app and pointer remain unchanged. Repeat with the secondary below or left if convenient. If fewer than two displays are connected or authorization is absent, record this check as skipped; it is not a unit-test failure. Never run `script/start.sh` or a live smoke without explicit operator authorization.

**Verify**: `system_profiler SPDisplaysDataType` → exit 0 and shows at least two displays for a performed check; otherwise note `SKIPPED: no authorized two-display setup` in the execution report.

## Test plan

- New file: `Tests/BackgroundComputerUseTests/DesktopGeometryTests.swift`.
- Regression cases: a 1920×1080 primary at `(0,0)` with a 2560×1440 display above at `y=1080...2520`; a 1600×900 display below at `y=-900...0`; and a 2560-wide display left at `x=-2560`.
- Invariants: the flip axis is always primary `maxY`; x is unchanged; negative AppKit and Quartz y values remain valid; `appKitRect(fromAXOrigin:)` and `axOrigin(fromAppKitFrame:)` round-trip.
- Structural pattern: Swift Testing (`@Suite`, `@Test`, `#expect`) matching `WindowStatePayloadParityTests.swift:407-493`; do not add XCTest.
- Verification: `swift test --filter DesktopGeometryTests` → all new tests pass.

## Done criteria

- [ ] `DesktopGeometry.desktopTop()` is deleted and repository search finds no callers.
- [ ] `primaryScreenTop()` uses `NSScreen.screens.first?.frame.maxY`, not `NSScreen.main` or the desktop union.
- [ ] `flip(y:primaryTop:)` is pure and all three shared conversions accept an injectable `primaryTop`.
- [ ] Both click global-point call sites use the same pure flip.
- [ ] `swift test --filter DesktopGeometryTests` exits 0 with above, below, left, known-point, and round-trip coverage.
- [ ] `swift build` and `swift test` exit 0.
- [ ] No files outside the in-scope list are modified (`git status --short`).
- [ ] Optional live status is explicitly recorded as passed or skipped.
- [ ] `plans/README.md` status row is updated.

## STOP conditions

Stop and report back (do not improvise) if:

- The five `desktopTop(` matches listed in Current state no longer match the live tree.
- `NSScreen.screens.first` is no longer documented/observed as the primary menu-bar display on the supported macOS range.
- A correct primary-display transform requires changing screenshot/model pixel scaling or native transport sequencing.
- The synthetic tests reveal that any production call site uses a window-local rather than global coordinate.
- A verification command fails twice after one reasonable correction.
- The fix requires modifying any out-of-scope file.

## Maintenance notes

- Reviewers should scrutinize the above-primary case; it is the arrangement that distinguishes primary-display height from desktop-union `maxY`.
- Keep the pure transform available even if future code wraps display discovery, so geometry tests remain independent of attached hardware.
- Do not replace `screens.first` with `NSScreen.main` during cleanup: key-window movement would make the global transform nondeterministic.
- Plan 014 changes native coordinate transport capability handling; it must preserve the `eventTapPointTopLeft` produced here.
