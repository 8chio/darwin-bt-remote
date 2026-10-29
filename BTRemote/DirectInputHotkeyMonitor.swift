#if os(macOS)
    import AppKit
    import Carbon

    /// Carbon registration detects conflicts and consumes the shortcut while capture is idle.
    /// Active capture detects it in its own CGEvent tap, before Carbon can see it.
    @MainActor
    final class DirectInputHotkeyMonitor {
        private var registration: EventHotKeyRef?
        private var handler: EventHandlerRef?
        private var globalKeyUp: Any?
        private var localKeyUp: Any?
        private var hotkey: DirectInputHotkey?
        private var onToggle: (() -> Void)?
        private var press = DirectInputShortcutPress()
        private var nextID: UInt32 = 0
        private var activeID: UInt32 = 0
        private static let signature: OSType = 0x55444354 // UDCT

        /// Keep the previous registration if the proposed replacement is unavailable.
        func register(_ hotkey: DirectInputHotkey, onToggle: @escaping () -> Void) -> OSStatus {
            if self.hotkey == hotkey, registration != nil {
                self.onToggle = onToggle
                return noErr
            }
            if handler == nil {
                var types = [
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                    EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
                ]
                let status = InstallEventHandler(
                    GetApplicationEventTarget(), Self.callback, types.count, &types,
                    Unmanaged.passUnretained(self).toOpaque(), &handler
                )
                guard status == noErr else { return status }
            }
            nextID &+= 1
            let identifier = EventHotKeyID(signature: Self.signature, id: nextID)
            var proposed: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotkey.keyCode), hotkey.carbonModifiers, identifier,
                                            GetApplicationEventTarget(), 0, &proposed)
            guard status == noErr else { return status }
            if let registration { UnregisterEventHotKey(registration) }
            registration = proposed
            activeID = nextID
            self.hotkey = hotkey
            self.onToggle = onToggle
            press.release()
            installKeyUpMonitors()
            return noErr
        }

        /// Returns false for duplicate/repeat activations from either input path.
        func capturedPress() -> Bool { press.press() }
        func keyReleased(_ keyCode: UInt16) {
            if hotkey?.keyCode == keyCode { press.release() }
        }

        func stop() {
            if let registration { UnregisterEventHotKey(registration) }
            if let handler { RemoveEventHandler(handler) }
            if let globalKeyUp { NSEvent.removeMonitor(globalKeyUp) }
            if let localKeyUp { NSEvent.removeMonitor(localKeyUp) }
            registration = nil
            handler = nil
            globalKeyUp = nil
            localKeyUp = nil
            hotkey = nil
            onToggle = nil
            press.release()
        }

        private func installKeyUpMonitors() {
            guard globalKeyUp == nil, localKeyUp == nil else { return }
            // Key-up after a captured stop may not produce a Carbon release, since
            // the corresponding down was consumed by the capture tap.
            globalKeyUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
                let code = event.keyCode
                // AppKit invokes event monitor handlers on the main thread.
                MainActor.assumeIsolated { self?.keyReleased(code) }
            }
            localKeyUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                let code = event.keyCode
                MainActor.assumeIsolated { self?.keyReleased(code) }
                return event
            }
        }

        private nonisolated static let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            let kind = GetEventKind(event)
            let monitor = Unmanaged<DirectInputHotkeyMonitor>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated {
                guard identifier.signature == signature, identifier.id == monitor.activeID else {
                    return OSStatus(eventNotHandledErr)
                }
                if kind == UInt32(kEventHotKeyReleased) {
                    monitor.press.release()
                } else if monitor.press.press() {
                    monitor.onToggle?()
                }
                return noErr
            }
        }
    }
#endif
