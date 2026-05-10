import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    let store = ClipboardHistoryStore()
    let updateChecker = UpdateChecker()
    private let monitor: PasteboardMonitor
    private let panelController = PickerPanelController()

    /// Assigned in `init` after `monitor`; using `HotkeyController!` avoids capturing `self` in
    /// closures while a `let` is still being initialized (compiler error).
    private var hotkey: HotkeyController!

    /// Avoid spamming alerts if `installTap` is retried.
    private var didPresentEventTapInstallFailure = false

    init() {
        monitor = PasteboardMonitor(store: store)
        hotkey = HotkeyController(
            onBegan: { [weak self] in
                self?.handlePickerBegan()
            },
            onEndedPaste: { [weak self] in
                self?.handlePickerCommit()
            },
            onCancelled: { [weak self] in
                self?.handlePickerCancel()
            },
            onInstallFailed: { [weak self] in
                Task { @MainActor in
                    self?.presentEventTapInstallFailure()
                }
            },
            onScrollWhilePicking: { [weak self] dx, dy in
                Task { @MainActor in
                    guard let self else { return }
                    self.panelController.applyScrollDelta(deltaX: dx, deltaY: dy, store: self.store)
                }
            }
        )
    }

    func start() {
        monitor.start()
        hotkey.start()
        updateChecker.startPeriodicChecks()
    }

    func reloadHotkeyFromDefaults() {
        hotkey.reloadShortcutFromDefaults()
    }

    func refreshHistorySettings() {
        store.refreshMaxItems()
    }

    /// Opens settings using an `NSPanel` so it works with `LSUIElement` / menu-bar-only apps.
    func presentSettingsWindow() {
        SettingsWindowPresenter.present(model: self)
    }

    /// Call after enabling Accessibility (or from Settings) so the event tap can attach.
    func restartHotkeyListener() {
        didPresentEventTapInstallFailure = false
        hotkey.stop()
        hotkey.start()
    }

    /// Temporarily disable the global event tap (e.g. while recording a new shortcut).
    func suspendHotkey() {
        hotkey.stop()
    }

    /// Re-enable the global event tap after recording.
    func resumeHotkey() {
        hotkey.start()
    }

    private func handlePickerBegan() {
        guard PasteService.isTrusted else {
            PasteService.promptForAccessibility()
            hotkey.abortPickingSilently()
            return
        }
        store.selectedIndex = 0
        store.clampSelection()
        panelController.show(store: store)
    }

    private func handlePickerCommit() {
        panelController.hide()
        guard store.items.indices.contains(store.selectedIndex) else { return }
        let item = store.items[store.selectedIndex]
        PasteService.applyToGeneralPasteboard(item)
        monitor.syncChangeCount()
        PasteService.injectPasteCommand()
    }

    private func handlePickerCancel() {
        panelController.hide()
    }

    private func presentEventTapInstallFailure() {
        guard !didPresentEventTapInstallFailure else { return }
        didPresentEventTapInstallFailure = true
        let alert = NSAlert()
        alert.messageText = "Repaste can’t listen for shortcuts yet"
        alert.informativeText = """
        Turn on Repaste in System Settings → Privacy & Security → Accessibility, then quit Repaste and launch it again.

        In Notes (and most apps), the default chord is ⌘⇧V: hold it, scroll the picker with the trackpad, then release to paste. It is not ⌘R unless you select ⌘R in Repaste’s Settings.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Accessibility Settings…")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
