#!/usr/bin/env python3
"""Source-boundary checks complement runtime report tests; not visual/OS tests."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def mac_source(name):
    active = [True]
    conditions = []
    output = []
    for line in (ROOT / 'BTRemote' / name).read_text().splitlines():
        directive = line.strip()
        if directive.startswith('#if '):
            expression = directive[4:]
            assert expression in ('os(macOS)', 'os(iOS)', 'DEBUG'), expression
            condition = expression == 'os(macOS)'
            conditions.append(condition)
            active.append(active[-1] and condition)
        elif directive.startswith('#elseif '):
            condition = directive[8:] == 'os(macOS)'
            active[-1] = active[-2] and not conditions[-1] and condition
            conditions[-1] |= condition
        elif directive == '#else':
            active[-1] = active[-2] and not conditions[-1]
        elif directive == '#endif':
            active.pop()
            conditions.pop()
        elif active[-1]:
            output.append(line)
    assert len(active) == 1
    return '\n'.join(output)


capture = mac_source('DirectInputController.swift')
for forbidden in ('sendMouse', 'MouseReport', 'NSCursor.', 'CGAssociateMouseAndMouseCursorPosition'):
    assert forbidden not in capture, forbidden
for name in ('KeyboardView.swift', 'ClassicKeyboardView.swift', 'SettingsView.swift'):
    source = mac_source(name)
    for forbidden in ('StandaloneTrackpadView(', 'TrackpadPanel(', 'TrackpadGestureSettingsView(',
                      'L10n.Settings.trackpad', 'L10n.Settings.trackingSpeed', 'L10n.Settings.scrollSpeed'):
        assert forbidden not in source, (name, forbidden)
keyboard = mac_source('KeyboardView.swift')
assert '[.fullKeyboard, .classic]' in keyboard
assert 'if selectedPage == 1 { selectedPage = 0 }' in keyboard
assert '.onDisappear { directInput.stop() }' not in mac_source('SetupView.swift')
assert 'button.action = #selector(releaseFromStatusItem)' in capture
content = mac_source('ContentView.swift')
for marker in ('keyboardStatus', 'shortcuts.connectionChanged(connected)', '.onChange(of: hid.activeError)',
               'keyboard_only.target_remote', 'keyboard_only.target_mac', 'keyboard_only.caps_help'):
    assert marker in content, marker
print('PASS: macOS UI boundaries, old trackpad preference migration, no pointer APIs, focus-independent setup, clickable release/status/help')
