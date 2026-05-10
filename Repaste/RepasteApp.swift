import AppKit
import SwiftUI

@main
struct RepasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Repaste", systemImage: "doc.on.clipboard") {
            MenuBarExtraContent()
                .environmentObject(model)
                .onAppear {
                    model.start()
                }
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

private struct MenuBarExtraContent: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Text("Hold ⌘⇧V (change in Settings), scroll, release to paste.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.top, 4)
        Button("Settings…") {
            model.presentSettingsWindow()
        }
        Divider()
        Button("Clear history") {
            model.store.clear()
        }
        Divider()
        Button("Quit Repaste") {
            NSApplication.shared.terminate(nil)
        }
    }
}
