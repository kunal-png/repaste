import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Key-code / modifier display helpers

private let keyCodeNames: [UInt16: String] = [
    0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H",
    0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
    0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R",
    0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
    0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9",
    0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
    0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
    0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
    0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
    0x2F: ".", 0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫",
    0x35: "⎋",
    0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
    0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
    0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
]

private func modifierSymbols(_ flags: CGEventFlags) -> String {
    var s = ""
    if flags.contains(.maskControl) { s += "⌃" }
    if flags.contains(.maskAlternate) { s += "⌥" }
    if flags.contains(.maskShift) { s += "⇧" }
    if flags.contains(.maskCommand) { s += "⌘" }
    return s
}

private func shortcutLabel(keyCode: CGKeyCode, flags: CGEventFlags) -> String {
    modifierSymbols(flags) + (keyCodeNames[keyCode] ?? "Key\(keyCode)")
}

private func nsModsToCGFlags(_ mods: NSEvent.ModifierFlags) -> CGEventFlags {
    var f = CGEventFlags()
    if mods.contains(.command) { f.insert(.maskCommand) }
    if mods.contains(.shift) { f.insert(.maskShift) }
    if mods.contains(.option) { f.insert(.maskAlternate) }
    if mods.contains(.control) { f.insert(.maskControl) }
    return f
}

// MARK: - Conflict detection

private func conflictOwner(keyCode: CGKeyCode, flags: CGEventFlags) -> String? {
    let norm = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
    let table: [(UInt16, CGEventFlags, String)] = [
        (0x09, [.maskCommand], "Paste (system)"),
        (0x08, [.maskCommand], "Copy (system)"),
        (0x07, [.maskCommand], "Cut (system)"),
        (0x06, [.maskCommand], "Undo (system)"),
        (0x00, [.maskCommand], "Select All (system)"),
        (0x0C, [.maskCommand], "Quit (system)"),
        (0x0D, [.maskCommand], "Close Window (system)"),
        (0x01, [.maskCommand], "Save (system)"),
        (0x23, [.maskCommand], "Print (system)"),
        (0x2D, [.maskCommand], "New (system)"),
        (0x1F, [.maskCommand], "Open (system)"),
        (0x03, [.maskCommand], "Find (system)"),
        (0x04, [.maskCommand], "Hide (system)"),
        (0x2E, [.maskCommand], "Minimize (system)"),
        (0x31, [.maskCommand], "Spotlight (system)"),
        (0x0F, [.maskCommand], "Refresh / Xcode Run"),
        (0x11, [.maskCommand], "New Tab (browsers)"),
    ]
    for (code, fl, owner) in table {
        if keyCode == code && norm == fl { return owner }
    }
    return nil
}

// MARK: - Shortcut recorder view

private struct ShortcutRecorderView: View {
    @EnvironmentObject var model: AppModel
    @State private var keyCode: CGKeyCode
    @State private var flags: CGEventFlags
    @State private var isRecording = false
    @State private var conflict: String?
    @State private var monitor: Any?

    init() {
        let k = UserDefaults.standard.hotkeyKeyCode
        let f = UserDefaults.standard.hotkeyFlags
        _keyCode = State(initialValue: k)
        _flags = State(initialValue: f)
        _conflict = State(initialValue: {
            if let o = conflictOwner(keyCode: k, flags: f) {
                return "\(shortcutLabel(keyCode: k, flags: f)) conflicts with \(o)"
            }
            return nil
        }())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Shortcut")
                Spacer()
                Button(action: toggleRecording) {
                    HStack(spacing: 6) {
                        if isRecording {
                            Circle().fill(.red).frame(width: 8, height: 8)
                            Text("Type shortcut…")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(shortcutLabel(keyCode: keyCode, flags: flags))
                                .fontDesign(.rounded)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRecording ? Color.red.opacity(0.1) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isRecording ? Color.red.opacity(0.5) : Color.primary.opacity(0.15),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Text("Hold shortcut to open, scroll to pick, release to paste. Esc cancels.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let conflict {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(conflict)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        model.suspendHotkey()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = CGKeyCode(event.keyCode)
            if code == 0x35 { // Esc
                stopRecording()
                return nil
            }
            let cgFlags = nsModsToCGFlags(event.modifierFlags)
            let hasMod = !cgFlags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand]).isEmpty
            guard hasMod else { return nil }

            keyCode = code
            flags = cgFlags
            UserDefaults.standard.set(Int(code), forKey: UserDefaultsKeys.hotkeyKeyCode)
            UserDefaults.standard.set(NSNumber(value: cgFlags.rawValue), forKey: UserDefaultsKeys.hotkeyFlags)

            if let o = conflictOwner(keyCode: code, flags: cgFlags) {
                conflict = "\(shortcutLabel(keyCode: code, flags: cgFlags)) conflicts with \(o)"
            } else {
                conflict = nil
            }

            stopRecording()
            model.reloadHotkeyFromDefaults()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        model.resumeHotkey()
    }
}

// MARK: - Settings view

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(UserDefaultsKeys.historyLimit) private var historyLimitStorage = 50
    @AppStorage(UserDefaultsKeys.pickerPosition) private var pickerPosition = "cursor"
    @State private var accessibilityStatusRefresh = 0
    @State private var listenerJustStarted = false

    private var accessibilityTrusted: Bool {
        _ = accessibilityStatusRefresh
        return PasteService.isTrusted
    }

    var body: some View {
        Form {
            // MARK: Status
            Section {
                // Accessibility row
                HStack(spacing: 10) {
                    Image(systemName: accessibilityTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accessibilityTrusted ? Color.green : Color.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .fontWeight(.medium)
                        Text(accessibilityTrusted ? "Granted" : "Not granted — Repaste can't work without it")
                            .font(.caption)
                            .foregroundStyle(accessibilityTrusted ? Color.secondary : Color.red)
                    }
                    Spacer()
                    if !accessibilityTrusted {
                        Button("Grant Access…") {
                            PasteService.promptForAccessibility()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)

                // Start listener button
                HStack(spacing: 10) {
                    Image(systemName: listenerJustStarted ? "ear.and.waveform" : "ear")
                        .font(.title3)
                        .foregroundStyle(listenerJustStarted ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard Listener")
                            .fontWeight(.medium)
                        Text(listenerJustStarted ? "Listening for shortcut" : "Click Start after granting Accessibility")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(listenerJustStarted ? "Restart" : "Start Listening") {
                        accessibilityStatusRefresh &+= 1
                        model.restartHotkeyListener()
                        listenerJustStarted = true
                    }
                    .controlSize(.small)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Status")
            }

            // MARK: Shortcut
            Section("Shortcut") {
                ShortcutRecorderView()
            }

            // MARK: History
            Section("History") {
                Stepper(value: $historyLimitStorage, in: 5 ... 200, step: 5) {
                    Text("Keep up to \(historyLimitStorage) clips")
                }
                .onChange(of: historyLimitStorage) { _, _ in
                    model.refreshHistorySettings()
                }
            }

            // MARK: Popup Position
            Section("Popup Position") {
                Picker("Show picker", selection: $pickerPosition) {
                    Text("Centered on screen").tag("centered")
                    Text("Above text cursor").tag("cursor")
                }
                .pickerStyle(.radioGroup)
                Text("\"Above text cursor\" falls back to centered if the cursor can't be detected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: Updates
            Section("Updates") {
                HStack(spacing: 10) {
                    if model.updateChecker.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    } else if model.updateChecker.updateAvailable {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if model.updateChecker.isChecking {
                            Text("Checking for updates…")
                                .fontWeight(.medium)
                        } else if model.updateChecker.updateAvailable,
                                  let latest = model.updateChecker.latestVersion {
                            Text("Update available: v\(latest)")
                                .fontWeight(.medium)
                            Text("You are \(model.updateChecker.versionsBehind) version\(model.updateChecker.versionsBehind == 1 ? "" : "s") behind — current: v\(model.updateChecker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if model.updateChecker.lastCheckFailed {
                            Text("Could not check for updates")
                                .fontWeight(.medium)
                            Text("v\(model.updateChecker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Up to date")
                                .fontWeight(.medium)
                            Text("v\(model.updateChecker.currentVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if model.updateChecker.updateAvailable, let url = model.updateChecker.releaseURL {
                        Button("Download") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    } else if !model.updateChecker.isChecking {
                        Button("Check now") {
                            model.updateChecker.check()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear {
            normalizeStoredShortcut()
            model.reloadHotkeyFromDefaults()
            accessibilityStatusRefresh &+= 1
            // Auto-detect if listener is likely running (accessibility is granted)
            if accessibilityTrusted {
                listenerJustStarted = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityStatusRefresh &+= 1
        }
    }

    private func normalizeStoredShortcut() {
        if UserDefaults.standard.integer(forKey: UserDefaultsKeys.hotkeyKeyCode) == 0 {
            UserDefaults.standard.set(9, forKey: UserDefaultsKeys.hotkeyKeyCode)
        }
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.hotkeyFlags) == nil {
            UserDefaults.standard.set(
                NSNumber(value: CGEventFlags([.maskCommand, .maskShift]).rawValue),
                forKey: UserDefaultsKeys.hotkeyFlags
            )
        }
    }
}
