# UniUniversalControl 개발 결과 보고서 (Claude Code)

- 작성일: 2026-11-03
- 기준 요구사항: `/Users/hok/Projects/UniUniversalControl/specs/REQUIREMENTS.md` v0.1 (UC-001~UC-005)
- 작업 위치: `~/Projects/UniUniversalControl/claude-dev`
- 이 보고서는 실제 소스코드와 `git diff dc717cf..6fcd1ce`를 다시 확인하고, 자동 테스트를 다시 실행한 결과를 바탕으로 작성했다. 보고서를 쓰는 동안 코드는 수정하지 않았다.

---

## 8. 기준 커밋 SHA 및 최종 커밋 SHA (먼저 기재)

| 항목 | 값 |
|---|---|
| 저장소 | https://github.com/8chio/darwin-bt-remote |
| 기준 브랜치 | `feature/direct-input-toggle` |
| 기준 커밋 SHA | `dc717cfb1182deeecda5bcaf3659275ee5b224ee` |
| 작업 브랜치 | `experiment/claude` |
| 구현 커밋 | `2d97d0b` — feat: keyboard-only Direct Input on macOS with Caps Lock forwarding |
| 최종 커밋 SHA | `6fcd1ce783d97cdcddf044a83103ad1a868e702e` — docs: add keyboard-only implementation report |
| 원본 브랜치 상태 | 로컬 `feature/direct-input-toggle`와 `origin/feature/direct-input-toggle` 모두 `dc717cf` 그대로 |
| GitHub Push | 하지 않음 |

이 보고서(`DEVELOPMENT_REPORT.md`)는 지시에 따라 파일로만 저장했고 커밋하지 않았다. 따라서 최종 커밋 SHA는 `6fcd1ce`이다.

---

## 1. 구현 완료 기능 및 미구현 기능

### 구현 완료

| 기능 | 구현 위치 |
|---|---|
| 키보드만 iPhone으로 전환 (이벤트 탭 마스크 = `keyDown`/`keyUp`/`flagsChanged`) | `DirectInputController.swift` `capturedEventTypes`, `eventMask` |
| 키보드 외 이벤트는 소비하지 않고 통과 | 이벤트 탭 콜백 `guard capturedEventTypes.contains(type) else { return passUnretained(cgEvent) }` |
| 커서 숨김(`NSCursor.hide`), 포인터 고정(`CGAssociateMouseAndMouseCursorPosition`) 제거 | `DirectInputController` (macOS) |
| 캡처 경로의 원격 마우스 HID 보고서 전송 제거 | macOS 컨트롤러에 `sendMouse` 없음 |
| 키보드 HID 상태 관리 분리 (눌린 키, 보조키, 6키 제한, 중립 리셋) | `DirectInputKeyboardRouter` |
| Caps Lock → HID `0x39` press/release 전송, 중복 필터 | `DirectInputEvent.capsLock`, `DirectInputCapsLockFilter`, `DirectInputKeyboardRouter.tapCapsLock` |
| 시작 실패 시 Mac 키보드를 가져가지 않음, 중립 보고서 전송, 원인 로그·UI 표시 | `start(sendKeyboard:onRelease:)`의 `fail(_:)` |
| 종료·해제 시 중립 보고서와 대기 중인 Caps Lock release 취소 | `stop()` → `router.reset()` |
| 기존 전환 단축키 유지 (저장, 충돌 거부, 중복 토글 방지) | `DirectInputHotkey*`, `DirectInputShortcutManager` (변경 없음) |
| 긴급 해제 `Control + Option` 유지 | `handle(_:)`의 `releaseShortcutPressed` |
| 트랙패드로 클릭할 수 있는 메뉴 막대 해제 "키보드를 Mac으로 되돌리기" | `showStatusItem()`, `DirectInputStatusItemTarget` |
| 트랙패드로 탭을 바꿔도 원격 모드 유지 (`SetupView.onDisappear { stop() }` 제거) | `SetupView.swift` |
| macOS UI에서 원격 트랙패드 페이지·패널·설정 숨김 | `KeyboardView`, `ClassicKeyboardView`, `SettingsView`, `TrackpadPanel` |
| Setup 원격 키보드 섹션: 연결 여부, 입력 대상(Mac / 원격 기기 (iPhone)), 전환 단축키, 긴급 해제, iPhone 한/영 도움말, 미연결 시 스위치 비활성화 | `SetupView.swift` |
| 사용자 표시 문구를 "Direct Input"에서 "원격 키보드"로 정리 (en/ko) | `L10n.swift`, `Localizable.xcstrings` |
| 자동 테스트 확장과 정적 UI 검사 추가 | `Tests/` |

### 미구현 또는 의도적으로 하지 않은 것

| 항목 | 이유 |
|---|---|
| 원격 모드 종료 시 Mac의 Caps Lock 잠금 상태·입력 소스 원복 | 앱이 샌드박스 상태(`com.apple.security.app-sandbox`)라 IOHID 잠금 상태 변경이 막힐 가능성이 크다. 요구사항상 우선 실측하고 제약을 기록하는 항목으로 판단 |
| Caps Lock 대신 다른 키 조합으로 한/영 전환 매핑 | 요구사항 UC-003.5에 따라 몰래 대체하지 않음. `Control + Space`는 기존 경로로 그대로 전달 |
| iOS 측(iPhone이 송신기) Direct Input과 원격 트랙패드 기능의 제거 | 범위 밖. 회귀 방지를 위해 유지 |
| HID descriptor와 백엔드의 마우스 정의 삭제 | 페어링·GATT 안정성 영향이 확인되지 않아 요구사항에 따라 유지 |
| Home/End/PageUp/PageDown, F13 이상, 키패드 키 매핑 추가 | 요구사항에 없음. 기존 키 맵 유지 |
| 실기기 검증 | 이번 작업에서 iPhone을 사용하지 않음. 전 항목 NOT_RUN |

---

## 2. 변경·삭제된 파일 목록

기준 `dc717cf` → 최종 `6fcd1ce`: 13개 파일, +1048 / −244행. 삭제된 파일은 없다(코드 블록만 삭제). 신규 의존성은 없다.

| 상태 | 파일 | 변경 내용 |
|---|---|---|
| M | `BTRemote/DirectInputController.swift` (+182/−140) | macOS 키보드 전용 캡처. 마우스 마스크·디코더·`sendMouse`·커서 숨김·포인터 고정 삭제, 라우터·Caps Lock 필터·메뉴 막대 해제 추가. iOS 섹션은 변경 없음 |
| M | `BTRemote/SetupView.swift` | 원격 키보드 섹션, 탭 이탈 시 stop 삭제, 단축키 관리자 주입 |
| M | `BTRemote/SettingsView.swift` | 트랙패드 섹션(추적·스크롤 속도, 제스처 링크)을 `#if os(iOS)`로 이동 |
| M | `BTRemote/KeyboardView.swift` | `KeyboardPage.available`(macOS는 트랙패드 제외), 이전 저장값 대체 |
| M | `BTRemote/ClassicKeyboardView.swift` | macOS 편집기에서 `TrackpadPanel` 삭제. 기존 레이아웃은 iOS 전용 `touchEditor`로 |
| M | `BTRemote/TrackpadPanel.swift` (−19) | macOS 전용 드래그 → 원격 마우스 코드 삭제 |
| M | `BTRemote/L10n.swift` | `L10n.RemoteKeyboard` 추가 |
| M | `BTRemote/Localizable.xcstrings` | `remote_keyboard.*` 14개 추가. macOS 전용 기존 문구 6개(`direct_input.capture_failed`, `connected_prompt_message`, `permission_message`, `shortcut.title`, `shortcut.hint`, `shortcut.no_host`) 수정 |
| M | `Tests/DirectInputShortcutTests.swift` | 마스크·라우터·Caps Lock·시작 실패 테스트. 기존 마우스 디코더 테스트는 "디코딩되지 않음" 검증으로 교체 |
| M | `Tests/README.md` | 자동·실기기 검증 절차를 키보드 전용 기준으로 갱신 |
| A | `Tests/check_keyboard_only_ui.py` | macOS 컴파일 코드의 원격 트랙패드/마우스/커서 참조를 `#if`를 고려해 검사 |
| A | `REMOVAL_NOTES.md` | 삭제·보존 범위 |
| A | `IMPLEMENTATION_REPORT.md` | 요구사항 7장 형식의 구현 보고서 |
| (미커밋) | `DEVELOPMENT_REPORT.md` | 이 보고서 |

---

## 3. UC-001~UC-005 요구사항 충족 여부

판정 기준:
- **충족(코드·자동검증)**: 코드로 구현했고 자동 테스트나 빌드로 확인했다.
- **구현(실기기 미검증)**: 코드로 구현했지만 동작은 실기기에서만 확인할 수 있다.
- **부분 / 제약**: 일부만 구현했거나 OS 제약이 있다.

어느 항목도 실기기 검증은 하지 않았다.

### UC-001 — 키보드만 전환 (P0)

| # | 요구 | 판정 | 근거 |
|---|---|---|---|
| 1 | 최초·해제 상태에서 키보드·트랙패드 모두 Mac | 구현(실기기 미검증) | 캡처 전에는 이벤트 탭이 없음 |
| 2 | 원격 모드에서 키보드만 iPhone | 충족(코드·자동검증) | 마스크 테스트, 라우터 테스트 |
| 3 | 일반 입력이 Mac 앱에 전달되지 않음 | 구현(실기기 미검증) / 제약 | 키보드 이벤트는 `nil`을 반환해 소비. Secure Input과 OS 예약 단축키는 제약(7장) |
| 4 | 트랙패드·마우스 이동·클릭·드래그·스크롤·제스처 정상 | 충족(코드·자동검증), 실동작 미검증 | 포인터·제스처 유형이 마스크에 없음, 커서 숨김·고정 삭제 |
| 5 | 다른 앱을 클릭해도 대상은 iPhone 유지 | 구현(실기기 미검증) | 포커스 감지 코드 없음, 탭 이탈 stop 삭제 |
| 6 | 마우스 이벤트를 가로채지 않고 마우스 HID 보고서를 보내지 않음 | 충족(코드·자동검증) | 디코더가 포인터 이벤트를 `nil` 처리, 라우터에 마우스 출력 없음, 정적 검사 PASS |
| 7 | 끄면 Mac 복귀, 눌림 상태 잔류 없음 | 부분 | iPhone 측은 중립 보고서와 Caps Lock release 취소(자동검증). Mac의 Caps Lock 잠금 상태는 원복하지 않음(7장) |

### UC-002 — 트랙패드 원격 제어 UI/기능 제거 (P0)

| # | 요구 | 판정 | 근거 |
|---|---|---|---|
| 1 | 원격 트랙패드·마우스 제어와 설정 제거·비활성화 | 충족(코드·자동검증) | macOS에서 페이지·패널·설정 숨김, 정적 검사 PASS(기준 커밋은 50건 검출) |
| 2 | 오해를 주는 감도·스크롤·제스처 UI 없음 | 충족(코드·자동검증) | `SettingsView` 트랙패드 섹션이 iOS 전용 |
| 3 | 삭제·보존 범위 문서화 | 충족 | `REMOVAL_NOTES.md` |
| 4 | HID 키보드 연결과 토글 정상 | 구현(실기기 미검증) | 백엔드·descriptor 변경 없음, 토글 회귀 테스트 PASS |

### UC-003 — Caps Lock으로 iPhone 한/영 전환 (P0 목표, 기기·OS 의존)

| # | 요구 | 판정 | 근거 |
|---|---|---|---|
| 1 | `flagsChanged` 경로 확인, HID `0x39` press/release, 중복·자동 반복·유실·오작동 방지 | 충족(코드·자동검증), macOS 실제 이벤트 모양은 미실측 | 4장 |
| 2 | Mac 한/영 상태가 iPhone 상태를 결정한다고 가정하지 않음 | 충족 | Mac 잠금 비트를 iPhone으로 전달하지 않고 키 탭만 전송 |
| 3 | iPhone 설정 안내 | 충족 | Setup "iPhone 한/영 전환" 도움말, `Tests/README.md` |
| 4 | Mac 로컬 Caps Lock·입력 소스 변화 실측 | 미검증 | NOT_RUN. 원복 처리 없음 |
| 5 | Caps Lock이 불가하면 `Control + Space` 테스트·안내, 몰래 대체하지 않음 | 안내 충족, 테스트 미실행 | 자동 테스트는 `Ctrl+Space` 디코딩만 확인 |
| 6 | 자동 테스트만으로 한/영 전환 성공을 확정하지 않음 | 충족 | 실기기 항목은 NOT_RUN으로 표기 |

### UC-004 — 안전한 전환 및 복구 (P0)

| # | 요구 | 판정 | 근거 |
|---|---|---|---|
| 1 | 단축키 켜기/끄기, 저장, 충돌 거부, 중복 토글 방지 유지 | 충족(코드·자동검증) | 20회 전환, 중복, 충돌·롤백 테스트 PASS, Carbon 스모크 PASS |
| 2 | 시작·종료 순간 단축키가 새거나 남지 않음 | 부분 | 시작 시 억제 유지(테스트 PASS). 단축키로 끌 때 보조키가 잠깐 전달됐다가 중립 보고서로 풀림(기존 동작) |
| 3 | `Control + Option`과 트랙패드 클릭 UI 해제 유지 | 충족(코드), 실기기 미검증 | 긴급 해제 디코더 PASS. Setup 스위치와 메뉴 막대 항목 |
| 4 | 연결 해제·탭 비활성화·앱 종료·시작 실패 시 즉시 복구와 중립 보고서 | 구현, 일부 자동검증 | 시작 실패·종료 알림·재연결은 PASS. 탭 비활성화와 실제 연결 해제는 미검증 |
| 5 | 시작 실패 시 키보드를 빼앗지 않고 이유 제공 | 충족(코드·자동검증) | 시작 실패 테스트 PASS, `lastError`, 로그 |
| 6 | 포커스 전환·트랙패드 클릭으로 모드가 바뀌거나 잠기지 않음 | 구현(실기기 미검증) | 탭 이탈 stop 제거, 포커스 기반 로직 없음 |

### UC-005 — 최소·명확한 UI (P1)

| # | 요구 | 판정 | 근거 |
|---|---|---|---|
| 1 | 연결 여부, 입력 대상, 단축키·긴급 해제 표시 | 충족(빌드 확인) | Setup 원격 키보드 섹션, 메뉴 막대 표시 |
| 2 | "Direct Input" 문구 정리 | 충족(macOS) | "원격 키보드"/"Remote Keyboard". iOS 문구는 유지 |
| 3 | 트랙패드를 막거나 포인터를 숨기는 처리 제거 | 충족(코드·자동검증) | 정적 검사 PASS |
| 4 | Caps Lock 한/영 설정 도움말 | 충족 | Setup 도움말 |

UI의 실제 화면 렌더링은 스크린샷으로 확인하지 않았다(빌드만 확인).

---

## 4. Caps Lock 한영 전환 구현 방식

### 이벤트 경로

```
물리 Caps Lock
 → macOS CGEvent flagsChanged (keycode 0x39, maskAlphaShift = 바뀐 Mac 잠금 상태)
 → DirectInputEvent.capsLock(isOn:)               // DirectInputController.swift
 → DirectInputCapsLockFilter.accept(isOn:at:)     // 중복 판정
 → DirectInputKeyboardRouter.tapCapsLock()
     ① 보고서 keys = [0x39] + 현재 눌린 키, 보조키 유지 → 즉시 전송
     ② 60 ms 후 0x39를 뺀 보고서 전송 (release)
 → HIDInput.sendKeyboard → BLE(HIDPeripheral) 또는 Classic 백엔드
```

### 설계 근거

- **release를 직접 만드는 이유:** macOS는 Caps Lock을 키다운/키업이 아니라 `flagsChanged` 하나로 보내는 것으로 알려져 있다. 물리적 release 시점을 알 수 없으므로 "누름 → 60 ms 유지 → 뗌" 탭을 만든다. 상수는 `DirectInputKeyboardRouter.capsLockHoldNanoseconds`이다.
- **release를 지연하는 이유:** BLE 백엔드(`HIDPeripheral`)는 대기 슬롯(`pendingBroadcast`)이 하나뿐이다. press와 release를 연달아 보내면 press가 덮여 iPhone에 전달되지 않을 수 있다. 앱의 기존 `KeyTypist`가 20 ms 간격을 두는 것도 같은 이유다.
- **중복 필터:** 같은 잠금 상태의 이벤트가 250 ms 안에 다시 오면 무시한다(`duplicateWindowNanoseconds`). 막으려는 경우와 허용하는 경우는 다음과 같다.
  - 중복 전달이나 key-up 메아리는 막는다.
  - 잠금 상태가 바뀌면 빠르게 눌러도 허용한다.
  - Mac이 잠금 상태를 바꾸지 않는 모드(입력 소스 전환 모드)라도 250 ms가 지난 뒤의 누름은 허용한다.
- **자동 반복:** 반복 키다운은 디코딩 단계에서 버린다. Caps Lock 탭은 이벤트마다 독립적인 press/release라서 길게 눌러도 `0x39`가 계속 눌린 상태로 남지 않는다.
- **눌림 잔류 방지:** `stop()` → `router.reset()`이 대기 중인 release를 취소하고 중립 보고서(`00×8`)를 보낸다. 새 세션은 이전 필터 상태를 이어받지 않는다.
- **Mac 잠금 비트:** `maskAlphaShift`는 iPhone 보조키로 전달하지 않는다. iPhone의 한/영·대문자 상태는 iPhone이 자체적으로 판단한다.
- **사용자 안내:** Setup에 "iPhone 한/영 전환" 도움말을 넣었다. 한국어·영어 키보드를 추가하고, 설정 → 일반 → 키보드 → 하드웨어 키보드 → 'Caps Lock으로 언어 전환'을 확인하라는 내용이다(iOS 버전에 따라 다름). 전환되지 않으면 `Control + Space`를 쓰도록 안내한다.

### 검증 상태

- HID `0x39` press 보고서 `00 00 39 00 00 00 00 00`과 이어지는 release `.zero`는 자동 테스트로 PASS했다.
- iPhone에서 실제로 한/영이 전환되는지는 **미검증(NOT_RUN)**이다. `0x39`를 올바르게 보냈다는 사실과 언어 전환 성공은 서로 다른 검증 항목이다.

---

## 5. 빌드 및 자동 테스트 결과

환경: Mac16,8, macOS 27.0.1, Xcode 27.1 (27A9275)

### 빌드

구현 커밋 `2d97d0b`와 같은 소스로 실행했다. 이후 커밋은 문서만 변경했다.

| 대상 | 명령 | 결과 |
|---|---|---|
| macOS Debug | `xcodegen generate` → `xcodebuild -project BTRemote.xcodeproj -scheme BTRemote -configuration Debug -destination "platform=macOS" -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED, 경고 0 |
| macOS Release | 위와 같음, `-configuration Release` | BUILD SUCCEEDED, 경고 0 |
| iOS Release | `… -configuration Release -sdk iphoneos -destination "generic/platform=iOS" -derivedDataPath .build/DerivedData-ios CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED, 경고 0 |
| swiftformat / swiftlint (`build.sh`) | — | NOT_RUN. 이 Mac에 설치되어 있지 않음 |

### 자동 테스트 (이 보고서 작성 시 다시 실행)

| 테스트 | 명령 | 결과 |
|---|---|---|
| 이벤트 경로: 단축키 필터, 시작 조합 억제, A/Ctrl+Space/긴급 해제/자동 반복 | `Tests/run-direct-input-shortcut-tests.sh` | PASS |
| 키보드 전용 마스크: 마우스 이동·클릭·드래그·스크롤·태블릿·제스처 미디코딩 | 위 스크립트 | PASS |
| 라우터: 키 눌림/해제, 보조키, 6키 제한, 중립 리셋, 마우스 보고서 0건 | 위 스크립트 | PASS |
| Caps Lock: `0x39` press/release, 중복 필터, 타이핑 조합, stop 시 취소 | 위 스크립트 | PASS |
| 시작 실패: Mac 키보드 유지, 중립 보고서, stop 중복 호출 안전 | 위 스크립트 | PASS |
| 단축키 관리자 회귀: 20회 전환, 반복, UI 시작, 저장, 충돌·롤백, 녹화 중단·재개, 실패, 재연결, 종료·초기화 | 위 스크립트 | PASS |
| Carbon 실제 등록: 등록, 중복 거부, 정리 | `.build/direct-input-shortcut-tests --carbon-smoke` | PASS |
| macOS UI 원격 트랙패드/마우스/커서 참조 없음 (10개 파일) | `python3 Tests/check_keyboard_only_ui.py` | PASS. 기준 커밋에 돌리면 50건을 검출하고 실패함 |
| 문자열 카탈로그 en/ko(270키), 참조 키 268개, 컴파일 테이블 | `python3 Tests/check_localizations.py [--app …]` | PASS |

합계: 9개 묶음 통과 9, 실패 0.

### 자동 테스트가 확인하지 못하는 것

- 실제 이벤트 탭 설치·동작
- 물리 키가 macOS에서 어떤 이벤트 모양으로 오는지
- BLE/Classic의 실제 전송
- 메뉴 막대 클릭
- UI 렌더링
- iPhone 동작 전체

---

## 6. 실제 iPhone에서 검증이 필요한 항목

현재 상태는 전부 **NOT_RUN**이다. 환경으로 다음을 기록한다: Mac 모델/macOS, iPhone 모델/iOS, BLE·Classic 여부, iPhone 한국어·영어 키보드, 하드웨어 키보드 설정.

| # | 항목 | 확인 내용 |
|---|---|---|
| 1 | 일반 모드 | Mac 키보드·트랙패드가 Mac에서 정상 동작 |
| 2 | 원격 모드 입력 | 영어 입력이 iPhone으로 가고 Mac 앱에는 입력되지 않음 |
| 3 | 트랙패드 불변 | 포인터 이동, 좌/우 클릭, 드래그, 스크롤, 두·세 손가락 제스처가 Mac에서 동작. 포인터가 보이고 iPhone에는 포인터가 나타나지 않음 |
| 4 | 보조키와 클릭 조합 | 원격 모드에서 ⌘+클릭, ⇧+클릭, ⌥+드래그가 Mac에서 어떻게 동작하는지 기록(7장 4) |
| 5 | 포커스 독립 | 트랙패드로 다른 앱이나 다른 탭을 클릭해도 입력은 iPhone 유지 |
| 6 | Caps Lock 한/영 | 반복 전환 성공 여부와 실제 입력 결과 |
| 7 | 대체 전환 | `Control + Space`에 대한 iPhone 반응 |
| 8 | Mac 상태 | Caps Lock을 누를 때 Mac Caps Lock LED와 입력 소스 변화, 복귀 후 상태 |
| 9 | 키 복구 | `Control + Option`, 단축키, Setup 스위치, 메뉴 막대 항목으로 복귀. 연결 해제, 재연결, 앱 종료 후 Mac 키보드 정상, iPhone에 눌린 키 없음 |
| 10 | 반복 | 원격/로컬 전환 20회 이상, 입력 멈춤·고착 없음 |
| 11 | 탭 비활성화 | macOS가 이벤트 탭을 비활성화하면 상태 해제와 오류 표시(보안 설정을 바꿔 일부러 만들지 않음) |
| 12 | Caps Lock 타이밍 | 60 ms 탭을 iOS가 짧은 누름으로 인식하는지, 250 ms 중복 창이 적절한지 |

절차는 `Tests/README.md`의 "MacBook + iPhone"과 `IMPLEMENTATION_REPORT.md` 8장에 있다.

---

## 7. 발견된 문제와 기술적 제약

| # | 우선순위 | 내용 | 종류 |
|---|---|---|---|
| 1 | 높음 | 실기기 검증 전부 미실행. 핵심 목표(트랙패드 불변, 한/영 전환)를 확인하지 못함 | 미해결 |
| 2 | 높음 | macOS의 Caps Lock 이벤트 모양(누를 때만인지, 뗄 때도인지, 입력 소스 전환 모드에서 어떤지)을 실측하지 않음. 필터는 두 경우를 모두 다루도록 설계했지만 가정에 기반함 | 미해결 |
| 3 | 중간 | 이벤트 탭은 Mac 앱 전달만 막는다. Mac의 Caps Lock 잠금·LED는 하드웨어 수준에서 바뀔 수 있다. macOS에서 "Caps Lock으로 ABC 입력 소스 전환"을 켜 두면 Mac 입력 소스도 바뀔 수 있다. 샌드박스 때문에 원복 처리가 없다 | 제약 |
| 4 | 중간 | 원격 모드에서는 보조키 입력이 iPhone으로 가므로 Mac의 ⌘/⇧/⌥+클릭이 보조키 없는 클릭으로 처리될 수 있다. 클릭 이벤트의 보조키 상태는 탭보다 앞 단계에서 정해지므로 정상일 가능성도 있다. 미검증 | 미확인 |
| 5 | 중간 | 60 ms 유지·250 ms 중복 창은 추정값이다. iOS가 너무 짧은 누름을 무시하거나, 잠금 상태가 바뀌지 않는 모드에서 250 ms 안의 두 번째 누름이 무시될 수 있다 | 제약 |
| 6 | 낮음 | Apple 키보드의 Caps Lock 지연 때문에 아주 짧은 누름은 macOS가 무시하여 이벤트가 오지 않을 수 있다 | OS 제약 |
| 7 | 낮음 | 단축키로 끌 때 단축키의 보조키가 잠깐 iPhone에 전달됐다가 중립 보고서로 풀린다(기존 동작과 같음) | 기존 동작 |
| 8 | 낮음 | Secure Input(암호 입력란 등) 중이나 macOS 보호·예약 단축키는 이벤트 탭이 받지 못해 Mac에 남을 수 있다 | OS 제약 |
| 9 | 낮음 | 앱이 비정상 종료되면 이벤트 탭은 사라져 Mac 키보드는 복구되지만, iPhone 측 키 해제는 iPhone의 연결 해제 처리에 의존한다 | 제약 |
| 10 | 낮음 | Home/End/PageUp/PageDown, F13 이상, 키패드, ISO 추가 키는 기존 키 맵에 없어 전달되지 않는다 | 범위 밖 |
| 11 | 낮음 | swiftformat/swiftlint 미실행. 포맷·린트 규칙 위반 여부를 확인하지 못함 | 미해결 |
| 12 | 정보 | 창을 닫으면(`ContentView.onDisappear`) 원격 모드가 꺼진다. 안전 복구로 보고 기존 동작을 유지했다 | 설계 선택 |
| 13 | 정보 | 작업 브랜치 이름은 사용자 지정 `experiment/claude`이며, 요구사항 문서 예시 `experiment/claude-keyboard-only`와 다르다. Codex와 같은 기준 SHA인지는 이 환경에서 확인 불가 | 참고 |
