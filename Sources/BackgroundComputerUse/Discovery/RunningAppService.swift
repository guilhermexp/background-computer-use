import AppKit
import Foundation

struct RunningAppService {
    func listApps() -> ListAppsResponse {
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let apps = targetableApps(frontmostBundleID: frontmostBundleID)

        return ListAppsResponse(
            contractVersion: ContractVersion.current,
            frontmostApp: snapshot(NSWorkspace.shared.frontmostApplication, frontmostBundleID: frontmostBundleID),
            runningApps: apps.compactMap { snapshot($0, frontmostBundleID: frontmostBundleID) },
            notes: []
        )
    }

    func targetableApps() -> [NSRunningApplication] {
        targetableApps(frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    func resolveApp(pid: pid_t) -> NSRunningApplication? {
        Self.exactPIDMatch(pid, in: targetableApps(), processIdentifier: \.processIdentifier)
    }

    static func exactPIDMatch<Candidate>(
        _ pid: pid_t,
        in candidates: [Candidate],
        processIdentifier: (Candidate) -> pid_t
    ) -> Candidate? {
        guard pid > 0 else { return nil }
        return candidates.first { processIdentifier($0) == pid }
    }

    private func targetableApps(frontmostBundleID: String?) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter(isTargetable)
            .sorted { lhs, rhs in
                sort(lhs: lhs, rhs: rhs, frontmostBundleID: frontmostBundleID)
            }
    }

    private func snapshot(_ app: NSRunningApplication?, frontmostBundleID: String?) -> RunningAppDTO? {
        guard let app,
              let bundleID = app.bundleIdentifier,
              let name = app.localizedName,
              name.isEmpty == false else {
            return nil
        }

        return RunningAppDTO(
            name: name,
            bundleID: bundleID,
            pid: app.processIdentifier,
            launchDate: app.launchDate.map(Time.iso8601String),
            activationPolicy: activationPolicyName(app.activationPolicy),
            isActive: app.isActive,
            isHidden: app.isHidden,
            isFrontmost: bundleID == frontmostBundleID,
            onscreenWindowCount: CGWindowInventory.windows(for: app.processIdentifier, onScreenOnly: true).count
        )
    }

    private func activationPolicyName(_ policy: NSApplication.ActivationPolicy) -> String {
        switch policy {
        case .regular:
            return "regular"
        case .accessory:
            return "accessory"
        case .prohibited:
            return "prohibited"
        @unknown default:
            return "unknown"
        }
    }

    private func isTargetable(_ app: NSRunningApplication) -> Bool {
        guard app.isTerminated == false, app.activationPolicy == .regular else {
            return false
        }

        let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleID = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty == false && bundleID.isEmpty == false
    }

    private func sort(lhs: NSRunningApplication, rhs: NSRunningApplication, frontmostBundleID: String?) -> Bool {
        let lhsFrontmost = lhs.bundleIdentifier == frontmostBundleID
        let rhsFrontmost = rhs.bundleIdentifier == frontmostBundleID
        if lhsFrontmost != rhsFrontmost {
            return lhsFrontmost && rhsFrontmost == false
        }

        let lhsName = lhs.localizedName ?? lhs.bundleIdentifier ?? ""
        let rhsName = rhs.localizedName ?? rhs.bundleIdentifier ?? ""
        return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
    }
}
