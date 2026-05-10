import AppKit
import ApplicationServices
import Foundation

enum PasteService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Helps debug “toggle ON in System Settings but app still untrusted” (common with Xcode / DerivedData).
    static var accessibilityHelpFootnote: String {
        let id = Bundle.main.bundleIdentifier ?? "(no bundle id)"
        let path = Bundle.main.bundleURL.path
        return "This running build:\n\(id)\n\(path)"
    }

    static func promptForAccessibility() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true,
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func applyToGeneralPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if !item.fileURLs.isEmpty {
            pb.writeObjects(item.fileURLs as [NSPasteboardWriting])
        }

        if let t = item.plainText {
            pb.setString(t, forType: .string)
        }
        if let d = item.rtfData {
            pb.setData(d, forType: .rtf)
        }
        if let d = item.htmlData {
            pb.setData(d, forType: .html)
        }
        if let d = item.imageTIFF {
            pb.setData(d, forType: .tiff)
        }
        if let d = item.imagePNG {
            pb.setData(d, forType: .png)
        }
    }

    /// Injects Command+V using the HID event tap target.
    static func injectPasteCommand(keyCode: CGKeyCode = 0x09) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else { return }
        guard let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(3000)
        up.post(tap: .cghidEventTap)
    }

    /// Global **CGRect** for the caret / focused text (AppKit screen coords, origin bottom-left).
    /// 1) `NSTextView` in our key window (accurate insertion rect). 2) Accessibility. 3) mouse.
    static func pickerCaretScreenRect() -> CGRect {
        if let r = Self.insertionRectFromFocusedNSTextView() { return r }

        let mouse = NSEvent.mouseLocation
        let fallback = Self.syntheticCaretRect(at: mouse)
        guard isTrusted else { return fallback }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return fallback }

        let focused = focusedRef as! AXUIElement
        if let raw = Self.caretRectFromSelectionBounds(element: focused),
           let norm = Self.sanitizeCaretRect(Self.normalizeAXRectToAppKit(raw)) {
            return norm
        }
        if let raw = Self.caretRectFromAXFrame(element: focused) {
            let norm = Self.normalizeAXRectToAppKit(raw)
            let anchored = Self.narrowCaretRectIfFullTextFrame(norm)
            if let s = Self.sanitizeCaretRect(anchored) {
                return s
            }
        }
        return fallback
    }

    /// Uses `NSTextView.firstRect(forCharacterRange:actualRange:)` → window space → `convertToScreen`.
    static func insertionRectFromFocusedNSTextView() -> CGRect? {
        guard let textView = Self.keyWindowFirstResponderTextView(),
              let window = textView.window
        else { return nil }

        let range = textView.selectedRange()
        var actual = NSRange(location: 0, length: 0)
        let rectInText = textView.firstRect(forCharacterRange: range, actualRange: &actual)
        guard !rectInText.isNull, !rectInText.isInfinite else { return nil }

        let rectInWindow = textView.convert(rectInText, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    private static func keyWindowFirstResponderTextView() -> NSTextView? {
        guard let responder = NSApp.keyWindow?.firstResponder else { return nil }
        return responder as? NSTextView
    }

    private static func syntheticCaretRect(at mouse: NSPoint) -> CGRect {
        let h: CGFloat = 22
        let w: CGFloat = 2
        return CGRect(x: mouse.x - w / 2, y: mouse.y - 3, width: w, height: h)
    }

    private static func caretRectFromSelectionBounds(element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }

        let rangeValue = rangeRef as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetType(rangeValue) == .cfRange,
              AXValueGetValue(rangeValue, .cfRange, &range)
        else { return nil }

        let rangeParam: AXValue? = withUnsafeMutablePointer(to: &range) { ptr in
            AXValueCreate(.cfRange, UnsafeRawPointer(ptr))
        }
        guard let rangeParam else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeParam,
            &boundsRef
        ) == .success,
              let boundsRef,
              CFGetTypeID(boundsRef) == AXValueGetTypeID()
        else { return nil }

        let boundsValue = boundsRef as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(boundsValue) == .cgRect,
              AXValueGetValue(boundsValue, .cgRect, &rect)
        else { return nil }

        guard rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height >= 0, rect.width <= 8000, rect.height <= 4000
        else { return nil }

        return rect
    }

    private static func caretRectFromAXFrame(element: AXUIElement) -> CGRect? {
        var frameRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameRef) == .success,
              let frameRef,
              CFGetTypeID(frameRef) == AXValueGetTypeID()
        else { return nil }

        let frameValue = frameRef as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(frameValue) == .cgRect,
              AXValueGetValue(frameValue, .cgRect, &rect)
        else { return nil }

        guard rect.width > 2, rect.height > 2, rect.width <= 8000, rect.height <= 4000 else { return nil }
        return rect
    }

    // MARK: - AX → AppKit screen space

    /// WebKit / some hosts return global rects whose Y axis does not match AppKit (`NSEvent.mouseLocation`).
    /// Do **not** use distance-to-mouse as the primary signal (hotkey use leaves the cursor far from the caret).
    private static func normalizeAXRectToAppKit(_ rect: CGRect) -> CGRect {
        let flipped = flippedTopLeftAXRectToAppKit(rect)
        let desktop = nsscreenUnionFrame
        let slack = desktop.insetBy(dx: -800, dy: -800)

        let rCenter = CGPoint(x: rect.midX, y: rect.midY)
        let fCenter = CGPoint(x: flipped.midX, y: flipped.midY)
        let rOK = slack.contains(rCenter)
        let fOK = slack.contains(fCenter)
        if rOK, !fOK { return rect }
        if fOK, !rOK { return flipped }

        func overlapArea(_ r: CGRect) -> CGFloat {
            let i = r.intersection(desktop)
            return max(0, i.width) * max(0, i.height)
        }
        let ra = overlapArea(rect)
        let fa = overlapArea(flipped)
        if fa > ra + 0.5 { return flipped }
        return rect
    }

    private static var nsscreenUnionFrame: CGRect {
        NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    }

    /// Approximate conversion when AX uses top-down Y relative to a screen’s `frame.maxY`.
    /// AX global coordinates always have (0,0) at the top-left of the primary screen.
    private static func flippedTopLeftAXRectToAppKit(_ rect: CGRect) -> CGRect {
        let probe = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(probe, $0.frame, false) })
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSPoint(x: rect.midX, y: rect.midY), $0.frame, false) })
            ?? NSScreen.main
        else { return rect }
        let f = screen.frame
        return CGRect(x: rect.origin.x, y: f.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    /// `AXFrame` is often the whole text area — using its `midX` shoves the picker to the screen edge. Collapse to a caret-like rect near the mouse, clamped inside the frame.
    private static func narrowCaretRectIfFullTextFrame(_ frame: CGRect) -> CGRect {
        let fieldThreshold: CGFloat = 200
        guard frame.width > fieldThreshold else { return frame }

        let m = NSEvent.mouseLocation
        let cx = min(max(m.x, frame.minX + 2), frame.maxX - 2)
        let cy = min(max(m.y, frame.minY + 10), frame.maxY - 10)
        let h: CGFloat = 22
        return CGRect(x: cx - 1, y: cy - h / 2, width: 2, height: h)
    }

    /// Drop unusable geometry; require center inside desktop (with slack).
    private static func sanitizeCaretRect(_ rect: CGRect) -> CGRect? {
        guard rect.width.isFinite, rect.height.isFinite,
              rect.width >= 0, rect.height >= 0, !rect.isNull, !rect.isInfinite
        else { return nil }
        let slack = nsscreenUnionFrame.insetBy(dx: -800, dy: -800)
        guard slack.contains(CGPoint(x: rect.midX, y: rect.midY)) else { return nil }
        return rect
    }
}
