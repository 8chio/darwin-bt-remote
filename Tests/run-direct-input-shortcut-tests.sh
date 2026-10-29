#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 6 -module-cache-path .build/ModuleCache \
    BTRemote/AppSettings.swift BTRemote/LowEnergy/HIDReports.swift \
    BTRemote/DirectInputHotkey.swift BTRemote/DirectInputHotkeyMonitor.swift \
    BTRemote/DirectInputController.swift BTRemote/DirectInputShortcutManager.swift \
    Tests/DirectInputShortcutTests.swift -o .build/direct-input-shortcut-tests
.build/direct-input-shortcut-tests
