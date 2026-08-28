import Foundation
import Security

public enum LockedUseLeaseError: Error, Equatable, Sendable {
    case invalidVersion
    case invalidLifetime
    case randomGenerationFailed(OSStatus)
    case duplicateNonce
    case unknownNonce
    case replayed
    case expired
    case uidMismatch
    case bootSessionMismatch
    case taskSessionMismatch
    case coreSignerMismatch
    case controlSignerMismatch
    case notOneUse
    case revoked
}

public struct LockedUseLease: Codable, Equatable, Sendable {
    public let version: Int
    public let taskSessionID: String
    public let uid: UInt32
    public let bootSessionID: String
    public let nonce: Data
    public let issuedAt: Date
    public let expiresAt: Date
    public let coreDesignatedRequirement: String
    public let controlDesignatedRequirement: String
    public let oneUse: Bool

    public static func issue(
        taskSessionID: String,
        uid: UInt32,
        bootSessionID: String,
        issuedAt: Date,
        expiresAt: Date,
        coreDesignatedRequirement: String,
        controlDesignatedRequirement: String
    ) throws -> LockedUseLease {
        let lifetime = expiresAt.timeIntervalSince(issuedAt)
        guard lifetime > 0, lifetime <= 60 else {
            throw LockedUseLeaseError.invalidLifetime
        }
        var nonce = Data(count: 32)
        let status = nonce.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw LockedUseLeaseError.randomGenerationFailed(status)
        }
        return LockedUseLease(
            version: 1,
            taskSessionID: taskSessionID,
            uid: uid,
            bootSessionID: bootSessionID,
            nonce: nonce,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            coreDesignatedRequirement: coreDesignatedRequirement,
            controlDesignatedRequirement: controlDesignatedRequirement,
            oneUse: true
        )
    }
}

public struct LockedUseConsumptionContext: Sendable {
    public let uid: UInt32
    public let bootSessionID: String
    public let taskSessionID: String
    public let coreDesignatedRequirement: String
    public let controlDesignatedRequirement: String
    public let now: Date

    public init(
        uid: UInt32,
        bootSessionID: String,
        taskSessionID: String,
        coreDesignatedRequirement: String,
        controlDesignatedRequirement: String,
        now: Date
    ) {
        self.uid = uid
        self.bootSessionID = bootSessionID
        self.taskSessionID = taskSessionID
        self.coreDesignatedRequirement = coreDesignatedRequirement
        self.controlDesignatedRequirement = controlDesignatedRequirement
        self.now = now
    }
}
