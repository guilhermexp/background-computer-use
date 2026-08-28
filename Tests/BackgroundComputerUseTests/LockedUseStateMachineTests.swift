@testable import BackgroundComputerUseLockedShared
import Foundation
import Testing

struct LockedUseStateMachineTests {
    @Test
    func validLeaseFlowReachesShieldedActivity() throws {
        var machine = LockedUseStateMachine()
        try machine.handle(.enable)
        try machine.handle(.lockObserved)
        try machine.handle(.leasePresented)
        try machine.handle(.unlockAllowed)

        #expect(machine.state == .shieldedActive)
        #expect(machine.manualUnlockRequired == false)
    }

    @Test
    func localInputRelocksAndRequiresManualUnlock() throws {
        var machine = LockedUseStateMachine(state: .shieldedActive)
        try machine.handle(.localInput)
        #expect(machine.state == .relocking)
        #expect(machine.manualUnlockRequired)
        try machine.handle(.relocked)
        #expect(machine.state == .armed)
        #expect(throws: LockedUseTransitionError.manualUnlockRequired) {
            try machine.handle(.leasePresented)
        }
        try machine.handle(.manualUnlockObserved)
        #expect(machine.manualUnlockRequired == false)
    }

    @Test
    func physicalInputBeforeLeasePresentationAlsoRequiresManualUnlock() throws {
        for initialState in [LockedUseState.armed, .locked] {
            var machine = LockedUseStateMachine(state: initialState)

            try machine.handle(.localInput)

            #expect(machine.state == .relocking)
            #expect(machine.manualUnlockRequired)
        }
    }

    @Test
    func dependencyLossAndExpiryAlwaysRelock() throws {
        for event in [LockedUseEvent.leaseExpired, .dependencyLost] {
            var machine = LockedUseStateMachine(state: .shieldedActive)
            try machine.handle(event)
            #expect(machine.state == .relocking)
        }
    }

    @Test
    func transientRelockFailureReturnsToARetryableState() throws {
        var machine = LockedUseStateMachine(state: .shieldedActive)
        try machine.handle(.dependencyLost)
        try machine.handle(.relockFailed)

        #expect(machine.state == .armed)
    }

    @Test
    func invalidOrderingFailsClosed() {
        var machine = LockedUseStateMachine()
        #expect(throws: LockedUseTransitionError.invalidTransition) {
            try machine.handle(.unlockAllowed)
        }
        #expect(machine.state == .disabled)
    }

    @Test
    func ruleInsertionPreservesCodexMechanismAndUnknownFields() throws {
        let original: [String: Any] = [
            "class": "evaluate-mechanisms",
            "comment": "fixture",
            "unknown": ["future": true],
            "mechanisms": [
                "builtin:authenticate,privileged",
                "com.openai.sky.CUAService.AuthorizationPlugin.remote",
                "use-login-window-ui",
            ],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: original,
            format: .xml,
            options: 0
        )
        let snapshot = try AuthorizationRuleSnapshot(data: data)
        let updated = try snapshot.inserting(
            mechanism: "xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin:remote"
        )
        let decoded = try #require(
            PropertyListSerialization.propertyList(from: updated, options: [], format: nil) as? [String: Any]
        )
        let mechanisms = try #require(decoded["mechanisms"] as? [String])
        #expect(mechanisms == [
            "builtin:authenticate,privileged",
            "com.openai.sky.CUAService.AuthorizationPlugin.remote",
            "xyz.dubdub.backgroundcomputeruse.AuthorizationPlugin:remote",
            "use-login-window-ui",
        ])
        #expect((decoded["unknown"] as? [String: Bool])?["future"] == true)
        #expect(try snapshot.isSemanticallyEqualToOriginal(snapshot.restoreData()))
    }
}
