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
}
struct HIDInput {
    var sendKeyboard: (KeyboardReport) -> Void = { _ in }
    var sendMouse: (MouseReport) -> Void = { _ in }
    var isConnected = true
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
        let mouse = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: .zero, mouseButton: .left)!
        mouse.setIntegerValueField(.mouseEventDeltaX, value: 8)
        mouse.setIntegerValueField(.mouseEventDeltaY, value: -5)
        guard let move = DirectInputEvent(type: .mouseMoved, event: mouse), case .mouseMove(8, -5) = move.kind else { preconditionFailure() }
        guard let click = DirectInputEvent(type: .leftMouseDown, event: mouse), case .mouseButton(.left, true) = click.kind else { preconditionFailure() }
        guard let release = DirectInputEvent(type: .leftMouseUp, event: mouse), case .mouseButton(.left, false) = release.kind else { preconditionFailure() }
        let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 2, wheel2: 0, wheel3: 0)!
        guard let scroll = DirectInputEvent(type: .scrollWheel, event: wheel), case .scroll(2) = scroll.kind else { preconditionFailure() }
        print("PASS: captured shortcut filtering, starting chord suppression, existing A/Ctrl+Space/emergency/mouse/click/scroll decoders")
    }
}
