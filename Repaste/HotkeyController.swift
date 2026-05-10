import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Global event tap: hold shortcut to begin picker, release to confirm; Esc cancels.
final class HotkeyController {
    private struct Config {
        var keyCode: CGKeyCode
        var flags: CGEventFlags
    }

    private var config: Config {
        Config(
            keyCode: UserDefaults.standard.hotkeyKeyCode,
            flags: UserDefaults.standard.hotkeyFlags
        )
    }

    private let modifierMask: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand,
    ]

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let onBegan: () -> Void
    private let onEndedPaste: () -> Void
    private let onCancelled: () -> Void
    private let onInstallFailed: (() -> Void)?
    private let onScrollWhilePicking: ((CGFloat, CGFloat) -> Void)?

    private enum Phase {
        case idle
        case picking
    }

    private var phase = Phase.idle
    private let stateLock = NSLock()

    private var swallowNextTriggerKeyUp = false

    init(
        onBegan: @escaping () -> Void,
        onEndedPaste: @escaping () -> Void,
        onCancelled: @escaping () -> Void,
        onInstallFailed: (() -> Void)? = nil,
        onScrollWhilePicking: ((CGFloat, CGFloat) -> Void)? = nil
    ) {
        self.onBegan = onBegan
        self.onEndedPaste = onEndedPaste
        self.onCancelled = onCancelled
        self.onInstallFailed = onInstallFailed
        self.onScrollWhilePicking = onScrollWhilePicking
    }

    func abortPickingSilently() {
        stateLock.lock()
        phase = .idle
        swallowNextTriggerKeyUp = false
        stateLock.unlock()
    }

    func reloadShortcutFromDefaults() {
        reinstallTapIfNeeded()
    }

    func start() {
        installTap()
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.commonModes)
        }
        runLoopSource = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        eventTap = nil
    }

    private func installTap() {
        stop()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.scrollWheel.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passRetained(event)
            }
            let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
            return controller.handleEvent(proxyType: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.onInstallFailed?()
            }
            return
        }

        eventTap = tap
        CGEvent.tapEnable(tap: tap, enable: true)

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
    }

    private func reinstallTapIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            self?.installTap()
        }
    }

    private func normalizedModifiers(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(modifierMask)
    }

    private func matchesShortcut(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let c = config
        return keyCode == c.keyCode && normalizedModifiers(flags) == normalizedModifiers(c.flags)
    }

    private func handleEvent(proxyType: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if proxyType == .tapDisabledByTimeout || proxyType == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        stateLock.lock()
        let currentPhase = phase
        stateLock.unlock()

        switch proxyType {
        case .scrollWheel:
            if currentPhase == .picking, let handler = onScrollWhilePicking {
                let deltas = HotkeyController.scrollWheelDeltas(from: event)
                DispatchQueue.main.async {
                    handler(deltas.dx, deltas.dy)
                }
                return nil
            }
        case .keyDown:
            if keyCode == CGKeyCode(kVK_Escape), currentPhase == .picking {
                DispatchQueue.main.async { [weak self] in
                    self?.cancelPicking()
                }
                return nil
            }
            if currentPhase == .picking, keyCode == config.keyCode {
                return nil
            }
            if currentPhase == .idle, matchesShortcut(keyCode: keyCode, flags: flags) {
                DispatchQueue.main.async { [weak self] in
                    self?.beginPicking()
                }
                return nil
            }
        case .keyUp:
            stateLock.lock()
            let swallow = swallowNextTriggerKeyUp && keyCode == config.keyCode
            if swallow {
                swallowNextTriggerKeyUp = false
            }
            stateLock.unlock()
            if swallow {
                return nil
            }
            if currentPhase == .picking, keyCode == config.keyCode {
                DispatchQueue.main.async { [weak self] in
                    self?.finishPicking(paste: true, swallowUpcomingTriggerKeyUp: false)
                }
            }
        case .flagsChanged:
            if currentPhase == .picking {
                let norm = normalizedModifiers(flags)
                let required = normalizedModifiers(config.flags)
                if !required.isSubset(of: norm) {
                    DispatchQueue.main.async { [weak self] in
                        self?.finishPicking(paste: true, swallowUpcomingTriggerKeyUp: true)
                    }
                }
            }
        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    private func beginPicking() {
        stateLock.lock()
        guard phase == .idle else {
            stateLock.unlock()
            return
        }
        phase = .picking
        stateLock.unlock()
        onBegan()
    }

    private func cancelPicking() {
        stateLock.lock()
        guard phase == .picking else {
            stateLock.unlock()
            return
        }
        phase = .idle
        stateLock.unlock()
        onCancelled()
    }

    private func finishPicking(paste: Bool, swallowUpcomingTriggerKeyUp: Bool) {
        stateLock.lock()
        guard phase == .picking else {
            stateLock.unlock()
            return
        }
        phase = .idle
        if swallowUpcomingTriggerKeyUp {
            swallowNextTriggerKeyUp = true
        }
        stateLock.unlock()
        if paste {
            onEndedPaste()
        } else {
            onCancelled()
        }
    }

    private static func scrollWheelDeltas(from event: CGEvent) -> (dx: CGFloat, dy: CGFloat) {
        let dy1 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let dx1 = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
        if dx1 != 0 || dy1 != 0 {
            return (CGFloat(dx1), CGFloat(dy1))
        }
        let iY = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let iX = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        return (CGFloat(iX) * 12, CGFloat(iY) * 12)
    }
}
