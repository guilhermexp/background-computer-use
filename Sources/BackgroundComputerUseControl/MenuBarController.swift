import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let model: ControlViewModel
    private var settingsWindow: NSWindow?

    init(model: ControlViewModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "BCU Control")
        statusItem.button?.toolTip = "BCU Control"
        rebuildMenu()
    }

    func rebuildMenu() {
        statusItem.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let status = NSMenuItem(title: model.isStopped ? "Sessão encerrada" : (model.isPaused ? "Pausado" : "BCU ativo"), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let pause = NSMenuItem(
            title: model.isPaused ? "Retomar" : "Pausar",
            action: #selector(togglePause),
            keyEquivalent: "p"
        )
        pause.target = self
        pause.isEnabled = model.isStopped == false
        menu.addItem(pause)
        let stop = NSMenuItem(title: "Parar sessão", action: #selector(stopSession), keyEquivalent: ".")
        stop.target = self
        stop.isEnabled = model.isStopped == false
        menu.addItem(stop)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Sair do BCU", action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return menu
    }

    @objc private func togglePause() {
        model.togglePause()
        rebuildMenu()
    }

    @objc private func stopSession() {
        model.stop()
        rebuildMenu()
    }

    @objc private func quitApplication() {
        model.quit()
    }

    @objc private func openSettings() {
        model.refreshPolicies()
        model.refreshPermissions()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let window = NSWindow(contentViewController: controller)
            window.title = "BCU Control"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
