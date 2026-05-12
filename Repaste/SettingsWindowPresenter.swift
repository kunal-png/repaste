import AppKit
import SwiftUI

/// Menu-bar (`LSUIElement`) apps often get a no-op from SwiftUI `openSettings()`. An `NSPanel` works.
@MainActor
enum SettingsWindowPresenter {
    private static var panel: NSPanel?
    private static var closeDelegate: SettingsCloseDelegate?

    static func present(model: AppModel) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(model)
            .frame(minWidth: 460, minHeight: 640)

        let host = NSHostingController(rootView: root)
        host.title = "Repaste Settings"

        let rect = NSRect(x: 0, y: 0, width: 480, height: 700)
        let p = NSPanel(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = "Repaste Settings"
        p.isReleasedWhenClosed = false
        p.level = .normal
        p.contentViewController = host
        p.setContentSize(rect.size)
        p.center()

        let del = SettingsCloseDelegate {
            closeDelegate = nil
            panel = nil
            NSApp.setActivationPolicy(.accessory)
        }
        p.delegate = del
        closeDelegate = del

        panel = p
        p.makeKeyAndOrderFront(nil)
    }
}

private final class SettingsCloseDelegate: NSObject, NSWindowDelegate {
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
