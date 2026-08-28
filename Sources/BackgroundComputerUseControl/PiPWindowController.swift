import AppKit
import SwiftUI

@MainActor
final class ActivityPiPModel: ObservableObject {
    @Published var activity: ActivityEnvelope

    init(activity: ActivityEnvelope) {
        self.activity = activity
    }
}

struct ActivityPiPPresentationState {
    private(set) var activity: ActivityEnvelope?
    private(set) var isEnabled: Bool
    private var generation: UInt64 = 0

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    mutating func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        generation += 1
        isEnabled = enabled
        if enabled == false {
            activity = nil
        }
    }

    mutating func present(_ activity: ActivityEnvelope) -> UInt64? {
        guard isEnabled else { return nil }
        generation += 1
        self.activity = activity
        return generation
    }

    mutating func dismiss(generation candidate: UInt64) -> Bool {
        guard candidate == generation else { return false }
        activity = nil
        return true
    }
}

private struct ActivityPiPView: View {
    @ObservedObject var model: ActivityPiPModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: model.activity.verdict == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(model.activity.action.replacingOccurrences(of: "_", with: " "))
                    .font(.headline)
                Spacer()
                Text(model.activity.verdict)
                    .font(.caption.bold())
            }
            Text(model.activity.summary)
                .font(.callout)
                .lineLimit(3)
            if let app = model.activity.appBundleID {
                Text(app)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let path = model.activity.screenshotPath,
               let image = NSImage(contentsOfFile: path)
            {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(width: 330, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.activity.action), \(model.activity.verdict), \(model.activity.summary)")
    }
}

@MainActor
final class PiPWindowController {
    private struct Entry {
        let panel: NSPanel
        let model: ActivityPiPModel
    }

    private var entry: Entry?
    private var presentation: ActivityPiPPresentationState
    private var dismissWorkItem: DispatchWorkItem?
    private let displayDuration: TimeInterval

    init(isEnabled: Bool = true, displayDuration: TimeInterval = 2) {
        presentation = ActivityPiPPresentationState(isEnabled: isEnabled)
        self.displayDuration = displayDuration
    }

    func setEnabled(_ enabled: Bool) {
        presentation.setEnabled(enabled)
        guard enabled == false else { return }
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        entry?.panel.orderOut(nil)
    }

    func update(_ activity: ActivityEnvelope) {
        guard let generation = presentation.present(activity) else { return }
        if let entry {
            entry.model.activity = activity
            entry.panel.setContentSize(NSSize(
                width: 330,
                height: activity.screenshotPath == nil ? 120 : 240
            ))
            repositionPanel()
            entry.panel.orderFrontRegardless()
            scheduleDismissal(generation: generation)
            return
        }
        let model = ActivityPiPModel(activity: activity)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 130),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentViewController = NSHostingController(rootView: ActivityPiPView(model: model))
        panel.setContentSize(NSSize(
            width: 330,
            height: activity.screenshotPath == nil ? 120 : 240
        ))
        panel.contentView?.layoutSubtreeIfNeeded()
        entry = Entry(panel: panel, model: model)
        repositionPanel()
        panel.orderFrontRegardless()
        scheduleDismissal(generation: generation)
    }

    private func scheduleDismissal(generation: UInt64) {
        dismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.presentation.dismiss(generation: generation)
                else {
                    return
                }
                self.entry?.panel.orderOut(nil)
            }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + displayDuration,
            execute: workItem
        )
    }

    private func repositionPanel() {
        guard let panel = entry?.panel,
              let frame = NSScreen.main?.visibleFrame
        else {
            return
        }
        let origin = NSPoint(
            x: max(frame.minX, frame.maxX - panel.frame.width - 18),
            y: max(frame.minY, frame.maxY - panel.frame.height - 18)
        )
        panel.setFrameOrigin(origin)
    }
}
