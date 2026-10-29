#if os(macOS)
    import AppKit
    import Combine
    import os

    @MainActor
    protocol DirectInputShortcutMonitoring: AnyObject {
        func register(_ hotkey: DirectInputHotkey, onToggle: @escaping () -> Void) -> OSStatus
        func stop()
        func capturedPress() -> Bool
        func keyReleased(_ keyCode: UInt16)
    }

    extension DirectInputHotkeyMonitor: DirectInputShortcutMonitoring {}

    @MainActor
    protocol DirectInputShortcutTarget: AnyObject {
        var isCapturing: Bool { get }
        var toggleHotkey: DirectInputHotkey? { get set }
        var onToggleShortcut: (() -> Void)? { get set }
        var onShortcutKeyUp: ((UInt16) -> Void)? { get set }
        func start(_ hid: HIDInput, suppressing hotkey: DirectInputHotkey?)
        func stop()
    }

    extension DirectInputController: DirectInputShortcutTarget {}

    @MainActor
    protocol DirectInputShortcutPreferences {
        func data(forKey key: String) -> Data?
        func set(_ value: Any?, forKey key: String)
        func removeObject(forKey key: String)
    }

    extension UserDefaults: DirectInputShortcutPreferences {}

    /// Adapted from LiLeoH's manager: persistence, a live HID builder, and one toggle action.
    @MainActor
    final class DirectInputShortcutManager: ObservableObject {
        @Published private(set) var hotkey: DirectInputHotkey?
        @Published private(set) var isMonitoring = false
        @Published private(set) var lastError: String?
        private let log = Logger(subsystem: "io.github.jqssun.btremote", category: "DirectInputShortcut")
        private let defaults: any DirectInputShortcutPreferences
        private let monitor: any DirectInputShortcutMonitoring
        private let systemConflict: (DirectInputHotkey) -> Bool
        private weak var directInput: (any DirectInputShortcutTarget)?
        private var buildHID: (() -> HIDInput)?
        private var suspended = false
        private var terminationObserver: AnyCancellable?

        init(defaults: any DirectInputShortcutPreferences = UserDefaults.standard,
             monitor: any DirectInputShortcutMonitoring = DirectInputHotkeyMonitor(),
             systemConflict: @escaping (DirectInputHotkey) -> Bool = { $0.systemConflict }) {
            self.defaults = defaults
            self.monitor = monitor
            self.systemConflict = systemConflict
            if let data = defaults.data(forKey: AppSettings.directInputToggleHotkeyKey) {
                hotkey = try? JSONDecoder().decode(DirectInputHotkey.self, from: data)
                if hotkey == nil { lastError = String(localized: "shortcut.invalid_saved") }
            }
            terminationObserver = NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.shutdown() } }
        }

        func attach(directInput: any DirectInputShortcutTarget, buildHID: @escaping () -> HIDInput) {
            if let previous = self.directInput, previous !== directInput {
                previous.stop()
                previous.onToggleShortcut = nil
                previous.onShortcutKeyUp = nil
            }
            self.directInput = directInput
            self.buildHID = buildHID
            directInput.onToggleShortcut = { [weak self] in
                guard let self, monitor.capturedPress() else { return }
                toggle(fromShortcut: true)
            }
            directInput.onShortcutKeyUp = { [weak self] in self?.monitor.keyReleased($0) }
            directInput.toggleHotkey = nil
            resumeMonitoring()
        }

        @discardableResult
        func setHotkey(_ proposed: DirectInputHotkey?) -> Bool {
            if let proposed {
                if let error = proposed.validationError {
                    lastError = error
                    if suspended { resumeMonitoring() }
                    return false
                }
                if systemConflict(proposed) {
                    lastError = String(localized: "shortcut.reserved")
                    if suspended { resumeMonitoring() }
                    return false
                }
                let status = register(proposed)
                guard status == noErr else {
                    lastError = registrationError(status)
                    if suspended { resumeMonitoring() }
                    return false
                }
            } else {
                monitor.stop()
            }
            suspended = false
            hotkey = proposed
            directInput?.toggleHotkey = proposed
            isMonitoring = proposed != nil
            lastError = nil
            log.info("binding updated enabled=\(proposed != nil)")
            if let proposed, let data = try? JSONEncoder().encode(proposed) {
                defaults.set(data, forKey: AppSettings.directInputToggleHotkeyKey)
            } else {
                defaults.removeObject(forKey: AppSettings.directInputToggleHotkeyKey)
            }
            return true
        }

        func suspendMonitoring() {
            directInput?.stop()
            suspended = true
            monitor.stop()
            isMonitoring = false
        }

        func resumeMonitoring() {
            suspended = false
            isMonitoring = false
            directInput?.toggleHotkey = nil
            guard let hotkey else { return }
            if let error = hotkey.validationError {
                lastError = error
                monitor.stop()
                return
            }
            guard !systemConflict(hotkey) else {
                lastError = String(localized: "shortcut.reserved")
                monitor.stop()
                return
            }
            let status = register(hotkey)
            isMonitoring = status == noErr
            directInput?.toggleHotkey = isMonitoring ? hotkey : nil
            if status != noErr { lastError = registrationError(status) }
        }

        func reload() {
            directInput?.stop()
            monitor.stop()
            isMonitoring = false
            hotkey = defaults.data(forKey: AppSettings.directInputToggleHotkeyKey)
                .flatMap { try? JSONDecoder().decode(DirectInputHotkey.self, from: $0) }
            directInput?.toggleHotkey = hotkey
            lastError = nil
            resumeMonitoring()
        }

        func toggle(fromShortcut: Bool = false) {
            guard let directInput else { return }
            let wasCapturing = directInput.isCapturing
            if directInput.isCapturing {
                directInput.stop()
            } else if let hid = buildHID?(), hid.isConnected {
                lastError = nil
                directInput.start(hid, suppressing: fromShortcut ? hotkey : nil)
            } else {
                lastError = String(localized: "shortcut.no_host")
            }
            let capturing = directInput.isCapturing
            log.info("toggle shortcut=\(fromShortcut) before=\(wasCapturing) after=\(capturing)")
        }

        func shutdown() {
            log.info("app shutdown: release capture and unregister shortcut")
            directInput?.stop()
            directInput?.onToggleShortcut = nil
            directInput?.onShortcutKeyUp = nil
            monitor.stop()
            isMonitoring = false
            directInput = nil
            buildHID = nil
        }

        private func register(_ hotkey: DirectInputHotkey) -> OSStatus {
            monitor.register(hotkey) { [weak self] in self?.toggle(fromShortcut: true) }
        }

        private func registrationError(_ status: OSStatus) -> String {
            String(format: String(localized: "shortcut.registration_failed"), status)
        }
    }
#endif
