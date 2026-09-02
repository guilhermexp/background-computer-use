import CryptoKit
import Darwin
import Foundation
import Security

public enum CodeSignatureIdentityError: Error, Equatable, Sendable {
    case invalidPID
    case codeLookupFailed(OSStatus)
    case invalidSignature(OSStatus)
    case staticCodeLookupFailed(OSStatus)
    case signingInformationFailed(OSStatus)
    case missingBundleID
    case missingTeamID
    case missingDesignatedRequirement
    case requirementStringFailed(OSStatus)
    case unsignedCode
    case invalidBundleURL
}

public protocol CodeSignatureIdentityResolving {
    func resolve(pid: pid_t) throws -> AppIdentity
}

public enum CodeSignatureSignerID {
    public static func resolve(
        teamID: String?,
        platformIdentifier: NSNumber?,
        certificateSHA256: String? = nil,
        cdhash: String? = nil
    ) throws -> String {
        if let teamID, teamID.isEmpty == false {
            return teamID
        }
        if let platformIdentifier, platformIdentifier.intValue > 0 {
            return "apple-platform:\(platformIdentifier.intValue)"
        }
        if let certificateSHA256, certificateSHA256.isEmpty == false {
            return "certificate-sha256:\(certificateSHA256.lowercased())"
        }
        // Ad-hoc signed code (dev Electron/Tauri builds, `codesign -s -`) has no signer at all.
        // The cdhash is the only stable identity left; it changes per build, so policy bound to
        // it never outlives the binary it was granted for.
        if let cdhash, cdhash.isEmpty == false {
            return "adhoc-cdhash:\(cdhash.lowercased())"
        }
        throw CodeSignatureIdentityError.missingTeamID
    }
}

public enum EmbeddedCoreIdentityPolicy {
    public static func accepts(control: AppIdentity, core: AppIdentity) -> Bool {
        control.bundleID == "xyz.dubdub.backgroundcomputeruse"
            && core.bundleID == BackgroundComputerUseCoreXPCService.bundleID
            && control.teamID == core.teamID
    }
}

public struct CodeSignatureIdentity: CodeSignatureIdentityResolving {
    public init() {}

    public func resolve(pid: pid_t) throws -> AppIdentity {
        guard pid > 0 else { throw CodeSignatureIdentityError.invalidPID }
        var code: SecCode?
        let lookup = SecCodeCopyGuestWithAttributes(
            nil,
            [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary,
            [],
            &code
        )
        guard lookup == errSecSuccess, let code else {
            if lookup == errSecCSUnsigned {
                throw CodeSignatureIdentityError.unsignedCode
            }
            throw CodeSignatureIdentityError.codeLookupFailed(lookup)
        }

        let validity = SecCodeCheckValidity(code, SecCSFlags(rawValue: UInt32(kSecCSStrictValidate)), nil)
        guard validity == errSecSuccess else {
            if validity == errSecCSUnsigned {
                throw CodeSignatureIdentityError.unsignedCode
            }
            throw CodeSignatureIdentityError.invalidSignature(validity)
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw CodeSignatureIdentityError.staticCodeLookupFailed(staticStatus)
        }
        return try identity(from: staticCode)
    }

    public func resolve(url: URL) throws -> AppIdentity {
        guard url.isFileURL, ["app", "xpc"].contains(url.pathExtension.lowercased()) else {
            throw CodeSignatureIdentityError.invalidBundleURL
        }
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            if createStatus == errSecCSUnsigned {
                throw CodeSignatureIdentityError.unsignedCode
            }
            throw CodeSignatureIdentityError.staticCodeLookupFailed(createStatus)
        }
        let validity = SecStaticCodeCheckValidity(
            staticCode,
            SecCSFlags(rawValue: UInt32(kSecCSStrictValidate)),
            nil
        )
        guard validity == errSecSuccess else {
            if validity == errSecCSUnsigned {
                throw CodeSignatureIdentityError.unsignedCode
            }
            throw CodeSignatureIdentityError.invalidSignature(validity)
        }
        return try identity(from: staticCode)
    }

    private func identity(from staticCode: SecStaticCode) throws -> AppIdentity {
        var rawInformation: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)),
            &rawInformation
        )
        guard informationStatus == errSecSuccess,
              let information = rawInformation as? [String: Any]
        else {
            throw CodeSignatureIdentityError.signingInformationFailed(informationStatus)
        }
        guard let bundleID = information[kSecCodeInfoIdentifier as String] as? String,
              bundleID.isEmpty == false
        else {
            throw CodeSignatureIdentityError.missingBundleID
        }
        let teamID = try CodeSignatureSignerID.resolve(
            teamID: information[kSecCodeInfoTeamIdentifier as String] as? String,
            platformIdentifier: information[kSecCodeInfoPlatformIdentifier as String] as? NSNumber,
            certificateSHA256: certificateDigest(from: information),
            cdhash: (information[kSecCodeInfoUnique as String] as? Data)?
                .map { String(format: "%02x", $0) }
                .joined()
        )
        var requirement: SecRequirement?
        let designatedStatus = SecCodeCopyDesignatedRequirement(staticCode, [], &requirement)
        guard designatedStatus == errSecSuccess, let requirement else {
            if designatedStatus == errSecCSUnsigned {
                throw CodeSignatureIdentityError.unsignedCode
            }
            throw CodeSignatureIdentityError.missingDesignatedRequirement
        }
        var rawRequirement: CFString?
        let requirementStatus = SecRequirementCopyString(requirement, [], &rawRequirement)
        guard requirementStatus == errSecSuccess, let rawRequirement else {
            throw CodeSignatureIdentityError.requirementStringFailed(requirementStatus)
        }
        return AppIdentity(
            bundleID: bundleID,
            teamID: teamID,
            designatedRequirement: rawRequirement as String
        )
    }

    private func certificateDigest(from information: [String: Any]) -> String? {
        guard let certificates = information[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let root = certificates.last
        else {
            return nil
        }
        return SHA256.hash(data: SecCertificateCopyData(root) as Data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
