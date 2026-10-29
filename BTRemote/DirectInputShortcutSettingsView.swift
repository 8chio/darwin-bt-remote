#if os(macOS)
    import AppKit
    import SwiftUI

    struct DirectInputShortcutSettingsView: View {
        @EnvironmentObject private var manager: DirectInputShortcutManager
        @StateObject private var recorder = DirectInputShortcutRecorder()

        var body: some View {
            Section(header: Text("shortcut.title"), footer: Text("shortcut.hint")) {
                HStack {
                    Button {
                        recorder.begin(manager: manager)
                    } label: {
                        Text(recorder.isRecording ? String(localized: "shortcut.recording") :
                            (manager.hotkey?.displayString ?? String(localized: "shortcut.none")))
                    }
                    .disabled(recorder.isRecording)
                    if recorder.isRecording {
                        Button("shortcut.cancel") { recorder.cancel() }
                    } else if manager.hotkey != nil {
                        Button("shortcut.clear") { manager.setHotkey(nil) }
                    }
                }
                Text(LocalizedStringKey(manager.isMonitoring ? "shortcut.active" : "shortcut.inactive"))
                    .font(.caption).foregroundStyle(.secondary)
                if let error = manager.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            .onDisappear { recorder.cancel() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                recorder.cancel()
            }
        }
    }

    /// Like LiLeoH's recorder, pause the live binding while recording and consume the key.
    @MainActor
    final class DirectInputShortcutRecorder: ObservableObject {
        @Published private(set) var isRecording = false
        private var monitor: Any?
        private weak var manager: DirectInputShortcutManager?

        func begin(manager: DirectInputShortcutManager) {
            guard !isRecording else { return }
            self.manager = manager
            manager.suspendMonitoring()
            isRecording = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated { self?.capture(event) }
                return nil
            }
        }

        private func capture(_ event: NSEvent) {
            guard !event.isARepeat, !DirectInputHotkey.modifierKeys.contains(event.keyCode) else { return }
            if event.keyCode == 53, event.modifierFlags.intersection([.control, .option, .shift, .command]).isEmpty {
                cancel()
                return
            }
            let proposed = DirectInputHotkey(keyCode: event.keyCode, flags: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            removeMonitor()
            manager?.setHotkey(proposed)
        }

        func cancel() {
            guard isRecording else { return }
            removeMonitor()
            manager?.resumeMonitoring()
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isRecording = false
        }
    }
#endif
