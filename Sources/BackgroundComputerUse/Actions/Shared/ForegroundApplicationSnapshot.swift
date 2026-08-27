import AppKit
import Foundation

struct ForegroundApplicationSnapshot: Equatable, Sendable {
    let pid: Int32
    let bundleID: String?

    static func capture() -> ForegroundApplicationSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return ForegroundApplicationSnapshot(
            pid: app.processIdentifier,
            bundleID: app.bundleIdentifier
        )
    }
}

enum TypeTextBackgroundSafety {
    static func evaluate(
        before: ForegroundApplicationSnapshot?,
        beforeDispatch: ForegroundApplicationSnapshot?,
        after: ForegroundApplicationSnapshot?
    ) -> TypeTextBackgroundSafetyDTO {
        let preserved = before != nil && before == beforeDispatch && beforeDispatch == after
        return TypeTextBackgroundSafetyDTO(
            frontmostPIDBefore: before?.pid,
            frontmostBundleBefore: before?.bundleID,
            frontmostPIDBeforeDispatch: beforeDispatch?.pid,
            frontmostBundleBeforeDispatch: beforeDispatch?.bundleID,
            frontmostPIDAfter: after?.pid,
            frontmostBundleAfter: after?.bundleID,
            foregroundPreserved: preserved
        )
    }
}
