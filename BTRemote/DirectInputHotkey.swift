#if os(macOS)
    import AppKit
    import Carbon
    import CoreGraphics

    /// Physical macOS keycode plus the four standard modifiers. No HID layout changes.
    struct DirectInputHotkey: Codable, Equatable, Sendable {
        let keyCode: UInt16
        let modifiers: UInt64

        static let modifierMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        static let modifierKeys: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

        init(keyCode: UInt16, flags: CGEventFlags) {
            self.keyCode = keyCode
            modifiers = flags.intersection(Self.modifierMask).rawValue
        }

        var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

        func matches(keyCode: UInt16, flags: CGEventFlags) -> Bool {
            self.keyCode == keyCode && self.modifiers == flags.intersection(Self.modifierMask).rawValue
        }

        var carbonModifiers: UInt32 {
            var result: UInt32 = 0
            if flags.contains(.maskControl) { result |= UInt32(controlKey) }
            if flags.contains(.maskAlternate) { result |= UInt32(optionKey) }
            if flags.contains(.maskShift) { result |= UInt32(shiftKey) }
            if flags.contains(.maskCommand) { result |= UInt32(cmdKey) }
            return result
        }

        var validationError: String? {
            guard !Self.modifierKeys.contains(keyCode), keyCode <= 0x7E else {
                return String(localized: "shortcut.requires_key")
            }
            guard !flags.intersection([.maskControl, .maskAlternate, .maskCommand]).isEmpty,
                  modifiers == flags.intersection(Self.modifierMask).rawValue else {
                return String(localized: "shortcut.requires_modifier")
            }
            if flags.contains(.maskControl), flags.contains(.maskAlternate) {
                return String(localized: "shortcut.emergency_conflict")
            }
            // Keep remote input switching, app control, and common macOS bindings available.
            let reserved: [(UInt16, CGEventFlags)] = [
                (49, .maskControl), (49, [.maskControl, .maskShift]),
                (49, .maskCommand), (49, [.maskCommand, .maskAlternate]),
                (48, .maskCommand), (50, .maskCommand),
                (12, .maskCommand), (13, .maskCommand), (4, .maskCommand),
                (20, [.maskCommand, .maskShift]), (21, [.maskCommand, .maskShift]),
                (23, [.maskCommand, .maskShift]), (53, [.maskCommand, .maskAlternate])
            ]
            if reserved.contains(where: { matches(keyCode: $0.0, flags: $0.1) }) {
                return String(localized: "shortcut.reserved")
            }
            return nil
        }

        /// Includes user-configured macOS symbolic hotkeys, without changing system settings.
        var systemConflict: Bool {
            var hotkeys: Unmanaged<CFArray>?
            guard CopySymbolicHotKeys(&hotkeys) == noErr,
                  let array = hotkeys?.takeRetainedValue() as? [[String: Any]] else { return false }
            return array.contains { item in
                (item[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
                    (item[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint16Value == keyCode &&
                    (item[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == carbonModifiers
            }
        }

        var displayString: String {
            var text = ""
            if flags.contains(.maskControl) { text += "⌃" }
            if flags.contains(.maskAlternate) { text += "⌥" }
            if flags.contains(.maskShift) { text += "⇧" }
            if flags.contains(.maskCommand) { text += "⌘" }
            let labels: [UInt16: String] = [
                0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
                12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
                22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
                32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
                42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
                51: "⌫", 53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑",
                122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
                101: "F9", 109: "F10", 103: "F11", 111: "F12"
            ]
            return text + (labels[keyCode] ?? "Key \(keyCode)")
        }
    }

    /// Tracks one physical activation across Carbon and the capture tap.
    struct DirectInputShortcutPress {
        private(set) var isDown = false
        mutating func press() -> Bool {
            guard !isDown else { return false }
            isDown = true
            return true
        }
        mutating func release() { isDown = false }
    }

    /// Removes the starting shortcut's key and modifiers until each is released.
    struct DirectInputShortcutSuppression {
        private var keyCode: UInt16?
        private var modifiers: CGEventFlags = []

        init(_ hotkey: DirectInputHotkey? = nil) {
            keyCode = hotkey?.keyCode
            modifiers = hotkey?.flags ?? []
        }

        mutating func filter(type: CGEventType, keyCode: UInt16, flags: CGEventFlags) -> (swallow: Bool, flags: CGEventFlags) {
            modifiers.formIntersection(flags)
            let swallow = (type == .keyDown || type == .keyUp) && keyCode == self.keyCode
            if type == .keyUp, keyCode == self.keyCode { self.keyCode = nil }
            return (swallow, flags.subtracting(modifiers))
        }
    }
#endif
