import ApplicationServices
import CoreGraphics
import Foundation

public struct ControlPermissionSnapshot: Equatable, Sendable {
    public let accessibilityGranted: Bool
    public let screenRecordingGranted: Bool

    public init(accessibilityGranted: Bool, screenRecordingGranted: Bool) {
        self.accessibilityGranted = accessibilityGranted
        self.screenRecordingGranted = screenRecordingGranted
    }

    public var ready: Bool {
        accessibilityGranted && screenRecordingGranted
    }

    public static func current() -> ControlPermissionSnapshot {
        ControlPermissionSnapshot(
            accessibilityGranted: AXIsProcessTrusted(),
            screenRecordingGranted: CGPreflightScreenCaptureAccess()
        )
    }
}

public enum ControlPermissionPane: String, CaseIterable, Sendable {
    case accessibility
    case screenRecording

    public var title: String {
        switch self {
        case .accessibility: "Acessibilidade"
        case .screenRecording: "Gravação da Tela"
        }
    }

    public var settingsURL: URL? {
        let anchor = switch self {
        case .accessibility: "Privacy_Accessibility"
        case .screenRecording: "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
}
