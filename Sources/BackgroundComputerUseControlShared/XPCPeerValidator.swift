import Darwin
import Foundation

public enum XPCPeerValidationError: Error, Equatable, Sendable {
    case bundleMismatch
    case teamMismatch
    case designatedRequirementMismatch
}

public struct XPCPeerValidator {
    private let resolver: any CodeSignatureIdentityResolving

    public init(resolver: any CodeSignatureIdentityResolving = CodeSignatureIdentity()) {
        self.resolver = resolver
    }

    @discardableResult
    public func validate(
        pid: pid_t,
        requiredBundleID: String,
        requiredTeamID: String,
        requiredDesignatedRequirement: String
    ) throws -> AppIdentity {
        let identity = try resolver.resolve(pid: pid)
        guard identity.bundleID == requiredBundleID else {
            throw XPCPeerValidationError.bundleMismatch
        }
        guard identity.teamID == requiredTeamID else {
            throw XPCPeerValidationError.teamMismatch
        }
        guard identity.designatedRequirement == requiredDesignatedRequirement else {
            throw XPCPeerValidationError.designatedRequirementMismatch
        }
        return identity
    }

    @discardableResult
    public func validate(
        auditToken: audit_token_t,
        requiredBundleID: String,
        requiredTeamID: String,
        requiredDesignatedRequirement: String
    ) throws -> AppIdentity {
        var auditToken = auditToken
        let pid = withUnsafeBytes(of: &auditToken) { bytes in
            pid_t(bytes.loadUnaligned(fromByteOffset: 5 * MemoryLayout<UInt32>.size, as: UInt32.self))
        }
        return try validate(
            pid: pid,
            requiredBundleID: requiredBundleID,
            requiredTeamID: requiredTeamID,
            requiredDesignatedRequirement: requiredDesignatedRequirement
        )
    }
}
