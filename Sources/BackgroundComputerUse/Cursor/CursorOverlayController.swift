import AppKit

struct CursorOverlayPresentation {
    let attachedWindowNumber: Int?
    let attachedWindowLevelRawValue: Int
    let snapshot: CursorSnapshot
}

@MainActor
final class CursorOverlayController {
    private(set) var screen: NSScreen
    let window: NSWindow
    let overlayView: CursorOverlaySurfaceView

    init(screen: NSScreen) {
        self.screen = screen
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayView = CursorOverlaySurfaceView(frame: NSRect(origin: .zero, size: screen.frame.size))

        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .normal
        window.collectionBehavior = [.stationary, .ignoresCycle, .transient]

        overlayView.autoresizingMask = [.width, .height]
        window.contentView = overlayView
    }

    func updateScreen(_ screen: NSScreen) {
        self.screen = screen
        window.setFrame(screen.frame, display: true)
        overlayView.frame = NSRect(origin: .zero, size: screen.frame.size)
    }

    func setPresentation(_ presentation: CursorOverlayPresentation?) {
        overlayView.presentation = presentation
        guard let presentation else {
            window.orderOut(nil)
            return
        }

        guard presentation.attachedWindowNumber != nil else {
            window.orderOut(nil)
            return
        }

        // `order(.above, relativeTo:)` only orders against windows of this app, so
        // pointing it at another application's window number silently promoted the
        // overlay above everything — that is how the agent cursor ended up painted
        // over apps it was not driving, on displays the driven window was not on.
        // The overlay is a floating layer so a background runtime can still show it
        // above the active app; *whether* it is shown is decided by
        // CursorWindowExposure, which only presents while the driven window is the
        // window visible under the cursor.
        window.level = .floating
        window.orderFront(nil)
    }

    func teardown() {
        window.orderOut(nil)
    }
}

@MainActor
final class CursorOverlaySurfaceView: NSView {
    var presentation: CursorOverlayPresentation? {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let presentation,
              let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let localSnapshot = presentation.snapshot.mapGeometry(localPointOrFallback(fromScreenPoint:))
        context.saveGState()
        context.clear(bounds)
        CursorRenderer.draw(localSnapshot, in: context)
        context.restoreGState()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func localPoint(fromScreenPoint point: CGPoint) -> CGPoint? {
        guard let window else { return nil }
        let windowPoint = window.convertPoint(fromScreen: point)
        return convert(windowPoint, from: nil)
    }

    private func localPointOrFallback(fromScreenPoint point: CGPoint) -> CGPoint {
        localPoint(fromScreenPoint: point) ?? CGPoint(
            x: point.x - (window?.frame.minX ?? 0),
            y: point.y - (window?.frame.minY ?? 0)
        )
    }
}
