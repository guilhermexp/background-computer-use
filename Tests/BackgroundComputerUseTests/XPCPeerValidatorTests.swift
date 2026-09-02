@testable import BackgroundComputerUseControlShared
import Foundation
import Testing

struct XPCPeerValidatorTests {
    private let trusted = AppIdentity(
        bundleID: "xyz.dubdub.backgroundcomputeruse.control",
        teamID: "TEAM123",
        designatedRequirement: "identifier \"xyz.dubdub.backgroundcomputeruse.control\" and certificate leaf[subject.OU] = \"TEAM123\""
    )

    @Test
    func exactTeamBundleAndRequirementAreAccepted() throws {
        let validator = XPCPeerValidator(resolver: StubIdentityResolver(result: .success(trusted)))

        let resolved = try validator.validate(
            pid: 42,
            requiredBundleID: trusted.bundleID,
            requiredTeamID: trusted.teamID,
            requiredDesignatedRequirement: trusted.designatedRequirement
        )
        #expect(resolved == trusted)
    }

    @Test
    func bundleSpoofAndRequirementMismatchAreRejected() {
        let spoof = AppIdentity(
            bundleID: trusted.bundleID,
            teamID: "ATTACKER",
            designatedRequirement: trusted.designatedRequirement
        )
        let validator = XPCPeerValidator(resolver: StubIdentityResolver(result: .success(spoof)))

        #expect(throws: XPCPeerValidationError.teamMismatch) {
            _ = try validator.validate(
                pid: 42,
                requiredBundleID: trusted.bundleID,
                requiredTeamID: trusted.teamID,
                requiredDesignatedRequirement: trusted.designatedRequirement
            )
        }
    }

    @Test
    func missingSignatureFailsClosed() {
        let validator = XPCPeerValidator(
            resolver: StubIdentityResolver(result: .failure(CodeSignatureIdentityError.unsignedCode))
        )

        #expect(throws: CodeSignatureIdentityError.unsignedCode) {
            _ = try validator.validate(
                pid: 42,
                requiredBundleID: trusted.bundleID,
                requiredTeamID: trusted.teamID,
                requiredDesignatedRequirement: trusted.designatedRequirement
            )
        }
    }

    @Test
    func applePlatformIdentityHasStableSignerNamespaceWithoutTeamID() throws {
        #expect(try CodeSignatureSignerID.resolve(teamID: nil, platformIdentifier: 1) == "apple-platform:1")
        #expect(
            try CodeSignatureSignerID.resolve(
                teamID: nil,
                platformIdentifier: nil,
                certificateSHA256: "abc123"
            ) == "certificate-sha256:abc123"
        )
        #expect(
            try CodeSignatureSignerID.resolve(
                teamID: nil,
                platformIdentifier: nil,
                certificateSHA256: nil,
                cdhash: "36E04F99"
            ) == "adhoc-cdhash:36e04f99"
        )
        #expect(throws: CodeSignatureIdentityError.missingTeamID) {
            _ = try CodeSignatureSignerID.resolve(teamID: nil, platformIdentifier: nil)
        }
    }

    @Test
    func embeddedCoreRequiresExactBundleAndSameSignerAsControl() {
        let control = AppIdentity(
            bundleID: "xyz.dubdub.backgroundcomputeruse",
            teamID: "TEAM123",
            designatedRequirement: "control"
        )
        let core = AppIdentity(
            bundleID: BackgroundComputerUseCoreXPCService.bundleID,
            teamID: "TEAM123",
            designatedRequirement: "core"
        )
        #expect(EmbeddedCoreIdentityPolicy.accepts(control: control, core: core))
        #expect(EmbeddedCoreIdentityPolicy.accepts(
            control: control,
            core: AppIdentity(
                bundleID: core.bundleID,
                teamID: "ATTACKER",
                designatedRequirement: core.designatedRequirement
            )
        ) == false)
    }
}

private struct StubIdentityResolver: CodeSignatureIdentityResolving {
    let result: Result<AppIdentity, Error>

    func resolve(pid _: pid_t) throws -> AppIdentity {
        try result.get()
    }
}
