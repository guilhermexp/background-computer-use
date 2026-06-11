import Testing
@testable import BackgroundComputerUse

@Suite
struct ClickDialogEffectVerifierTests {
    @Test
    func modalDialogOpenedWhenNewDialogLikeProbeAppears() {
        let before = [
            ClickDialogEffectProbe(
                roleSignals: ["button"],
                signatureSignals: ["button", "View"]
            ),
        ]
        let after = before + [
            ClickDialogEffectProbe(
                roleSignals: ["dialog"],
                signatureSignals: ["dialog", "Deployment", "120,80,720,540"]
            ),
        ]

        #expect(ClickDialogEffectVerifier.modalDialogOpened(before: before, after: after))
    }

    @Test
    func modalDialogDoesNotOpenWhenOnlyExistingDialogRemains() {
        let dialog = ClickDialogEffectProbe(
            roleSignals: ["dialog"],
            signatureSignals: ["dialog", "Deployment", "120,80,720,540"]
        )

        #expect(ClickDialogEffectVerifier.modalDialogOpened(before: [dialog], after: [dialog]) == false)
    }

    @Test
    func modalFlagCanIdentifyWebModalWithoutDialogRole() {
        let before = [
            ClickDialogEffectProbe(
                roleSignals: ["group"],
                signatureSignals: ["group", "View"]
            ),
        ]
        let after = before + [
            ClickDialogEffectProbe(
                roleSignals: ["group"],
                signatureSignals: ["group", "Deployment", "120,80,720,540"],
                metadataSignals: ["aria-modal"]
            ),
        ]

        #expect(ClickDialogEffectVerifier.modalDialogOpened(before: before, after: after))
    }
}
