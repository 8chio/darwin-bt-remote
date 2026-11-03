import AppKit
import Carbon
import Foundation

// Standalone harness: actual shortcut/decoder/manager code, no OS input injection.
enum AccessibilityPermission { static let isTrusted = false }
enum L10n {
    enum DirectInput {
        static let captureFailedString = "Capture failed"
        static let releaseHintString = "Control + Option releases capture"
    }
    enum RemoteKeyboard {
        static let statusTitleString = "Keyboard → Device"
        static let returnToMacString = "Return Keyboard to Mac"
    }
}
struct HIDInput {
    var sendKeyboard: (KeyboardReport) -> Void = { _ in }
    var sendMouse: (MouseReport) -> Void = { _ in }
    var isConnected = true
}

@MainActor
final class ReportLog {
    var keyboard: [KeyboardReport] = []
    var mouse: [MouseReport] = []
    var hid: HIDInput {
        HIDInput(sendKeyboard: { report in MainActor.assumeIsolated { self.keyboard.append(report) } },
                 sendMouse: { report in MainActor.assumeIsolated { self.mouse.append(report) } })
    }
}

/// Deterministic clock and release scheduler for the Caps Lock tap.
@MainActor
final class ManualClock {
    var now: UInt64 = 10_000_000_000
    var delays: [UInt64] = []
    var cancels = 0
    private var work: (@MainActor () -> Void)?
    var hasPending: Bool { work != nil }
    func schedule(_ delay: UInt64, _ work: @escaping @MainActor () -> Void) -> @MainActor () -> Void {
        delays.append(delay)
        self.work = work
        return { self.cancels += 1; self.work = nil }
    }
    func fire() {
        let pending = work
        work = nil
        pending?()
    }
    func advance(milliseconds: UInt64) { now += milliseconds * 1_000_000 }
}

@MainActor
final class MemoryPreferences: DirectInputShortcutPreferences {
    private var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value as? Data }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}

@MainActor
final class TestMonitor: DirectInputShortcutMonitoring {
    var onToggle: (() -> Void)?
    var binding: DirectInputHotkey?
    var refused: DirectInputHotkey?
    private var press = DirectInputShortcutPress()
    func register(_ hotkey: DirectInputHotkey, onToggle: @escaping () -> Void) -> OSStatus {
        if hotkey == refused { return OSStatus(eventHotKeyExistsErr) }
        binding = hotkey
        self.onToggle = onToggle
        return noErr
    }
    func stop() { binding = nil; onToggle = nil; press.release() }
    func capturedPress() -> Bool { press.press() }
    func keyReleased(_ code: UInt16) { if code == binding?.keyCode { press.release() } }
    func globalPress() { if press.press() { onToggle?() } }
}

@MainActor
final class TestCapture: DirectInputShortcutTarget {
    var isCapturing = false
    var toggleHotkey: DirectInputHotkey?
    var onToggleShortcut: (() -> Void)?
    var onShortcutKeyUp: ((UInt16) -> Void)?
    var startCount = 0
    var stopCount = 0
    var suppression: DirectInputHotkey?
    var failStart = false
    func start(_ hid: HIDInput, suppressing hotkey: DirectInputHotkey?) {
        startCount += 1
        suppression = hotkey
        isCapturing = !failStart
    }
    func stop() { if isCapturing { stopCount += 1 }; isCapturing = false }
}

@main
struct DirectInputShortcutTests {
    @MainActor
    static func main() throws {
        let binding = DirectInputHotkey(keyCode: 2, flags: [.maskCommand, .maskShift])
        let replacement = DirectInputHotkey(keyCode: 3, flags: [.maskCommand, .maskShift])
        precondition(binding.validationError == nil)
        precondition(binding.matches(keyCode: 2, flags: [.maskCommand, .maskShift, .maskAlphaShift]))
        precondition(!binding.matches(keyCode: 2, flags: [.maskCommand, .maskShift, .maskControl]))
        for invalid in [DirectInputHotkey(keyCode: 0, flags: []),
                        DirectInputHotkey(keyCode: 57, flags: .maskCommand),
                        DirectInputHotkey(keyCode: 49, flags: .maskControl),
                        DirectInputHotkey(keyCode: 49, flags: .maskCommand),
                        DirectInputHotkey(keyCode: 2, flags: [.maskControl, .maskAlternate])] {
            precondition(invalid.validationError != nil)
        }
        let roundTrip = try JSONDecoder().decode(DirectInputHotkey.self, from: JSONEncoder().encode(binding))
        precondition(roundTrip == binding)
        testSuppression(binding)
        testEventPaths(binding)
        testKeyboardOnlyCapture()
        testKeyboardRouter()
        testCapsLock()
        testCaptureStartFailure()

        let defaults = MemoryPreferences()
        let monitor = TestMonitor(), capture = TestCapture()
        let manager = DirectInputShortcutManager(defaults: defaults, monitor: monitor, systemConflict: { _ in false })
        var connected = true
        manager.attach(directInput: capture) { HIDInput(isConnected: connected) }
        precondition(manager.hotkey == nil && !manager.isMonitoring)
        manager.toggle() // Existing UI route works with no shortcut.
        precondition(capture.isCapturing && capture.suppression == nil)
        manager.toggle()
        precondition(!capture.isCapturing)
        precondition(manager.setHotkey(binding) && manager.isMonitoring)
        // 20 full start/stop cycles, both sources and duplicate/held presses.
        let initialStarts = capture.startCount, initialStops = capture.stopCount
        for _ in 0 ..< 20 {
            monitor.globalPress()
            monitor.globalPress()
            precondition(capture.isCapturing && capture.suppression == binding)
            capture.onShortcutKeyUp?(binding.keyCode)
            capture.onToggleShortcut?()
            capture.onToggleShortcut?()
            precondition(!capture.isCapturing)
            monitor.keyReleased(binding.keyCode)
        }
        precondition(capture.startCount - initialStarts == 20)
        precondition(capture.stopCount - initialStops == 20)
        // Failed capture may be retried once the physical key is released.
        capture.failStart = true
        monitor.globalPress()
        precondition(!capture.isCapturing)
        monitor.keyReleased(binding.keyCode)
        capture.failStart = false
        connected = false
        let previousStarts = capture.startCount
        monitor.globalPress()
        precondition(capture.startCount == previousStarts && manager.lastError != nil)
        monitor.keyReleased(binding.keyCode)
        connected = true
        monitor.globalPress()
        precondition(capture.isCapturing)
        capture.onShortcutKeyUp?(binding.keyCode)
        capture.onToggleShortcut?()
        monitor.keyReleased(binding.keyCode)
        // Failed replacement keeps the live and persisted previous binding.
        monitor.refused = replacement
        precondition(!manager.setHotkey(replacement))
        precondition(manager.hotkey == binding && monitor.binding == binding && manager.isMonitoring)
        manager.suspendMonitoring()
        precondition(!manager.isMonitoring)
        precondition(!manager.setHotkey(replacement))
        precondition(manager.isMonitoring && monitor.binding == binding)
        let reloaded = DirectInputShortcutManager(defaults: defaults, monitor: TestMonitor(), systemConflict: { _ in false })
        precondition(reloaded.hotkey == binding)
        // A macOS symbolic conflict is rejected without overwriting persisted settings.
        let conflicted = DirectInputShortcutManager(defaults: defaults, monitor: TestMonitor(), systemConflict: { _ in true })
        precondition(!conflicted.setHotkey(replacement) && conflicted.hotkey == binding)
        manager.toggle()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        precondition(!capture.isCapturing && !manager.isMonitoring && capture.onToggleShortcut == nil)
        precondition(manager.setHotkey(nil))
        precondition(defaults.data(forKey: AppSettings.directInputToggleHotkeyKey) == nil)
        defaults.set(Data("invalid".utf8), forKey: AppSettings.directInputToggleHotkeyKey)
        let corrupt = DirectInputShortcutManager(defaults: defaults, monitor: TestMonitor(), systemConflict: { _ in false })
        precondition(corrupt.hotkey == nil && corrupt.lastError != nil)
        defaults.removeObject(forKey: AppSettings.directInputToggleHotkeyKey)
        reloaded.reload()
        precondition(reloaded.hotkey == nil && !reloaded.isMonitoring)
        if CommandLine.arguments.contains("--carbon-smoke") { carbonSmoke() }
        print("PASS: matching/validation, 20 toggle cycles, repeats, UI without shortcut, persistence, conflicts/rollback, recorder pause/resume, failed start, reconnect, shutdown/reset")
    }

    @MainActor
    static func carbonSmoke() {
        let first = DirectInputHotkeyMonitor(), second = DirectInputHotkeyMonitor()
        defer { first.stop(); second.stop() }
        let candidate = DirectInputHotkey(keyCode: 80, flags: [.maskCommand, .maskShift]) // ⌘⇧F19
        let status = first.register(candidate, onToggle: {})
        guard status == noErr else {
            print("SKIP: real Carbon registration unavailable, status=\(status)")
            return
        }
        let conflict = second.register(candidate, onToggle: {})
        precondition(conflict == OSStatus(eventHotKeyExistsErr))
        precondition(first.register(candidate, onToggle: {}) == noErr)
        print("PASS: real Carbon registration, duplicate conflict, same-binding reuse, cleanup")
    }

    static func testSuppression(_ binding: DirectInputHotkey) {
        var suppression = DirectInputShortcutSuppression(binding)
        var result = suppression.filter(type: .keyDown, keyCode: binding.keyCode, flags: binding.flags)
        precondition(result.swallow && result.flags.isEmpty)
        result = suppression.filter(type: .mouseMoved, keyCode: 0, flags: binding.flags)
        precondition(!result.swallow && result.flags.isEmpty)
        result = suppression.filter(type: .keyUp, keyCode: binding.keyCode, flags: binding.flags)
        precondition(result.swallow)
        result = suppression.filter(type: .flagsChanged, keyCode: 55, flags: .maskShift)
        precondition(result.flags.isEmpty)
        _ = suppression.filter(type: .flagsChanged, keyCode: 56, flags: [])
        result = suppression.filter(type: .keyDown, keyCode: 0, flags: .maskShift)
        precondition(!result.swallow && result.flags == .maskShift)
        // Fresh UI-start capture has no suppression of real user modifiers.
        suppression = DirectInputShortcutSuppression()
        result = suppression.filter(type: .keyDown, keyCode: 49, flags: .maskControl)
        precondition(!result.swallow && result.flags == .maskControl)
    }

    static func testEventPaths(_ binding: DirectInputHotkey) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: binding.keyCode, keyDown: true)!
        event.flags = binding.flags
        precondition(DirectInputShortcutEvent(type: .keyDown, event: event).isToggle(hotkey: binding))
        precondition(!DirectInputShortcutEvent(type: .keyUp, event: event).isToggle(hotkey: binding))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        precondition(!DirectInputShortcutEvent(type: .keyDown, event: event).isToggle(hotkey: binding))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        event.setIntegerValueField(.keyboardEventKeycode, value: 49)
        event.flags = .maskControl
        let input = DirectInputShortcutEvent(type: .keyDown, event: event)
        precondition(!input.isToggle(hotkey: binding))
        guard let space = input.event(flags: input.flags), case .keyDown(.space) = space.kind else { preconditionFailure() }
        precondition(space.modifiers == .leftCtrl)
        guard let up = DirectInputEvent(type: .keyUp, event: event), case .keyUp(.space) = up.kind else { preconditionFailure() }
        event.flags = []
        event.setIntegerValueField(.keyboardEventKeycode, value: 0)
        guard let letter = DirectInputEvent(type: .keyDown, event: event), case .keyDown(.a) = letter.kind else { preconditionFailure() }
        event.flags = [.maskControl, .maskAlternate]
        precondition(DirectInputEvent(type: .flagsChanged, event: event)?.releaseShortcutPressed == true)
        event.flags = []
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        precondition(DirectInputEvent(type: .keyDown, event: event) == nil) // auto-repeat is not a new press
        print("PASS: captured shortcut filtering, starting chord suppression, A/Ctrl+Space/emergency/auto-repeat decoders")
    }

    /// UC-001: only keyboard events are tapped; pointer events are never decoded or consumed.
    static func testKeyboardOnlyCapture() {
        let pointerTypes: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp,
            .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
            .tabletPointer, .tabletProximity
        ]
        let mask = DirectInputController.eventMask
        for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            precondition(mask & (CGEventMask(1) << CGEventMask(type.rawValue)) != 0)
        }
        for type in pointerTypes {
            precondition(mask & (CGEventMask(1) << CGEventMask(type.rawValue)) == 0, "pointer type \(type.rawValue) in mask")
            precondition(!DirectInputController.capturedEventTypes.contains(type))
        }
        // Gesture/magnify/swipe event types (29-31) are not in the mask either.
        for raw: UInt32 in [29, 30, 31] { precondition(mask & (CGEventMask(1) << CGEventMask(raw)) == 0) }
        precondition(mask == (CGEventMask(1) << 10 | CGEventMask(1) << 11 | CGEventMask(1) << 12))

        let mouse = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)!
        mouse.setIntegerValueField(.mouseEventDeltaX, value: 8)
        mouse.setIntegerValueField(.mouseEventDeltaY, value: -5)
        for type in pointerTypes { precondition(DirectInputEvent(type: type, event: mouse) == nil) }
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 2, wheel2: 0, wheel3: 0)!
        precondition(DirectInputEvent(type: .scrollWheel, event: wheel) == nil)
        precondition(DirectInputShortcutEvent(type: .leftMouseDown, event: mouse).event(flags: []) == nil)
        print("PASS: keyboard-only event mask; mouse move/click/drag/scroll/tablet/gesture never decoded")
    }

    /// Key press/release, modifiers and neutral reset; the router has no mouse output at all.
    @MainActor
    static func testKeyboardRouter() {
        let log = ReportLog(), clock = ManualClock()
        let router = DirectInputKeyboardRouter(send: log.hid.sendKeyboard, schedule: clock.schedule, now: { clock.now })
        let a = keyEvent(.keyDown, 0x00, flags: .maskShift)
        router.handle(a)
        precondition(log.keyboard.last == KeyboardReport(modifiers: .leftShift, keys: [.a]))
        router.handle(keyEvent(.keyDown, 0x01, flags: [.maskShift, .maskCommand]))
        precondition(log.keyboard.last == KeyboardReport(modifiers: [.leftShift, .leftGUI], keys: [.a, .s]))
        router.handle(keyEvent(.keyUp, 0x00, flags: [.maskShift, .maskCommand]))
        precondition(log.keyboard.last == KeyboardReport(modifiers: [.leftShift, .leftGUI], keys: [.s]))
        // Modifier-only change (Control/Option/Shift/Command) is forwarded as a flagsChanged report.
        router.handle(keyEvent(.flagsChanged, 0x3B, flags: [.maskControl]))
        precondition(log.keyboard.last == KeyboardReport(modifiers: .leftCtrl, keys: [.s]))
        // More than six keys never overflows the boot report.
        for code: UInt16 in [0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08] { router.handle(keyEvent(.keyDown, code, flags: [])) }
        precondition(log.keyboard.last!.keys.count == 6 && log.keyboard.last!.data.count == 8)
        // Stop/disconnect/termination path: one neutral report and empty state.
        router.reset()
        precondition(log.keyboard.last == .zero && log.keyboard.last!.data == Data(repeating: 0, count: 8))
        precondition(router.pressedKeys.isEmpty && router.modifiers.isEmpty && !router.isCapsLockHeld)
        precondition(log.mouse.isEmpty)
        print("PASS: router key down/up, modifiers, 6-key limit, neutral reset, no mouse reports")
    }

    /// UC-003: Caps Lock flagsChanged -> HID 0x39 press, timed release, duplicate and stuck-key protection.
    @MainActor
    static func testCapsLock() {
        // macOS delivers Caps Lock as flagsChanged keycode 0x39 with the new lock state.
        let on = keyEvent(.flagsChanged, 0x39, flags: .maskAlphaShift)
        let off = keyEvent(.flagsChanged, 0x39, flags: [])
        guard case .capsLock(isOn: true) = on.kind, case .capsLock(isOn: false) = off.kind else { preconditionFailure() }
        precondition(on.modifiers.isEmpty) // Caps Lock is not forwarded as a modifier bit
        // A Shift change is still a plain modifier change, not Caps Lock.
        guard case .flagsChanged = keyEvent(.flagsChanged, 0x38, flags: .maskShift).kind else { preconditionFailure() }

        let log = ReportLog(), clock = ManualClock()
        let router = DirectInputKeyboardRouter(send: log.hid.sendKeyboard, schedule: clock.schedule, now: { clock.now })
        router.handle(on)
        precondition(log.keyboard == [KeyboardReport(keys: [.capsLock])])
        precondition(log.keyboard[0].data == Data([0, 0, 0x39, 0, 0, 0, 0, 0]))
        precondition(router.isCapsLockHeld && clock.delays == [DirectInputKeyboardRouter.capsLockHoldNanoseconds])
        clock.fire()
        precondition(log.keyboard == [KeyboardReport(keys: [.capsLock]), .zero] && !router.isCapsLockHeld)

        // Duplicate delivery / release echo with the same lock state inside the window is ignored.
        clock.advance(milliseconds: 100)
        router.handle(on)
        precondition(log.keyboard.count == 2 && !clock.hasPending)
        // Next physical press toggles the Mac lock state: accepted even when quick.
        clock.advance(milliseconds: 50)
        router.handle(off)
        precondition(log.keyboard.count == 3 && log.keyboard[2].keys == [.capsLock])
        clock.fire()
        precondition(log.keyboard.count == 4 && log.keyboard[3] == .zero)
        // If macOS does not toggle its lock state (input-source switching), a later press still counts.
        clock.advance(milliseconds: 300)
        router.handle(off)
        precondition(log.keyboard.count == 5 && log.keyboard[4].keys == [.capsLock])
        clock.fire()

        // Caps Lock while typing keeps the other keys and modifiers in the same report.
        clock.advance(milliseconds: 300)
        router.handle(keyEvent(.keyDown, 0x00, flags: .maskShift))
        router.handle(keyEvent(.flagsChanged, 0x39, flags: [.maskAlphaShift, .maskShift]))
        precondition(log.keyboard.last == KeyboardReport(modifiers: .leftShift, keys: [.capsLock, .a]))
        clock.fire()
        precondition(log.keyboard.last == KeyboardReport(modifiers: .leftShift, keys: [.a]))
        router.handle(keyEvent(.keyUp, 0x00, flags: []))

        // Stopping during the tap cancels the pending release and leaves nothing pressed.
        clock.advance(milliseconds: 300)
        router.handle(off)
        precondition(router.isCapsLockHeld && clock.hasPending)
        let cancelsBefore = clock.cancels
        router.reset()
        precondition(clock.cancels == cancelsBefore + 1 && !clock.hasPending)
        precondition(log.keyboard.last == .zero && !router.isCapsLockHeld)
        let sent = log.keyboard.count
        clock.fire()
        precondition(log.keyboard.count == sent)
        // A fresh session does not inherit the previous duplicate window.
        router.handle(off)
        precondition(log.keyboard.last?.keys == [.capsLock])
        router.reset()

        // Every press report is followed by exactly one release report (no stuck 0x39).
        let presses = log.keyboard.filter { $0.keys.contains(.capsLock) }.count
        let releases = zip(log.keyboard, log.keyboard.dropFirst()).filter { $0.keys.contains(.capsLock) && !$1.keys.contains(.capsLock) }.count
        precondition(presses == releases && !log.keyboard.last!.keys.contains(.capsLock))

        var filter = DirectInputCapsLockFilter()
        precondition(filter.accept(isOn: true, at: 0))
        precondition(!filter.accept(isOn: true, at: DirectInputCapsLockFilter.duplicateWindowNanoseconds - 1))
        precondition(filter.accept(isOn: false, at: 1))
        precondition(filter.accept(isOn: false, at: 1 + DirectInputCapsLockFilter.duplicateWindowNanoseconds))
        precondition(log.mouse.isEmpty)
        print("PASS: Caps Lock flagsChanged -> HID 0x39 press/release, duplicate filter, typing combo, cancel on stop")
    }

    /// UC-004: a failed start never takes the Mac keyboard and leaves the host neutral.
    @MainActor
    static func testCaptureStartFailure() {
        let log = ReportLog()
        let controller = DirectInputController()
        var released = 0
        controller.start(sendKeyboard: log.hid.sendKeyboard, onRelease: { released += 1 })
        precondition(!controller.isCapturing && controller.needsAccessibility && released == 1)
        precondition(log.keyboard == [.zero] && log.mouse.isEmpty)
        controller.start(log.hid)
        precondition(!controller.isCapturing && log.mouse.isEmpty)
        controller.stop()
        controller.stop() // idempotent
        precondition(!controller.isCapturing)
        print("PASS: capture start failure keeps Mac keyboard local, sends neutral report, idempotent stop")
    }

    static func keyEvent(_ type: CGEventType, _ keyCode: UInt16, flags: CGEventFlags) -> DirectInputEvent {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: type != .keyUp)!
        event.flags = flags
        return DirectInputEvent(type: type, event: event)!
    }
}
