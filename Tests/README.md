# Direct Input (keyboard-only) verification

Based on `feature/direct-input-toggle` at `dc717cf`. On macOS, Direct Input is now
keyboard-only ("Remote Keyboard"): the Mac trackpad and mouse are never captured,
hidden, or forwarded. Caps Lock is forwarded as HID usage `0x39`.

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

Run from this worktree:

```sh
Tests/run-direct-input-shortcut-tests.sh          # shortcut, capture decoder, keyboard router, Caps Lock
python3 Tests/check_keyboard_only_ui.py           # macOS code has no remote trackpad/mouse paths
python3 Tests/check_localizations.py              # en/ko catalog coverage
```

The Swift harness compiles the production shortcut model, monitor, manager, capture
controller, keyboard router, and HID report types. Storage, hotkey registration, the
capture target, the HID backend, and the Caps Lock release timer are replaced by test
objects. It never posts input or changes Accessibility/Bluetooth settings.

Coverage: keyboard-only event mask (keyDown/keyUp/flagsChanged only; mouse move,
click, drag, scroll, tablet, and gesture types are absent and never decoded); key
press/release, modifier changes, six-key limit, and neutral reset with no mouse
report; Caps Lock `flagsChanged` keycode `0x39` -> HID `0x39` press then timed
release, duplicate/echo filtering, Caps Lock while typing, cancel on stop, and no
stuck `0x39`; capture start failure leaves the keyboard local and sends a neutral
report; 20 complete start/stop cycles (40 activations), held-key duplicate
suppression, starting chord filtering, no-shortcut UI start, settings round trip,
registration/system conflict rejection with rollback, recorder pause/resume,
failed start, current connection state after reconnect, settings reset, and app
termination notification cleanup. Letter, Ctrl+Space, emergency release, and
auto-repeat decoders are also exercised.

Optional `.build/direct-input-shortcut-tests --carbon-smoke` briefly registers
Command+Shift+F19, verifies duplicate registration rejection and cleanup, and
reports SKIP if registration is unavailable. It does not synthesize keystrokes.

These tests do not verify physical hotkey delivery, the event tap, the real BLE or
Classic delivery, how macOS reports a physical Caps Lock press, persistence through
a real app relaunch, or any iPhone behavior. Sending HID `0x39` is not proof that
the iPhone switched between Korean and English.

## MacBook + iPhone

Record the Mac model/macOS version, iPhone model/iOS version, transport (BLE or
Classic), the iPhone keyboards (Korean, English), and the iPhone hardware keyboard
settings. Mark each item PASS / FAIL / BLOCKED / NOT_RUN.

1. Quit other BTRemote builds. Launch this worktree's Release app. Keep existing
   Bluetooth and Accessibility settings; handle any permission prompt yourself.
2. Connect using Bluetooth LE. Confirm iPhone hardware keyboard recognition.
3. Local mode: the Mac keyboard and trackpad both work on the Mac.
4. Turn on Setup > Remote Keyboard. Type English into an iPhone text field; the same
   characters must not appear in the focused Mac app.
5. While remote: move the pointer, left/right click, drag a window, scroll, and use
   two/three-finger gestures on the Mac. All must work on the Mac. The pointer must
   stay visible and the iPhone must not show a pointer.
6. While remote: click another Mac app and type. Input must still go to the iPhone.
7. Caps Lock: on the iPhone, add Korean and English keyboards and check Settings >
   General > Keyboard > Hardware Keyboard > "Caps Lock to switch language" (name and
   availability vary by iOS version). Press Caps Lock repeatedly and record whether
   the iPhone switches Korean <-> English and the typed result. Also record whether
   the Mac Caps Lock light or Mac input source changes, and its state after returning.
8. If Caps Lock does not switch, record what Control+Space does on the iPhone.
9. Return the keyboard with Control+Option, the shortcut, the Setup switch, and the
   menu bar item "Return Keyboard to Mac". Each time, verify Mac typing and that no
   Shift/Command/Control/Option/Caps Lock stays pressed on the iPhone.
10. In Settings > Remote Keyboard Shortcut, record a free shortcut such as
    Command+Shift+D. Ensure Command+Space and Control+Space are rejected without
    replacing the current binding. Toggle with another app focused; holding the
    shortcut must toggle once and no shortcut letter may reach the iPhone.
11. Repeat a full start/stop cycle at least 20 times; no stuck or frozen input.
12. Disconnect while remote: capture stops and the Mac keyboard returns. Reconnect
    and toggle again. Quit while remote and confirm local input restoration.
13. If capture fails or macOS disables the event tap, verify the capture state is
    cleared, the error is visible, and local input is restored. Do not change
    system security settings just to simulate this case.

Automated PASS is not an iPhone test result. Global shortcuts implemented by other
apps using independent key event taps may not reserve a Carbon hotkey and cannot all
be detected in advance.
