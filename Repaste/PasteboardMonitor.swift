import AppKit
import Foundation

/// Polls the system pasteboard and pushes new clips into the history store.
final class PasteboardMonitor {
    private let store: ClipboardHistoryStore
    private var lastChangeCount: Int
    private var timer: Timer?

    init(store: ClipboardHistoryStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    @MainActor
    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        guard let types = pb.types, !types.isEmpty else { return }

        let plain: String? = types.contains(.string) ? pb.string(forType: .string) : nil
        let rtf: Data? = types.contains(.rtf) ? pb.data(forType: .rtf) : nil
        let html: Data? = types.contains(.html) ? pb.data(forType: .html) : nil

        var tiff: Data?
        var png: Data?
        if types.contains(.tiff) {
            tiff = pb.data(forType: .tiff)
        } else if types.contains(.png) {
            png = pb.data(forType: .png)
        }

        var files: [URL] = []
        if types.contains(.fileURL) {
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                files = urls
            }
        }

        let hasContent = plain != nil || rtf != nil || html != nil || tiff != nil || png != nil || !files.isEmpty
        guard hasContent else { return }

        let item = ClipboardItem(
            plainText: plain,
            rtfData: rtf,
            htmlData: html,
            imageTIFF: tiff,
            imagePNG: png,
            fileURLs: files
        )
        guard item.fingerprintData() != nil else { return }
        store.prependIfNew(item)
    }
}
