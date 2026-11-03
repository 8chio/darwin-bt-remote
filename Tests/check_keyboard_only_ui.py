#!/usr/bin/env python3
"""Check that macOS-compiled UI and capture code has no remote trackpad/mouse paths."""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1] / "BTRemote"
FILES = [
    "ContentView.swift", "SetupView.swift", "SettingsView.swift", "KeyboardView.swift",
    "ClassicKeyboardView.swift", "RemoteTabView.swift", "RemoteView.swift",
    "DirectInputController.swift", "DirectInputShortcutManager.swift", "DirectInputShortcutSettingsView.swift",
]
FORBIDDEN = [
    "TrackpadPanel(", "StandaloneTrackpadView(", "TrackpadGestureSettingsView(", "TouchpadView(",
    "sendMouse", "MouseReport", "NSCursor.hide", "CGAssociateMouseAndMouseCursorPosition",
    "L10n.Settings.trackpad", "L10n.Settings.trackingSpeed", "L10n.Settings.scrollSpeed",
    "L10n.Gesture.sectionTitle", ".mouseMoved", ".scrollWheel", "MouseDown", "MouseUp", "MouseDragged",
]
IOS_ONLY = re.compile(r"#(?:else)?if\s+os\(iOS\)")


def macos_lines(text):
    """Yield (line number, code) for lines compiled on macOS; nested #if blocks are tracked."""
    stack = []  # True when the current branch is excluded from macOS
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append(bool(IOS_ONLY.match(stripped)))
            continue
        if stripped.startswith("#elseif"):
            stack[-1] = bool(IOS_ONLY.match(stripped))
            continue
        if stripped.startswith("#else"):
            stack[-1] = not stack[-1]
            continue
        if stripped.startswith("#endif"):
            stack.pop()
            continue
        if any(stack) or stripped.startswith("//"):
            continue
        yield number, line.split("//")[0]


def check():
    problems = []
    for name in FILES:
        for number, code in macos_lines((ROOT / name).read_text()):
            problems += [f"{name}:{number}: {token}" for token in FORBIDDEN if token in code]
    assert not problems, "\n".join(problems)
    print(f"PASS: no remote trackpad/mouse or pointer-capture references in macOS code of {len(FILES)} files")


if __name__ == "__main__":
    check()
