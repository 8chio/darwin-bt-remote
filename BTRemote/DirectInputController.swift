#if os(macOS)
    import AppKit
    import CoreGraphics
    import Foundation
    import os

    /// Keyboard-only capture: the Mac trackpad and mouse are never tapped, hidden, or forwarded.
    @MainActor
    final class DirectInputController: ObservableObject {
        @Published private(set) var isCapturing = false
        @Published private(set) var lastError: String?
        @Published private(set) var needsAccessibility = false

        /// Pointer events are deliberately absent so clicks, drags, scrolls and gestures stay on the Mac.
        nonisolated static let capturedEventTypes: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        nonisolated static let eventMask: CGEventMask = capturedEventTypes.reduce(CGEventMask(0)) { result, type in
            result | (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "DirectInputCapture")
        private var eventTap: CFMachPort?
        private var runLoopSource: CFRunLoopSource?
        private var statusItem: NSStatusItem?
        private var statusItemTarget: DirectInputStatusItemTarget?
        private var router: DirectInputKeyboardRouter?
        private var shortcutSuppression = DirectInputShortcutSuppression()
        var toggleHotkey: DirectInputHotkey?
        var onToggleShortcut: (() -> Void)?
        var onShortcutKeyUp: ((UInt16) -> Void)?

        private var onRelease: (() -> Void)?

        /// capture keyboard input and route it to HID backend
        func start(_ hid: HIDInput, suppressing hotkey: DirectInputHotkey? = nil) {
            start(sendKeyboard: hid.sendKeyboard, onRelease: {})
            if isCapturing { shortcutSuppression = DirectInputShortcutSuppression(hotkey) }
        }

        func start(sendKeyboard: @escaping (KeyboardReport) -> Void, onRelease: @escaping () -> Void) {
            stop()
            lastError = nil

            // Any failure leaves the Mac keyboard untouched and the remote host neutral.
            func fail(_ reason: String) {
                log.error("capture not started: \(reason, privacy: .public)")
                sendKeyboard(.zero)
                onRelease()
            }

            guard AccessibilityPermission.isTrusted else {
                needsAccessibility = true
                fail("accessibility not trusted")
                return
            }

            let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: DirectInputController.eventTapCallback,
                userInfo: refcon
            ) else {
                lastError = L10n.DirectInput.captureFailedString
                fail("event tap unavailable")
                return
            }

            eventTap = tap
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            guard let runLoopSource else {
                CFMachPortInvalidate(tap)
                eventTap = nil
                lastError = L10n.DirectInput.captureFailedString
                fail("run loop source unavailable")
                return
            }
            router = DirectInputKeyboardRouter(send: sendKeyboard)
            self.onRelease = onRelease
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            guard CGEvent.tapIsEnabled(tap: tap) else {
                stop()
                lastError = L10n.DirectInput.captureFailedString
                fail("event tap disabled")
                return
            }
            isCapturing = true
            log.info("keyboard capture started")
            showStatusItem()
        }

        func stop() {
            if isCapturing { log.info("keyboard capture stopped; releasing remote keys") }
            isCapturing = false
            shortcutSuppression = DirectInputShortcutSuppression()
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: false)
            }
            if let runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            }
            if let eventTap { CFMachPortInvalidate(eventTap) }
            eventTap = nil
            runLoopSource = nil

            router?.reset()
            router = nil
            onRelease = nil
            hideStatusItem()
        }

        func clearAccessibilityRequest() {
            needsAccessibility = false
        }

        /// menu bar indicator while the keyboard goes to the remote device; clickable with the Mac trackpad
        private func showStatusItem() {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
                icon?.isTemplate = false
                button.image = icon
                button.imagePosition = .imageLeading
                button.attributedTitle = NSAttributedString(
                    string: "  " + L10n.RemoteKeyboard.statusTitleString,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
            }
            let target = DirectInputStatusItemTarget { [weak self] in
                guard let self, isCapturing else { return }
                onRelease?()
                stop()
            }
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: L10n.DirectInput.releaseHintString, action: nil, keyEquivalent: ""))
            let release = NSMenuItem(
                title: L10n.RemoteKeyboard.returnToMacString,
                action: #selector(DirectInputStatusItemTarget.fire),
                keyEquivalent: ""
            )
            release.target = target
            menu.addItem(release)
            item.menu = menu
            statusItemTarget = target
            statusItem = item
        }

        private func hideStatusItem() {
            if let statusItem {
                NSStatusBar.system.removeStatusItem(statusItem)
            }
            statusItem = nil
            statusItemTarget = nil
        }

        private func handle(_ event: DirectInputEvent) {
            guard isCapturing, let router else { return }
            if event.releaseShortcutPressed {
                onRelease?()
                stop()
                return
            }
            router.handle(event)
        }

        private func intercept(_ input: DirectInputShortcutEvent) {
            guard isCapturing else { return }
            if input.type == .keyUp { onShortcutKeyUp?(input.keyCode) }
            if input.isToggle(hotkey: toggleHotkey) {
                if let onToggleShortcut { onToggleShortcut() } else { stop() }
                return
            }
            let filtered = shortcutSuppression.filter(type: input.type, keyCode: input.keyCode, flags: input.flags)
            guard !filtered.swallow else { return }
            if let event = input.event(flags: filtered.flags) { handle(event) }
        }

        private nonisolated static let eventTapCallback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
            guard let userInfo else { return nil }
            let controller = Unmanaged<DirectInputController>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                // Release immediately rather than retaining keys after capture fails.
                MainActor.assumeIsolated {
                    guard controller.isCapturing else { return }
                    controller.log.error("capture tap disabled; releasing input")
                    controller.stop()
                    controller.lastError = L10n.DirectInput.captureFailedString
                }
                return nil
            }
            // Never consume anything outside the keyboard mask (pointer input stays on the Mac).
            guard DirectInputController.capturedEventTypes.contains(type) else { return Unmanaged.passUnretained(cgEvent) }
            // The tap is installed on the main run loop. Process synchronously so
            // queued events cannot cross a stop/start boundary or race a Carbon toggle.
            let input = DirectInputShortcutEvent(type: type, event: cgEvent)
            MainActor.assumeIsolated { controller.intercept(input) }
            return nil
        }

    }

    @MainActor
    private final class DirectInputStatusItemTarget: NSObject {
        private let action: () -> Void

        init(_ action: @escaping () -> Void) {
            self.action = action
        }

        @objc func fire() {
            action()
        }
    }

    /// Keyboard HID state for one capture session; it only ever emits keyboard reports.
    @MainActor
    final class DirectInputKeyboardRouter {
        typealias Schedule = @MainActor (UInt64, @escaping @MainActor () -> Void) -> @MainActor () -> Void

        /// macOS reports one flagsChanged per Caps Lock press and no key-up, so the remote
        /// press is synthesized as a short tap. Spacing keeps the BLE backend from
        /// coalescing the press into the release.
        static let capsLockHoldNanoseconds: UInt64 = 60_000_000

        private let send: (KeyboardReport) -> Void
        private let schedule: Schedule
        private let now: @MainActor () -> UInt64
        private(set) var pressedKeys: Set<Keycode> = []
        private(set) var modifiers: KeyboardModifiers = []
        private(set) var isCapsLockHeld = false
        private var capsLockFilter = DirectInputCapsLockFilter()
        private var cancelCapsLockRelease: (@MainActor () -> Void)?

        init(
            send: @escaping (KeyboardReport) -> Void,
            schedule: @escaping Schedule = DirectInputKeyboardRouter.scheduleOnMain,
            now: @escaping @MainActor () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }
        ) {
            self.send = send
            self.schedule = schedule
            self.now = now
        }

        var report: KeyboardReport {
            let keys = pressedKeys.filter { $0 != .capsLock }.sorted { $0.rawValue < $1.rawValue }
            return KeyboardReport(modifiers: modifiers, keys: Array(((isCapsLockHeld ? [.capsLock] : []) + keys).prefix(6)))
        }

        func handle(_ event: DirectInputEvent) {
            modifiers = event.modifiers
            switch event.kind {
            case let .keyDown(key):
                pressedKeys.insert(key)
            case let .keyUp(key):
                pressedKeys.remove(key)
            case .flagsChanged:
                break
            case let .capsLock(isOn):
                guard capsLockFilter.accept(isOn: isOn, at: now()) else { return }
                tapCapsLock()
                return
            }
            send(report)
        }

        /// Sends one neutral report so nothing stays pressed on the remote host.
        func reset() {
            cancelCapsLockRelease?()
            cancelCapsLockRelease = nil
            isCapsLockHeld = false
            pressedKeys.removeAll()
            modifiers = []
            capsLockFilter = DirectInputCapsLockFilter()
            send(.zero)
        }

        private func tapCapsLock() {
            if isCapsLockHeld { releaseCapsLock() }
            isCapsLockHeld = true
            send(report)
            cancelCapsLockRelease = schedule(Self.capsLockHoldNanoseconds) { [weak self] in self?.releaseCapsLock() }
        }

        private func releaseCapsLock() {
            cancelCapsLockRelease?()
            cancelCapsLockRelease = nil
            guard isCapsLockHeld else { return }
            isCapsLockHeld = false
            send(report)
        }

        static func scheduleOnMain(_ nanoseconds: UInt64, _ work: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                work()
            }
            return { task.cancel() }
        }
    }

    /// One physical Caps Lock press may surface as a repeated flagsChanged with the same
    /// lock state (duplicate delivery or a release echo). Those are dropped; a state change
    /// or a press after the window always counts.
    struct DirectInputCapsLockFilter {
        static let duplicateWindowNanoseconds: UInt64 = 250_000_000

        private var last: (isOn: Bool, time: UInt64)?

        mutating func accept(isOn: Bool, at time: UInt64) -> Bool {
            if let last, last.isOn == isOn, time >= last.time, time - last.time < Self.duplicateWindowNanoseconds {
                return false
            }
            last = (isOn, time)
            return true
        }
    }

    struct DirectInputShortcutEvent: Sendable {
        let type: CGEventType
        let keyCode: UInt16
        let flags: CGEventFlags
        let isRepeat: Bool
        private let decoded: DirectInputEvent?

        init(type: CGEventType, event: CGEvent) {
            self.type = type
            keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            flags = event.flags
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            decoded = DirectInputEvent(type: type, event: event)
        }

        func isToggle(hotkey: DirectInputHotkey?) -> Bool {
            type == .keyDown && !isRepeat && hotkey?.matches(keyCode: keyCode, flags: flags) == true
        }

        func event(flags: CGEventFlags) -> DirectInputEvent? {
            guard var decoded else { return nil }
            decoded.modifiers = KeyboardModifiers(eventFlags: flags)
            decoded.releaseShortcutPressed = flags.contains(.maskControl) && flags.contains(.maskAlternate)
            return decoded
        }
    }

    struct DirectInputEvent: Sendable {
        enum Kind: Sendable {
            case keyDown(Keycode)
            case keyUp(Keycode)
            case flagsChanged
            /// physical Caps Lock press; `isOn` is the Mac lock state reported with it
            case capsLock(isOn: Bool)
        }

        static let capsLockVirtualKey: UInt16 = 0x39

        let kind: Kind
        var modifiers: KeyboardModifiers
        var releaseShortcutPressed: Bool

        init?(type: CGEventType, event: CGEvent) {
            let flags = event.flags
            modifiers = KeyboardModifiers(eventFlags: flags)
            releaseShortcutPressed = flags.contains(.maskControl) && flags.contains(.maskAlternate)

            switch type {
            case .keyDown:
                if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
                guard let key = Keycode(macVirtualKey: UInt16(event.getIntegerValueField(.keyboardEventKeycode))) else { return nil }
                kind = .keyDown(key)
            case .keyUp:
                guard let key = Keycode(macVirtualKey: UInt16(event.getIntegerValueField(.keyboardEventKeycode))) else { return nil }
                kind = .keyUp(key)
            case .flagsChanged:
                if UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == Self.capsLockVirtualKey {
                    kind = .capsLock(isOn: flags.contains(.maskAlphaShift))
                } else {
                    kind = .flagsChanged
                }
            default:
                // Pointer and other events are never decoded, so they cannot reach the HID path.
                return nil
            }
        }
    }

    private extension KeyboardModifiers {
        init(eventFlags flags: CGEventFlags) {
            self.init()
            if flags.contains(.maskControl) { insert(.leftCtrl) }
            if flags.contains(.maskShift) { insert(.leftShift) }
            if flags.contains(.maskAlternate) { insert(.leftAlt) }
            if flags.contains(.maskCommand) { insert(.leftGUI) }
        }
    }

    private extension Keycode {
        init?(macVirtualKey key: UInt16) {
            guard let code = Self.macVirtualKeys[key] else { return nil }
            self = code
        }

        static let macVirtualKeys: [UInt16: Keycode] = [
            0x00: .a, 0x0B: .b, 0x08: .c, 0x02: .d, 0x0E: .e, 0x03: .f, 0x05: .g, 0x04: .h,
            0x22: .i, 0x26: .j, 0x28: .k, 0x25: .l, 0x2E: .m, 0x2D: .n, 0x1F: .o, 0x23: .p,
            0x0C: .q, 0x0F: .r, 0x01: .s, 0x11: .t, 0x20: .u, 0x09: .v, 0x0D: .w, 0x07: .x,
            0x10: .y, 0x06: .z,
            0x12: .digit1, 0x13: .digit2, 0x14: .digit3, 0x15: .digit4, 0x17: .digit5,
            0x16: .digit6, 0x1A: .digit7, 0x1C: .digit8, 0x19: .digit9, 0x1D: .digit0,
            0x24: .return, 0x4C: .return,
            0x35: .escape, 0x33: .backspace, 0x30: .tab, 0x31: .space,
            0x1B: .minus, 0x18: .equal, 0x21: .leftBracket, 0x1E: .rightBracket,
            0x2A: .backslash, 0x29: .semicolon, 0x27: .quote, 0x32: .grave,
            0x2B: .comma, 0x2F: .period, 0x2C: .slash, 0x39: .capsLock,
            0x7A: .f1, 0x78: .f2, 0x63: .f3, 0x76: .f4, 0x60: .f5, 0x61: .f6,
            0x62: .f7, 0x64: .f8, 0x65: .f9, 0x6D: .f10, 0x67: .f11, 0x6F: .f12,
            0x7C: .rightArrow, 0x7B: .leftArrow, 0x7D: .downArrow, 0x7E: .upArrow,
            0x75: .deleteForward
        ]
    }

#elseif os(iOS)
    import CoreGraphics
    import Foundation
    import GameController
    import SwiftUI
    import UIKit

    @MainActor
    final class DirectInputController: ObservableObject {
        @Published private(set) var isCapturing = false
        @Published private(set) var lastError: String?
        @Published private(set) var hasInputDevice = false

        private var sendKeyboard: ((KeyboardReport) -> Void)?
        private var sendMouse: ((MouseReport) -> Void)?
        private var pressedKeys: Set<Keycode> = []
        private var pressedMouseButtons: MouseButtons = []
        private var modifiers: KeyboardModifiers = []
        private var observers: [NSObjectProtocol] = []

        // GCMouse deltas are in points; tune on-device
        private static let sensitivity: CGFloat = 1
        private static let scrollSensitivity: CGFloat = 1

        init() {
            refreshDevicePresence()
            observeDevices()
        }

        func start(_ hid: HIDInput) {
            start(sendKeyboard: hid.sendKeyboard, sendMouse: hid.sendMouse)
        }

        func start(
            sendKeyboard: @escaping (KeyboardReport) -> Void,
            sendMouse: @escaping (MouseReport) -> Void
        ) {
            stop()
            guard hasInputDevice else { return }

            self.sendKeyboard = sendKeyboard
            self.sendMouse = sendMouse
            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            lastError = nil

            attachHandlers()
            isCapturing = true
        }

        func stop() {
            detachHandlers()
            if isCapturing {
                sendKeyboard?(.zero)
                sendMouse?(.zero)
            }
            pressedKeys.removeAll()
            pressedMouseButtons = []
            modifiers = []
            sendKeyboard = nil
            sendMouse = nil
            isCapturing = false
        }

        private func attachHandlers() {
            if let keyboard = GCKeyboard.coalesced {
                keyboard.handlerQueue = .main
                keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
                    let raw = keyCode.rawValue
                    Task { @MainActor in self?.handleKey(raw: raw, pressed: pressed) }
                }
            }
            if let mouse = GCMouse.current {
                mouse.handlerQueue = .main
                let input = mouse.mouseInput
                input?.mouseMovedHandler = { [weak self] _, dx, dy in
                    Task { @MainActor in self?.handleMove(dx: dx, dy: dy) }
                }
                input?.leftButton.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handleButton(.left, pressed) }
                }
                input?.rightButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handleButton(.right, pressed) }
                }
                input?.middleButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                    Task { @MainActor in self?.handleButton(.middle, pressed) }
                }
                input?.scroll.valueChangedHandler = { [weak self] _, _, y in
                    Task { @MainActor in self?.handleScroll(y) }
                }
            }
        }

        private func detachHandlers() {
            GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
            if let input = GCMouse.current?.mouseInput {
                input.mouseMovedHandler = nil
                input.leftButton.pressedChangedHandler = nil
                input.rightButton?.pressedChangedHandler = nil
                input.middleButton?.pressedChangedHandler = nil
                input.scroll.valueChangedHandler = nil
            }
        }

        /// GCKeyCode raw values are HID usage IDs; 0xE0...0xE7 are modifier keys
        private func handleKey(raw: Int, pressed: Bool) {
            if (0xE0 ... 0xE7).contains(raw) {
                let mod = KeyboardModifiers(rawValue: UInt8(1) << UInt8(raw - 0xE0))
                if pressed { modifiers.insert(mod) } else { modifiers.remove(mod) }
            } else if let key = Keycode(rawValue: UInt8(truncatingIfNeeded: raw)) {
                if pressed { pressedKeys.insert(key) } else { pressedKeys.remove(key) }
            } else {
                return
            }
            if releaseComboHeld {
                stop()
                return
            }
            sendKeyboard?(KeyboardReport(modifiers: modifiers, keys: Array(pressedKeys.prefix(6))))
        }

        private var releaseComboHeld: Bool {
            !modifiers.isDisjoint(with: [.leftCtrl, .rightCtrl]) &&
                !modifiers.isDisjoint(with: [.leftAlt, .rightAlt])
        }

        private func handleMove(dx: Float, dy: Float) {
            let mx = HIDInput.clamp(CGFloat(dx) * Self.sensitivity)
            let my = HIDInput.clamp(CGFloat(-dy) * Self.sensitivity) // GC y is up-positive, HID is down-positive
            guard mx != 0 || my != 0 else { return }
            sendMouse?(MouseReport(buttons: pressedMouseButtons, dX: mx, dY: my))
        }

        private func handleButton(_ button: MouseButtons, _ pressed: Bool) {
            if pressed { pressedMouseButtons.insert(button) } else { pressedMouseButtons.remove(button) }
            sendMouse?(MouseReport(buttons: pressedMouseButtons))
        }

        private func handleScroll(_ y: Float) {
            let wheel = HIDInput.clamp(CGFloat(y) * Self.scrollSensitivity)
            guard wheel != 0 else { return }
            sendMouse?(MouseReport(buttons: pressedMouseButtons, wheel: wheel))
            sendMouse?(MouseReport(buttons: pressedMouseButtons))
        }

        private func refreshDevicePresence() {
            hasInputDevice = GCKeyboard.coalesced != nil || GCMouse.current != nil
        }

        private func observeDevices() {
            let names: [Notification.Name] = [
                .GCKeyboardDidConnect, .GCKeyboardDidDisconnect, .GCMouseDidConnect, .GCMouseDidDisconnect
            ]
            for name in names {
                let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        self.refreshDevicePresence()
                        if self.isCapturing { self.attachHandlers() }
                        if !self.hasInputDevice { self.stop() }
                    }
                }
                observers.append(token)
            }
        }
    }

    /// iPadOS pointer lock hides system pointer so GameController receives raw deltas
    struct PointerLockHost: UIViewControllerRepresentable {
        var locked: Bool

        func makeUIViewController(context: Context) -> PointerLockController {
            PointerLockController()
        }

        func updateUIViewController(_ controller: PointerLockController, context: Context) {
            controller.locked = locked
        }
    }

    final class PointerLockController: UIViewController {
        var locked = false {
            didSet {
                guard locked != oldValue else { return }
                setNeedsUpdateOfPrefersPointerLocked()
            }
        }

        override var prefersPointerLocked: Bool {
            locked
        }
    }
#endif
