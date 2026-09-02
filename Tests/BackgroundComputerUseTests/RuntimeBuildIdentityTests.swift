import Testing
@testable import BackgroundComputerUse

struct RuntimeBuildIdentityTests {
    @Test
    func loadsCleanBuildIdentityFromInjectedInfo() {
        let identity = RuntimeBuildIdentity.load(from: [
            "BCUBuildIdentity": "abc123-clean:digest",
            "BCUBuildCommit": "abc123",
            "BCUBuildDirty": false,
            "BCUSourcesSHA256": "digest",
        ])

        #expect(identity.identity == "abc123-clean:digest")
        #expect(identity.commit == "abc123")
        #expect(identity.dirty == false)
        #expect(identity.sourcesSHA256 == "digest")
    }

    @Test
    func loadsDirtyBuildIdentityFromInjectedInfo() {
        let identity = RuntimeBuildIdentity.load(from: [
            "BCUBuildIdentity": "abc123-dirty:digest",
            "BCUBuildCommit": "abc123",
            "BCUBuildDirty": true,
            "BCUSourcesSHA256": "digest",
        ])

        #expect(identity.identity == "abc123-dirty:digest")
        #expect(identity.commit == "abc123")
        #expect(identity.dirty)
        #expect(identity.sourcesSHA256 == "digest")
    }

    @Test
    func missingBuildMetadataUsesExplicitDevelopmentFallback() {
        let identity = RuntimeBuildIdentity.load(from: [:])

        #expect(identity.identity == "development-unknown")
        #expect(identity.commit == "unknown")
        #expect(identity.dirty)
        #expect(identity.sourcesSHA256 == "unknown")
    }
}
