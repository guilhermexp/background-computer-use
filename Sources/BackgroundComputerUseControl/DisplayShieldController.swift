import AppKit
import CoreGraphics
import Foundation

public final class DisplayShieldController: LockedUseShielding, @unchecked Sendable {
    private var panels: [UInt32: NSPanel] = [:]

    public init() {}

    public func activeDisplayIDs() -> Set<UInt32> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Set(displays.prefix(Int(count)))
    }

    public func installShields() -> Set<UInt32> {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { installOnMain() }
        }
        return DispatchQueue.main.sync { @MainActor in installOnMain() }
    }

    public func removeShields() {
        let work = { @MainActor in
            for panel in self.panels.values {
                panel.orderOut(nil)
            }
            self.panels.removeAll()
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.sync { @MainActor in work() }
        }
    }

    @MainActor
    private func installOnMain() -> Set<UInt32> {
        removeShields()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = number.uint32Value
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.backgroundColor = .black
            panel.isOpaque = true
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            panels[displayID] = panel
        }
        return Set(panels.keys)
    }
}
