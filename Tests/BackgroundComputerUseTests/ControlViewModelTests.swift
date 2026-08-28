import AppKit
@testable import BackgroundComputerUseControl
import BackgroundComputerUseControlShared
import Foundation
import Testing

struct ControlViewModelTests {
    private func request(_ suffix: String) -> ApprovalRequest {
        ApprovalRequest(
            id: suffix,
            identity: AppIdentity(
                bundleID: "com.example.\(suffix)",
                teamID: "TEAM123",
                designatedRequirement: "requirement-\(suffix)"
            ),
            pid: 100,
            sessionID: "session",
            operation: "Launch and control in background"
        )
    }

    @Test
    func approvalQueueExposesOneActiveRequestInOrder() {
        let queue = ApprovalQueue()
        queue.enqueue(request("one"))
        queue.enqueue(request("two"))

        #expect(queue.active?.id == "one")
        #expect(queue.pendingCount == 1)
        queue.resolveActive(.allowOnce)
        #expect(queue.active?.id == "two")
        #expect(queue.decision(for: "one") == .allowOnce)
    }

    @Test
    func dismissalTimeoutAndInvalidChoiceDeny() {
        #expect(ApprovalDecisionPolicy.sanitize(nil, timedOut: false) == .deny)
        #expect(ApprovalDecisionPolicy.sanitize(.ask, timedOut: false) == .deny)
        #expect(ApprovalDecisionPolicy.sanitize(.alwaysAllow, timedOut: true) == .deny)
        #expect(ApprovalDecisionPolicy.sanitize(.alwaysAllow, timedOut: false) == .alwaysAllow)
    }

    @Test
    func approvalCopyIncludesVerifiedSignerAndScope() {
        let copy = ApprovalPresentationCopy.make(for: request("editor"))
        #expect(copy.accessibilityLabel.contains("com.example.editor"))
        #expect(copy.accessibilityLabel.contains("TEAM123"))
        #expect(copy.accessibilityLabel.contains("Launch and control in background"))
        #expect(copy.allowOnceLabel.isEmpty == false)
        #expect(copy.alwaysAllowLabel.isEmpty == false)
        #expect(copy.denyLabel.isEmpty == false)
    }

    @Test @MainActor
    func lockedUsePreferenceIsExplicitAndCallbackDriven() throws {
        var values: [Bool] = []
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try ControlViewModel(
            store: AppPolicyStore(fileURL: file),
            lockedUseOptIn: false,
            onLockedUsePreferenceChanged: { values.append($0) }
        )
        model.setLockedUseOptIn(true)

        #expect(model.lockedUseOptIn)
        #expect(values == [true])
    }

    @Test
    func missingActivityCardPreferenceDefaultsToEnabledWhilePersistedFalseSurvives() throws {
        let suiteName = "BCUActivityCardPreferenceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(ActivityCardPreference.isEnabled(in: defaults))
        defaults.set(false, forKey: "BCUActivityCardEnabled")
        #expect(ActivityCardPreference.isEnabled(in: defaults) == false)
    }

    @Test @MainActor
    func activityCardPreferenceUpdatesModelAndCallback() throws {
        var values: [Bool] = []
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try ControlViewModel(
            store: AppPolicyStore(fileURL: file),
            activityCardEnabled: false,
            onActivityCardPreferenceChanged: { values.append($0) }
        )

        model.setActivityCardEnabled(true)

        #expect(model.activityCardEnabled)
        #expect(values == [true])
    }

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
        #expect(try NSApplication.shared.sendAction(#require(item.action), to: item.target, from: item))
        #expect(didRequestQuit)
    }

    @Test
    func permissionLinksTargetTheTwoRequiredPrivacyPanes() throws {
        let accessibility = try #require(ControlPermissionPane.accessibility.settingsURL)
        let screenRecording = try #require(ControlPermissionPane.screenRecording.settingsURL)
        #expect(accessibility.absoluteString.contains("Privacy_Accessibility"))
        #expect(screenRecording.absoluteString.contains("Privacy_ScreenCapture"))
        #expect(ControlPermissionSnapshot(
            accessibilityGranted: true,
            screenRecordingGranted: false
        ).ready == false)
    }
}
