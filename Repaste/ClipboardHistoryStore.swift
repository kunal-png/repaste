import AppKit
import Combine
import CoreGraphics
import CryptoKit
import Foundation

/// One snapshot of the general pasteboard worth replaying.
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let capturedAt: Date

    var plainText: String?
    var rtfData: Data?
    var htmlData: Data?
    var imageTIFF: Data?
    var imagePNG: Data?
    var fileURLs: [URL]

    init(
        id: UUID = UUID(),
        capturedAt: Date = Date(),
        plainText: String?,
        rtfData: Data?,
        htmlData: Data?,
        imageTIFF: Data?,
        imagePNG: Data?,
        fileURLs: [URL]
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.plainText = plainText
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imageTIFF = imageTIFF
        self.imagePNG = imagePNG
        self.fileURLs = fileURLs
    }

    /// Short line for the picker UI.
    var previewLine: String {
        if let t = plainText?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            let maxLen = 120
            if t.count <= maxLen { return t }
            return String(t.prefix(maxLen)) + "…"
        }
        if !fileURLs.isEmpty {
            return fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        }
        if imageTIFF != nil || imagePNG != nil {
            return "Image"
        }
        return "Clip"
    }

    func fingerprintData() -> Data? {
        var chunks: [Data] = []
        if let plainText {
            chunks.append(Data(plainText.utf8))
        }
        if let rtfData {
            chunks.append(rtfData)
        }
        if let htmlData {
            chunks.append(htmlData)
        }
        if let imageTIFF {
            chunks.append(imageTIFF)
        }
        if let imagePNG {
            chunks.append(imagePNG)
        }
        for url in fileURLs {
            if let u = url.absoluteString.data(using: .utf8) {
                chunks.append(u)
            }
        }
        guard !chunks.isEmpty else { return nil }
        return chunks.reduce(into: Data()) { $0.append($1) }
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.fingerprintDigest() == rhs.fingerprintDigest()
    }

    private func fingerprintDigest() -> String? {
        guard let d = fingerprintData() else { return nil }
        let digest = SHA256.hash(data: d)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published var selectedIndex: Int = 0

    private let maxItems: () -> Int

    init(maxItems: @escaping () -> Int = { UserDefaults.standard.historyLimit }) {
        self.maxItems = maxItems
    }

    func refreshMaxItems() {
        trim()
    }

    func prependIfNew(_ item: ClipboardItem) {
        if let first = items.first, first == item {
            return
        }
        items.insert(item, at: 0)
        trim()
    }

    func clear() {
        items.removeAll()
        selectedIndex = 0
    }

    private func trim() {
        let limit = max(1, maxItems())
        if items.count > limit {
            items = Array(items.prefix(limit))
        }
        if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
        }
    }

    func clampSelection() {
        guard !items.isEmpty else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), items.count - 1)
    }

    /// Replaces list content (e.g. settings carousel demo). Does not touch the pasteboard.
    func replaceItems(_ items: [ClipboardItem], selectedIndex: Int = 0) {
        self.items = items
        if items.isEmpty {
            self.selectedIndex = 0
        } else {
            self.selectedIndex = min(max(0, selectedIndex), items.count - 1)
        }
    }
}

// MARK: - Scroll wheel → carousel step

@MainActor
enum CarouselWheelNavigation {
    /// Accumulated wheel delta needed to move one clip (unchanged from original behavior at 1.0× sensitivity).
    private static let stepThreshold: CGFloat = 14

    static func applyScrollDelta(
        deltaX: CGFloat,
        deltaY: CGFloat,
        scrollAccum: inout CGFloat,
        store: ClipboardHistoryStore
    ) {
        let mult = CGFloat(UserDefaults.standard.scrollWheelSensitivity)
        scrollAccum += (deltaY + deltaX) * mult
        guard abs(scrollAccum) >= stepThreshold else { return }
        let direction = scrollAccum > 0 ? 1 : -1
        scrollAccum -= CGFloat(direction) * stepThreshold

        guard !store.items.isEmpty else { return }
        let n = store.items.count
        var idx = store.selectedIndex + direction
        idx = min(max(0, idx), n - 1)
        guard idx != store.selectedIndex else { return }
        store.selectedIndex = idx
        if UserDefaults.standard.carouselHapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
    }
}

enum UserDefaultsKeys {
    static let historyLimit = "historyLimit"
    static let hotkeyFlags = "hotkeyFlags"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    /// "centered" or "cursor" — where the picker panel appears.
    static let pickerPosition = "pickerPosition"
    /// Multiplier for wheel deltas before thresholding (default 1.0). Higher = more sensitive.
    static let scrollWheelSensitivity = "scrollWheelSensitivity"
    /// Haptic tick when moving to another clip in the picker (default on).
    static let carouselHapticsEnabled = "carouselHapticsEnabled"
}

extension UserDefaults {
    var historyLimit: Int {
        let v = integer(forKey: UserDefaultsKeys.historyLimit)
        if v == 0 { return 50 }
        return min(200, max(5, v))
    }

    var hotkeyKeyCode: CGKeyCode {
        let raw = integer(forKey: UserDefaultsKeys.hotkeyKeyCode)
        if raw == 0 { return 0x09 }
        return CGKeyCode(raw)
    }

    /// Stored as NSNumber wrapping CGEventFlags rawValue (UInt64).
    var hotkeyFlags: CGEventFlags {
        guard let num = object(forKey: UserDefaultsKeys.hotkeyFlags) as? NSNumber else {
            return [.maskCommand, .maskShift]
        }
        return CGEventFlags(rawValue: num.uint64Value)
    }

    /// Stored scroll multiplier; 0 means “unset” and maps to 1.0 for backwards compatibility.
    var scrollWheelSensitivity: Double {
        let v = double(forKey: UserDefaultsKeys.scrollWheelSensitivity)
        if v == 0 { return 1.0 }
        return min(2.5, max(0.25, v))
    }

    /// `bool(forKey:)` is false when unset — default is on until the user changes the toggle.
    var carouselHapticsEnabled: Bool {
        if object(forKey: UserDefaultsKeys.carouselHapticsEnabled) == nil { return true }
        return bool(forKey: UserDefaultsKeys.carouselHapticsEnabled)
    }
}
