# REMOVAL_NOTES — 키보드 전용 전환에 따른 삭제·보존 범위

기준: `feature/direct-input-toggle` @ `dc717cfb1182deeecda5bcaf3659275ee5b224ee`
대상 사용 사례: macOS(송신) → iPhone(Bluetooth HID 수신)

## 삭제·비활성화 (macOS)

| 항목 | 위치 | 처리 |
|---|---|---|
| 마우스·스크롤 이벤트 캡처 (`mouseMoved`, `left/right/otherMouseDown/Up/Dragged`, `scrollWheel`) | `DirectInputController.swift` 이벤트 마스크 | 삭제. 마스크는 `keyDown`/`keyUp`/`flagsChanged`만 포함 |
| 마우스 디코더 (`mouseMove`, `mouseButton`, `scroll` 케이스, `clampInt8`, `mouseButton(for:)`) | `DirectInputEvent` | 삭제. 포인터 이벤트는 `nil`로 디코딩 |
| 원격 마우스 HID 보고서 전송 (`sendMouse`, `pressedMouseButtons`, 종료 시 `sendMouse(.zero)`) | `DirectInputController` | 삭제. 캡처 경로에서는 키보드 보고서만 전송 |
| 커서 숨김·고정 (`NSCursor.hide/unhide`, `CGAssociateMouseAndMouseCursorPosition`) | `DirectInputController` | 삭제 |
| 키보드 외 이벤트 소비 | 이벤트 탭 콜백 | 키보드 외 이벤트는 그대로 통과(`passUnretained`)시키도록 방어 코드 추가 |
| Setup 탭 이탈 시 캡처 종료 (`SetupView.onDisappear { stop() }`) | `SetupView.swift` (macOS) | 삭제. 트랙패드로 탭을 바꾸기만 해도 원격 모드가 꺼지던 문제 제거 (UC-004.6) |
| 원격 트랙패드 페이지 | `KeyboardView.swift` | macOS에서 페이지 목록·전환 대상에서 제외. 예전에 저장된 페이지 값은 키보드로 대체 |
| Classic 키보드 옆 원격 트랙패드 패널 | `ClassicKeyboardView.swift` | macOS에서 표시하지 않음 |
| 원격 트랙패드 설정 (추적 속도, 스크롤 속도, 제스처 설정 링크) | `SettingsView.swift` | macOS에서 표시하지 않음 (iOS 전용) |
| macOS 전용 드래그 → 원격 마우스 코드 | `TrackpadPanel.swift` | 삭제. macOS에서 더 이상 도달하지 않음 |

## 보존 (회귀 방지)

| 항목 | 이유 |
|---|---|
| HID report descriptor의 마우스·디지타이저 정의, `HIDInput.sendMouse`, `HIDPeripheral`/`HIDClassicDevice`의 `sendMouse` | GATT/SDP 레이아웃과 페어링 안정성에 영향을 줄 수 있어 요구사항에 따라 유지. macOS 캡처 경로에서는 호출하지 않음 |
| iOS 측 `DirectInputController`(GCKeyboard/GCMouse), `PointerLockHost` | iPhone이 송신 측인 다른 사용 사례. 이번 범위(macOS → iPhone)와 무관 |
| iOS 원격 트랙패드 UI (`TrackpadPanel`, `StandaloneTrackpadView`, `TouchpadView`, `TrackpadGestureSettingsView`, `TrackpadGestureAction`) | iPhone을 트랙패드로 쓰는 iOS 앱 기능. macOS에서만 노출을 막음 |
| 트랙패드 관련 `AppSettings` 키와 문자열 | iOS UI가 계속 사용 |
| `direct_input.section`/`toggle`/`release_hint`/`ios_no_device` 문자열 | iOS Direct Input UI가 계속 사용. macOS는 새 `remote_keyboard.*` 키 사용 |
| 단축키 저장·검증·충돌 거부·중복 토글 방지 (`DirectInputHotkey*`, `DirectInputShortcutManager`) | UC-004.1에 따라 동작 변경 없이 유지 |
| 긴급 해제 `Control + Option` | UC-004.3에 따라 유지 |
| 메뉴 막대 상태 항목 | 유지. 트랙패드로 클릭해 "키보드를 Mac으로 되돌리기"를 선택할 수 있도록 메뉴 추가 |
