# Direct Input shortcut verification

Shortcut implementation provenance: local `main` at `1725708`.
Current keyboard-only work starts at `feature/direct-input-toggle`,
`dc717cfb1182deeecda5bcaf3659275ee5b224ee`, and adds Caps Lock HID support.

Reference: LiLeoH/darwin-bt-remote at `fcb684f519867b9e4c2814ad7905dead5b840b17`:
[manager](https://github.com/LiLeoH/darwin-bt-remote/blob/fcb684f519867b9e4c2814ad7905dead5b840b17/BTRemote/DirectInputShortcutManager.swift),
[monitor](https://github.com/LiLeoH/darwin-bt-remote/blob/fcb684f519867b9e4c2814ad7905dead5b840b17/BTRemote/DirectInputHotkeyMonitor.swift),
[shortcut model](https://github.com/LiLeoH/darwin-bt-remote/blob/fcb684f519867b9e4c2814ad7905dead5b840b17/BTRemote/Hotkey.swift),
[recorder](https://github.com/LiLeoH/darwin-bt-remote/blob/fcb684f519867b9e4c2814ad7905dead5b840b17/BTRemote/ShortcutRecorder.swift).
The persistence/manager/recording design is adapted. Carbon registration replaces
the idle NSEvent key-down monitor to support registration conflicts and shortcut
consumption. Capture-time detection uses the original controller's event tap.
The existing Control+Option emergency release remains reserved. The unrelated BLE,
clipboard, mouse scheduling, and one-second connect grace implementations are not ported.

## Automated

Run `Tests/run-direct-input-shortcut-tests.sh` from this worktree. It compiles the
production shortcut model, monitor, manager, capture event decoder, and HID report
types. Storage, hotkey registration, and the capture target are replaced by test
objects. It never posts input or changes Accessibility/Bluetooth settings.

Coverage: 20 complete start/stop cycles (40 activations), held-key duplicate
suppression, starting chord filtering, no-shortcut UI start, settings round trip,
registration/system conflict rejection with rollback, recorder pause/resume,
failed start, current connection state after reconnect, settings reset, and app
termination notification cleanup. The original letter, Ctrl+Space, emergency
release decoders are exercised; mouse move/click/scroll must now be rejected.

Optional `.build/direct-input-shortcut-tests --carbon-smoke` briefly registers
Command+Shift+F19, verifies duplicate registration rejection and cleanup, and
reports SKIP if registration is unavailable. It does not synthesize keystrokes.

These tests do not verify physical hotkey delivery, the event tap, physical local pointer
behavior, persistence through a real app relaunch, BLE delivery, or iPhone behavior.

## MacBook + iPhone

1. Quit other BTRemote builds. Launch this worktree's Release app. Keep existing
   Bluetooth and Accessibility settings; handle any permission prompt yourself.
2. Connect using Bluetooth LE. Confirm iPhone hardware keyboard recognition.
3. With no toggle shortcut set, start Direct Input from Setup. Test English and
   Korean typing, Caps Lock and Ctrl+Space switching. Mouse movement, clicks,
   drag, scroll and gestures must stay on Mac. Release with Control+Option.
4. In Settings > Remote Keyboard Shortcut, record a free shortcut such as
   Command+Shift+D. Ensure Command+Space and Control+Space are rejected without
   replacing the current binding. A Carbon-registered conflicting app shortcut
   should also produce an error and preserve the previous binding.
5. With this app focused, use the shortcut to start, release the entire chord,
   type a marker, then use the same shortcut to stop. Confirm no shortcut letter
   appears on iPhone and no Command/Shift remains held.
6. Repeat with another Mac app focused. Test holding the shortcut key: one
   physical press should toggle once. Test both left and right modifiers.
7. Repeat a full start/stop cycle 20 times. Check that the Mac cursor and keyboard
   remain usable locally after release, and that ordinary input/Ctrl+Space work.
8. Disconnect while capturing: capture should stop. Reconnect and repeat the
   shortcut. Confirm it uses the current connection, not a stale HID backend.
9. Quit/relaunch and verify the saved binding, recording cancellation via Escape,
   clear binding, and Setup's independent UI control. Quit while capturing using
   the app/Dock controls and confirm local input restoration.
10. If capture fails or macOS disables the event tap, verify the capture state is
    cleared, the error is visible, and local input is restored. Do not change
    system security settings just to simulate this case.

Record pass/fail separately for each physical scenario. Automated PASS is not an
iPhone test result. Global shortcuts implemented by other apps using independent
key event taps may not reserve a Carbon hotkey and cannot all be detected in advance.

## Keyboard-only implementation (experiment/codex)

Run `bash Tests/run-direct-input-shortcut-tests.sh` and
`python3 Tests/verify-keyboard-only-ui.py` from the repository root.
The Swift harness now checks keyboard-only event masks/decoding, Caps Lock
`0x39` press/release and duplicate suppression, held-key/modifier reports,
permission-failure cleanup, backend reset selection, disconnect/reconnect,
20 toggle cycles, shutdown, and BLE keyboard FIFO backpressure/overflow behavior.
The Python check verifies macOS-only UI/source boundaries and saved trackpad-page
migration; it does not render the interface or test actual pointing devices.

These tests neither install a live event tap nor inject OS input. Manager tests
use fake capture/monitor objects; permission failure tests use the real controller
with an untrusted permission stub. They cannot establish that an iPhone received
reports or switched languages. See `IMPLEMENTATION_REPORT.md` for build results,
environment limitations, and the required Mac+iPhone manual checklist.
