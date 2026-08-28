# BCU Direct Quit Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-available `Sair do BCU` Command-Q menu action that cleans the active control session before terminating the macOS app.

**Architecture:** `ControlViewModel` owns the ordered stop-then-quit operation through an injected termination callback. `MenuBarController` exposes the standard macOS command, while `BCUControlRuntime` supplies `NSApplication.shared.terminate(nil)` only at the composition root.

**Tech Stack:** Swift 6, AppKit, Swift Testing, Swift Package Manager, macOS menu-bar accessory app

**Spec:** `docs/plans/2026-08-28-bcu-direct-quit-menu-design.md`

## Global Constraints

- The visible label is exactly `Sair do BCU`.
- The shortcut is Command-Q through the `q` key equivalent.
- Quitting is direct and shows no confirmation dialog.
- Session cleanup completes before native application termination is requested.
- The quit item remains enabled after `Parar sessão`.
- Do not alter pause, resume, stop, settings, activity-card, or Locked Use behavior beyond the cleanup already performed by `SessionControls.stop()`.

---

### Task 1: Ordered quit behavior in the control view model

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/ControlViewModel.swift:123-180`
- Test: `Tests/BackgroundComputerUseTests/ControlViewModelTests.swift`

**Interfaces:**
- Consumes: `SessionControls.stop() -> Void`.
- Produces: `ControlViewModel.init(..., onQuit: @escaping () -> Void = {})` and `ControlViewModel.quit() -> Void`.

- [x] **Step 1: Write the failing ordering test**

Add this test to `ControlViewModelTests`:

```swift
import AppKit

@Test @MainActor
func quitStopsSessionBeforeRequestingApplicationTermination() throws {
    var events: [String] = []
    let controls = SessionControls(onStop: { events.append("stop") })
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = try ControlViewModel(
        store: AppPolicyStore(fileURL: file),
        controls: controls,
        onQuit: { events.append("quit") }
    )

    model.quit()

    #expect(events == ["stop", "quit"])
    #expect(model.isStopped)
    #expect(model.isPaused)
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter ControlViewModelTests.quitStopsSessionBeforeRequestingApplicationTermination
```

Expected: compilation fails because `ControlViewModel` does not accept `onQuit` and has no `quit()` method.

- [x] **Step 3: Implement the minimal ordered quit seam**

Add the stored callback, initializer parameter, and method:

```swift
private let onQuit: () -> Void
```

Append this parameter after `onActivityCardPreferenceChanged` in the existing initializer signature:

```swift
onQuit: @escaping () -> Void = {}
```

Append this assignment immediately after `self.onActivityCardPreferenceChanged = onActivityCardPreferenceChanged`:

```swift
self.onQuit = onQuit
```

Add this method immediately after `stop()`:

```swift
public func quit() {
    stop()
    onQuit()
}
```

- [x] **Step 4: Run the focused suite and verify GREEN**

Run:

```bash
swift test --filter ControlViewModelTests
```

Expected: all `ControlViewModelTests` pass.

---

### Task 2: Native menu command and runtime termination wiring

**Files:**
- Modify: `Sources/BackgroundComputerUseControl/MenuBarController.swift:19-68`
- Modify: `Sources/BackgroundComputerUseControl/BCUControlRuntime.swift:57-84`
- Test: `Tests/BackgroundComputerUseTests/ControlViewModelTests.swift`

**Interfaces:**
- Consumes: `ControlViewModel.quit() -> Void` from Task 1.
- Produces: `MenuBarController.makeMenu() -> NSMenu`, the `Sair do BCU` menu action, and the production AppKit termination callback.

- [x] **Step 1: Write the failing menu contract test**

Add this test to `ControlViewModelTests`:

```swift
@Test @MainActor
func stoppedMenuOffersStandardQuitCommand() throws {
    var didRequestQuit = false
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let model = try ControlViewModel(
        store: AppPolicyStore(fileURL: file),
        onQuit: { didRequestQuit = true }
    )
    model.stop()
    let controller = MenuBarController(model: model)

    let menu = controller.makeMenu()
    let item = try #require(menu.items.last)

    #expect(item.title == "Sair do BCU")
    #expect(item.keyEquivalent == "q")
    #expect(item.keyEquivalentModifierMask.contains(.command))
    #expect(item.isEnabled)
    #expect(menu.items.dropLast().last?.isSeparatorItem == true)
    #expect(NSApplication.shared.sendAction(item.action!, to: item.target, from: item))
    #expect(didRequestQuit)
}
```

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
swift test --filter ControlViewModelTests.stoppedMenuOffersStandardQuitCommand
```

Expected: compilation fails because `MenuBarController.makeMenu()` does not exist.

- [x] **Step 3: Extract menu construction and add the quit item**

Refactor `rebuildMenu()` to assign `statusItem.menu = makeMenu()`. Replace the existing inline construction with:

```swift
func rebuildMenu() {
    statusItem.menu = makeMenu()
}

func makeMenu() -> NSMenu {
    let menu = NSMenu()
    let status = NSMenuItem(
        title: model.isStopped ? "Sessão encerrada" : (model.isPaused ? "Pausado" : "BCU ativo"),
        action: nil,
        keyEquivalent: ""
    )
    status.isEnabled = false
    menu.addItem(status)
    menu.addItem(.separator())

    let pause = NSMenuItem(
        title: model.isPaused ? "Retomar" : "Pausar",
        action: #selector(togglePause),
        keyEquivalent: "p"
    )
    pause.target = self
    pause.isEnabled = model.isStopped == false
    menu.addItem(pause)

    let stop = NSMenuItem(title: "Parar sessão", action: #selector(stopSession), keyEquivalent: ".")
    stop.target = self
    stop.isEnabled = model.isStopped == false
    menu.addItem(stop)

    menu.addItem(.separator())
    let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)

    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Sair do BCU", action: #selector(quitApplication), keyEquivalent: "q")
    quit.target = self
    quit.isEnabled = true
    quit.keyEquivalentModifierMask = [.command]
    menu.addItem(quit)
    return menu
}
```

Add the selector:

```swift
@objc private func quitApplication() {
    model.quit()
}
```

At the `ControlViewModel` composition in `BCUControlRuntime.start()`, supply:

```swift
onQuit: {
    NSApplication.shared.terminate(nil)
}
```

- [x] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter ControlViewModelTests
swift test --filter ActivityControlTests
```

Expected: both focused suites pass; pause, stop, activity-card, and quit behavior remain green.

- [x] **Step 5: Preserve the complete new Control files for the final authorized commit**

The four implementation/test files are wholly untracked because the broader BCU Control product is
part of this same authorized working tree. Do not create a misleading partial-file commit. Confirm:

```bash
git status --short -- Sources/BackgroundComputerUseControl/ControlViewModel.swift \
  Sources/BackgroundComputerUseControl/MenuBarController.swift \
  Sources/BackgroundComputerUseControl/BCUControlRuntime.swift \
  Tests/BackgroundComputerUseTests/ControlViewModelTests.swift
```

Expected: each path is `??`; commit them with the complete validated BCU parity change in Task 3.

---

### Task 3: Release and live macOS qualification

**Files:**
- Modify: `docs/superpowers/plans/2026-08-28-bcu-direct-quit-menu.md` (mark completed steps)

**Interfaces:**
- Consumes: the signed universal `BackgroundComputerUse.app` produced by `script/build_and_run.sh`.
- Produces: test, signature, visual menu, process-exit, and successful-relaunch evidence.

- [x] **Step 1: Run formatting and the full automated suite**

Run:

```bash
swiftformat --lint Sources/BackgroundComputerUseControl/ControlViewModel.swift \
  Sources/BackgroundComputerUseControl/MenuBarController.swift \
  Sources/BackgroundComputerUseControl/BCUControlRuntime.swift \
  Tests/BackgroundComputerUseTests/ControlViewModelTests.swift
swift test
python3 -m unittest script/test_smoke_control.py script/test_benchmark_mac_parity.py
```

Expected: formatter reports no changes required; Swift and Python suites pass.

- [x] **Step 2: Build and install the signed release**

Run:

```bash
BACKGROUND_COMPUTER_USE_RELEASE_BUILD=1 script/build_and_run.sh run
codesign --verify --deep --strict /Users/guilhermevarela/Applications/BackgroundComputerUse.app
file /Users/guilhermevarela/Applications/BackgroundComputerUse.app/Contents/MacOS/BackgroundComputerUse
```

Expected: signature verification succeeds and the executable contains `x86_64` and `arm64`.

- [x] **Step 3: Validate the real menu and direct quit lifecycle**

Use native macOS Computer Use to click the BCU status item, capture the visible menu, verify `Sair do BCU` appears below a separator with Command-Q, and click that item once. Then verify:

```bash
pgrep -f '/BackgroundComputerUse.app/Contents/MacOS/BackgroundComputerUse'
```

Expected after activation: no matching process remains. Relaunch with:

```bash
open /Users/guilhermevarela/Applications/BackgroundComputerUse.app
```

Then call `GET /health` and `GET /v1/bootstrap` through the manifest-aware BCU helper. Expected: health is `ok: true` and bootstrap is ready.

### Pre-ship review follow-up

The all-working-tree review found material fail-open, targeting, lifecycle, and authorization-plugin
risks outside the nominal quit path. The quit path itself matched the approved design. Resolve the
review findings before the final commit in three bounded batches:

- [x] **Batch A — Control and engine safety:** require Control for the signed server while preserving
  standalone-library behavior; inject router control policy in tests; require exact paste focus before
  touching the pasteboard; settle only on exact expected text; sample launch foreground after window
  polling; make renderer bootstrap worker startup non-blocking; restore the specified focused Unicode
  fallback when AX text operation is unavailable.
- [x] **Batch B — Locked Use trust and relock lifecycle:** validate armed leases against authenticated
  Control and root-configured Core identities; revoke pre-consume leases on physical input; make relock
  one-shot; acknowledge manual unlock; remove shields and end the locked session safely.
- [x] **Batch C — Plugin and recovery safety:** prevent the C authorization ABI from allowing after a
  concurrent deactivate; preserve the first valid authorization-rule backup across reinstall; add
  regression coverage for both paths.

- [x] **Step 4: Mark this plan complete and ship the authorized BCU parity branch**

Change every checkbox in this plan to `[x]`, review the complete working tree, commit every authorized
BCU source/test/script/doc change, and run no-mistakes with the user's complete intent before pushing
the branch to `fork`.

```bash
git add -A
git commit -m "feat: reach BCU macOS product parity"
no-mistakes axi run --intent "Complete the BCU macOS product-parity work, including a single transient two-second activity card, a Settings option that disables the card without disabling activity history, corrected card top spacing, and an always-enabled Sair do BCU Command-Q action that directly stops the session and cleanly quits the app without confirmation. Validate the signed universal release and publish the feature branch to the user's fork; Locked Use remains opt-in and its destructive qualification must stay off the primary Mac."
```
