import AppKit
import QuartzCore
import SwiftUI

/// Arc opens toward the text caret (mockup: ∧ above, ∨ below).
enum PickerVerticalPlacement {
    case aboveCursor
    case belowCursor
}

enum PickerMetrics {
    /// Fixed panel size — never changes, so the window never resizes or jumps.
    static let panelWidth: CGFloat = 800
    static let panelHeight: CGFloat = 300

    static let cellSpacing: CGFloat = 150
    static let cardWidth: CGFloat = 124
    static let cardHeight: CGFloat = 82
    static let thumbSize: CGFloat = 40

    /// Radius of the virtual circle the cards sit on (bigger = flatter arc).
    static let arcRadius: CGFloat = 800
    /// Degrees of rotation per card step along the arc.
    static let arcDegreesPerStep: Double = 7.0
    /// Gap between cursor top and panel bottom.
    static let cursorGap: CGFloat = 16
}

@MainActor
final class PickerPanelController {
    private var panel: FloatingPickerPanel?
    private var hosting: NSHostingView<PickerView>?
    private var scrollAccum: CGFloat = 0

    func show(store: ClipboardHistoryStore) {
        hide()
        scrollAccum = 0

        let size = NSSize(width: PickerMetrics.panelWidth, height: PickerMetrics.panelHeight)
        let padding: CGFloat = 8
        let positionMode = UserDefaults.standard.string(forKey: UserDefaultsKeys.pickerPosition) ?? "cursor"

        let frame: NSRect
        if positionMode == "centered" {
            let vf = NSScreen.main?.visibleFrame ?? .zero
            let originX = vf.midX - size.width / 2
            let originY = vf.midY - size.height / 2
            frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        } else {
            // Follow the text cursor
            let caret = PasteService.pickerCaretScreenRect()
            let vf: CGRect = {
                let p = NSPoint(x: caret.midX, y: caret.midY)
                if let s = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) {
                    return s.visibleFrame
                }
                return NSScreen.main?.visibleFrame ?? .zero
            }()

            // Center horizontally on the caret, clamp to screen
            var originX = caret.midX - size.width / 2
            originX = min(max(originX, vf.minX + padding), vf.maxX - padding - size.width)

            // Position above the caret
            var originY = caret.maxY + PickerMetrics.cursorGap
            // If it would go off the top, flip below
            if originY + size.height > vf.maxY - padding {
                originY = caret.minY - PickerMetrics.cursorGap - size.height
            }
            // Final clamp
            originY = min(max(originY, vf.minY + padding), vf.maxY - padding - size.height)

            frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        }

        let picker = PickerView(store: store)
        let host = NSHostingView(rootView: picker)
        host.autoresizingMask = [.width, .height]
        host.layer?.masksToBounds = false

        let panel = FloatingPickerPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false

        panel.setContentSize(size)
        panel.contentView = host
        panel.contentView?.clipsToBounds = false
        host.frame = NSRect(origin: .zero, size: size)

        panel.setFrame(frame, display: false)
        panel.alphaValue = 0

        self.panel = panel
        self.hosting = host
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hosting = nil
        scrollAccum = 0
    }

    func applyScrollDelta(deltaX: CGFloat, deltaY: CGFloat, store: ClipboardHistoryStore) {
        CarouselWheelNavigation.applyScrollDelta(
            deltaX: deltaX,
            deltaY: deltaY,
            scrollAccum: &scrollAccum,
            store: store
        )
    }
}

final class FloatingPickerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Rotary-phone arc carousel

struct PickerView: View {
    @ObservedObject var store: ClipboardHistoryStore

    var body: some View {
        Group {
            if store.items.isEmpty {
                Text("Copy something first — history appears here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 20)
                    .frame(width: PickerMetrics.panelWidth, height: PickerMetrics.panelHeight)
            } else {
                rotaryStrip
                    .frame(width: PickerMetrics.panelWidth, height: PickerMetrics.panelHeight)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(Color.clear)
    }

    // MARK: - Rotary strip

    private var rotaryStrip: some View {
        ZStack {
            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                let rel = CGFloat(index - store.selectedIndex)
                clipCard(item: item, isSelected: index == store.selectedIndex)
                    .opacity(cardOpacity(rel: rel))
                    .scaleEffect(cardScale(rel: rel))
                    .offset(
                        x: rel * PickerMetrics.cellSpacing,
                        y: arcLiftUp(rel: rel)
                    )
                    .rotationEffect(
                        .degrees(Double(rel) * -PickerMetrics.arcDegreesPerStep),
                        anchor: .bottom
                    )
                    .zIndex(index == store.selectedIndex ? 10 : Double(5 - Int(abs(rel))))
            }
        }
        .frame(width: PickerMetrics.panelWidth, height: PickerMetrics.panelHeight)
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1.0),
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: store.selectedIndex)
    }

    // MARK: - Arc math (selected card at top, side cards drop down = ∩ shape)

    /// Cards further from center drop DOWN (positive Y in SwiftUI = downward).
    private func arcLiftUp(rel: CGFloat) -> CGFloat {
        let t = abs(rel)
        let angle = Double(t) * PickerMetrics.arcDegreesPerStep * .pi / 180.0
        let lift = PickerMetrics.arcRadius * (1 - cos(angle))
        return CGFloat(lift)    // positive = downward in SwiftUI → ∩ arc
    }

    // MARK: - Opacity / scale

    /// Full opacity for selected + 2 neighbours, then fade.
    private func cardOpacity(rel: CGFloat) -> CGFloat {
        let a = abs(rel)
        if a <= 2.0 { return 1.0 }
        if a > 5.0 { return 0.0 }
        return max(0.0, 1.0 - 0.3 * (a - 2.0))
    }

    private func cardScale(rel: CGFloat) -> CGFloat {
        let a = abs(rel)
        return max(0.65, 1.0 - 0.06 * a)
    }

    // MARK: - Card view

    @ViewBuilder
    private func clipCard(item: ClipboardItem, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            thumbnailView(for: item)
            Text(item.previewLine)
                .font(.system(size: 10, weight: .medium, design: .default))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .frame(maxWidth: PickerMetrics.cardWidth - PickerMetrics.thumbSize - 14, alignment: .topLeading)
        }
        .padding(8)
        .frame(width: PickerMetrics.cardWidth, height: PickerMetrics.cardHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isSelected ? 1 : 0.9)
        )
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.12),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.45) : .black.opacity(0.2), radius: isSelected ? 14 : 5, y: isSelected ? 5 : 3)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }

    @ViewBuilder
    private func thumbnailView(for item: ClipboardItem) -> some View {
        let img: NSImage? = {
            if let d = item.imagePNG, let i = NSImage(data: d) { return i }
            if let d = item.imageTIFF, let i = NSImage(data: d) { return i }
            return nil
        }()
        if let img {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: PickerMetrics.thumbSize, height: PickerMetrics.thumbSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: PickerMetrics.thumbSize, height: PickerMetrics.thumbSize)
                .overlay {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
        }
    }
}
