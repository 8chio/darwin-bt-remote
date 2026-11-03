# IMPLEMENTATION_REPORT — Keyboard-Only 전환 (Claude Code)

요구사항: `specs/REQUIREMENTS.md` v0.1 (2026-11-03), UC-001~UC-005

## 1. 기준점

| 항목 | 값 |
|---|---|
| 저장소 | https://github.com/8chio/darwin-bt-remote |
| 시작 브랜치 | `feature/direct-input-toggle` |
| 시작 SHA | `dc717cfb1182deeecda5bcaf3659275ee5b224ee` |
| 작업 브랜치 | `experiment/claude` (사용자 지정 이름. 문서 예시의 `experiment/claude-keyboard-only`는 쓰지 않음) |
| 구현 커밋 | `2d97d0b` |
| 최종 SHA | 이 보고서 커밋 (`git log -1 experiment/claude`) |
| 원본 브랜치 | 로컬·원격 모두 `dc717cf` 그대로. 푸시하지 않음 |

Codex 측 시작 SHA와의 일치 여부는 이 환경에서 확인할 수 없음. 다른 AI의 작업물은 참고하지 않음.

## 2. 구현 요약

macOS의 Direct Input을 키보드 전용 "원격 키보드"로 바꿨다. 이벤트 탭 마스크는 `keyDown`/`keyUp`/`flagsChanged`만 포함하고, 마우스·스크롤 디코더, 원격 마우스 보고서 전송, 커서 숨김(`NSCursor.hide`), 포인터 고정(`CGAssociateMouseAndMouseCursorPosition`)은 삭제했다. 따라서 원격 모드에서도 Mac 트랙패드와 마우스는 Mac에서 그대로 동작한다. 키보드 HID 상태(눌린 키, 보조키, Caps Lock tap)는 새 `DirectInputKeyboardRouter`가 관리하며, 이 클래스에는 마우스 출력 경로가 없다. Mac Caps Lock(`flagsChanged` 키코드 `0x39`)은 HID `0x39` press를 보낸 뒤 60 ms 후 release를 보내는 방식으로 전달하고, 중복 수신은 거른다. 기존 단축키 토글과 `Control + Option` 긴급 해제는 그대로 유지했다. 트랙패드로 클릭할 수 있는 메뉴 막대 "키보드를 Mac으로 되돌리기"를 추가했고, Setup 탭을 벗어나기만 해도 캡처가 꺼지던 동작은 없앴다. macOS UI에서는 원격 트랙패드 페이지·패널·설정을 숨겼고, Setup에 연결 여부, 키보드 입력 대상(Mac / 원격 기기 (iPhone)), 전환 단축키, 긴급 해제, iPhone 한/영 전환 도움말을 표시한다. Bluetooth HID descriptor·백엔드와 iOS 측 기능은 변경하지 않았다. 삭제·보존 범위의 상세는 `REMOVAL_NOTES.md`에 있다.

## 3. 주요 파일별 변경사항

| 파일 | 목적 |
|---|---|
| `BTRemote/DirectInputController.swift` | (macOS) 키보드 전용 마스크, 비키보드 이벤트 통과, 마우스·커서 코드 삭제, `DirectInputKeyboardRouter`·`DirectInputCapsLockFilter` 추가, 시작 실패 시 중립 보고서, 클릭 가능한 메뉴 막대 해제 |
| `BTRemote/SetupView.swift` | 원격 키보드 섹션(연결, 입력 대상, 단축키, 긴급 해제, 한/영 도움말), 미연결 시 스위치 비활성화, 탭 이탈 시 stop 제거 |
| `BTRemote/SettingsView.swift` | 원격 트랙패드 섹션을 iOS 전용으로 |
| `BTRemote/KeyboardView.swift` | macOS 페이지 목록에서 트랙패드 제외, 저장값 대체 |
| `BTRemote/ClassicKeyboardView.swift` | macOS에서 트랙패드 패널 제거 |
| `BTRemote/TrackpadPanel.swift` | macOS 전용 드래그 → 원격 마우스 코드 삭제 |
| `BTRemote/L10n.swift`, `BTRemote/Localizable.xcstrings` | `remote_keyboard.*` 14개 추가, macOS 전용 문구 6개 키보드 전용으로 수정 (en/ko) |
| `Tests/DirectInputShortcutTests.swift` | 마스크·디코더·라우터·Caps Lock·시작 실패 테스트 추가 |
| `Tests/check_keyboard_only_ui.py` | macOS 컴파일 코드에 원격 트랙패드/마우스/커서 참조가 없는지 `#if`를 고려해 검사 |
| `Tests/README.md` | 자동·실기기 검증 절차를 키보드 전용 기준으로 갱신 |
| `REMOVAL_NOTES.md` | 삭제·보존 범위 |

## 4. 검증 표

환경: Mac16,8, macOS 27.0.1, Xcode 27.1 (27A9275). iPhone 실기기는 이번 작업에서 사용하지 않음.

| 테스트 | 명령 / 환경 | 결과 | 근거 |
|---|---|---|---|
| macOS 빌드 (Debug, Release) | `xcodegen generate` 후 `xcodebuild … -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build` | PASS | `BUILD SUCCEEDED`, 경고 0 |
| iOS 빌드 (Release) | `xcodebuild … -sdk iphoneos -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO build` | PASS | `BUILD SUCCEEDED`, 경고 0 |
| 기존 단축키 회귀 (20회 전환, 중복, 충돌·롤백, 재연결, 종료) | `Tests/run-direct-input-shortcut-tests.sh` | PASS | 기존 검사 전부 유지 |
| 키보드 전용 마스크·디코더 | 위 스크립트 | PASS | 마스크 = 키보드 3종, 포인터·태블릿·제스처 유형은 디코딩되지 않음 |
| 키 눌림/해제·보조키·6키 제한·중립 리셋 | 위 스크립트 | PASS | 마우스 보고서 0건 |
| Caps Lock → HID `0x39` press/release, 중복, 타이핑 조합, stop 시 취소 | 위 스크립트 | PASS | press `00 00 39 00…`, 이어서 release `.zero`. `0x39`가 눌린 채 끝나지 않음 |
| 캡처 시작 실패 | 위 스크립트 | PASS | 캡처되지 않음, 중립 보고서 1건, `onRelease` 호출 |
| Carbon 실제 등록 스모크 | `.build/direct-input-shortcut-tests --carbon-smoke` | PASS | ⌘⇧F19 등록, 중복 거부, 정리 |
| macOS UI 원격 트랙패드 제거 | `python3 Tests/check_keyboard_only_ui.py` | PASS | 기준 커밋에 돌리면 50건을 검출하고 실패함(음성 대조) |
| 문자열 카탈로그·컴파일 테이블 | `python3 Tests/check_localizations.py --app …/Release/BTRemote.app` | PASS | 270키 en/ko, 참조 268키 존재 |
| swiftformat / swiftlint | `build.sh` 1~2단계 | NOT_RUN | 이 Mac에 도구가 설치되어 있지 않음 |
| 실기기 일반 모드 | Mac + iPhone | NOT_RUN | |
| 실기기 원격 모드 영어 입력 | Mac + iPhone | NOT_RUN | |
| 실기기 트랙패드 불변 | Mac + iPhone | NOT_RUN | |
| 실기기 포커스 독립 | Mac + iPhone | NOT_RUN | |
| 실기기 Caps Lock 한/영 | Mac + iPhone | NOT_RUN | |
| 실기기 Control + Space 대체 | Mac + iPhone | NOT_RUN | |
| 실기기 Mac 로컬 상태 | Mac + iPhone | NOT_RUN | |
| 실기기 키 복구 (단축키, 긴급 해제, UI, 메뉴 막대, 연결 해제, 종료) | Mac + iPhone | NOT_RUN | |
| 실기기 20회 반복 | Mac + iPhone | NOT_RUN | |

## 5. Caps Lock

**이벤트 경로:** 물리 Caps Lock → macOS `flagsChanged`(키코드 `0x39`, `maskAlphaShift` = 바뀐 잠금 상태) → `DirectInputEvent.capsLock(isOn:)` → `DirectInputCapsLockFilter`(같은 잠금 상태가 250 ms 안에 다시 오면 중복이나 release 메아리로 보고 무시) → `DirectInputKeyboardRouter`가 HID 키 `0x39`를 포함한 보고서를 보내고 60 ms 후 `0x39`를 뺀 보고서를 보냄 → BLE/Classic 키보드 보고서. 다른 키와 보조키는 같은 보고서에 유지된다. 캡처를 끄면 대기 중인 release를 취소하고 중립 보고서를 보낸다. Mac의 Caps Lock 잠금 비트는 iPhone 보조키로 전달하지 않는다.

**release를 지연한 이유:** macOS는 Caps Lock을 누를 때 이벤트 하나만 보내고 key-up을 따로 보내지 않는 것으로 알려져 있다. 또 BLE 백엔드는 대기 슬롯이 하나라서, press와 release를 연달아 보내면 press가 덮여 사라질 수 있다.

**iPhone 한/영 전환:** 미검증 (NOT_RUN). 자동 테스트는 `0x39` 전송만 확인하며, 실제 언어 전환은 iPhone 설정과 iOS 버전에 달려 있다.

**필요 설정:** iPhone에 한국어·영어 키보드를 추가하고, 설정 → 일반 → 키보드 → 하드웨어 키보드 → ‘Caps Lock으로 언어 전환’을 확인한다(iOS 버전에 따라 이름이나 제공 여부가 다를 수 있음). 같은 안내를 Setup의 "iPhone 한/영 전환" 도움말에 넣었다.

**한계:**
- 이벤트 탭은 Mac 앱으로 가는 이벤트만 막는다. Mac의 Caps Lock 잠금 상태와 LED는 하드웨어 수준에서 바뀔 수 있다. 앱이 샌드박스 상태라 원래 상태로 되돌리는 처리는 넣지 않았다.
- macOS에서 "Caps Lock으로 ABC 입력 소스 전환"을 켰다면 Mac 입력 소스도 함께 바뀔 수 있다. 실기기 확인이 필요하다.
- Apple 키보드의 Caps Lock 지연 때문에 아주 짧은 누름은 macOS가 무시할 수 있다. 이 경우 이벤트 자체가 오지 않는다.
- 잠금 상태가 바뀌지 않는 모드에서 250 ms 안에 두 번 누르면 두 번째 누름은 무시된다.
- 60 ms 유지 시간과 250 ms 중복 창은 추정값이며, 실기기에서 조정해야 할 수 있다.

**대체법:** `Control + Space`는 변경 없이 그대로 iPhone에 전달된다(기존 경로). 다른 키 조합으로 몰래 대체하지 않았다.

## 6. 안전성

| 상황 | 복구 방법 | 자동 검증 | 실기기 |
|---|---|---|---|
| 단축키 끄기 | `manager.toggle` → `stop()` → 탭 해제, `router.reset()` 중립 보고서 | PASS (20회) | NOT_RUN |
| `Control + Option` | `releaseShortcutPressed` → `stop()` | 디코더 PASS | NOT_RUN |
| UI 스위치 / 메뉴 막대 | `stop()` | 빌드만 확인 | NOT_RUN |
| Bluetooth 연결 해제 | `ContentView.onChange(hid.isConnected)`, `SetupView.onChange(hid.isActive)` → `stop()` | 관리자 재연결 PASS | NOT_RUN |
| 이벤트 탭 비활성화 | 콜백에서 `stop()`, 오류 표시 | 미검증 (OS 이벤트 필요) | NOT_RUN |
| 캡처 시작 실패 | 탭을 설치하지 않고 중립 보고서, 오류·로그 표시 | PASS | NOT_RUN |
| 앱 종료 | `willTerminate` → `shutdown()` → `stop()` | PASS | NOT_RUN |
| 창 닫기 | `ContentView.onDisappear` → `stop()` (기존 동작 유지) | 미검증 | NOT_RUN |

앱이 비정상 종료되면 프로세스와 함께 이벤트 탭도 사라지므로 Mac 키보드는 복구된다. 다만 iPhone에 남은 키를 해제하려면 iPhone 측 연결 해제 처리에 의존해야 하며, 이 부분은 확인하지 못했다.

## 7. 미해결 항목과 위험

1. **(높음) 실기기 검증 전부 NOT_RUN.** 특히 트랙패드 불변, Caps Lock 한/영, 20회 반복을 확인해야 한다.
2. **(높음) macOS의 Caps Lock 이벤트 모양.** 누를 때만 이벤트가 오는지, 뗄 때도 오는지, 입력 소스 전환 모드에서 어떻게 오는지는 실측하지 않았다. 필터가 두 경우를 모두 다루도록 설계했지만 확인이 필요하다.
3. **(중간) 원격 모드 중 Mac의 Caps Lock 잠금·입력 소스 변화.** 원복 처리가 없다.
4. **(중간) 60 ms 유지 시간.** iOS가 너무 짧은 누름을 무시하거나 길게 누른 것으로 판단할 가능성이 있다.
5. **(낮음) 토글 단축키 보조키의 순간 전달.** 단축키로 끌 때 보조키(⌘⇧ 등)가 잠깐 iPhone에 전달된 뒤 중립 보고서로 풀린다. 기존 동작과 같다.
6. **(낮음) 보호된 macOS 단축키.** Secure Input(암호 입력란) 중이나 OS 예약 단축키는 이벤트 탭이 받지 못할 수 있다. OS 제약이다.
7. **(낮음) Home/End/PageUp/PageDown, F13 이상, 키패드 등 매핑되지 않은 키.** 기존 키 맵 그대로라 전달되지 않는다. 범위 밖이라 그대로 두었다.
8. swiftformat/swiftlint를 실행하지 않았다.

## 8. 재현 절차

1. `git checkout experiment/claude` 후 `ci_scripts/ci_post_clone.sh`(xcodegen)를 실행하고 Xcode에서 macOS Release로 실행한다. 손쉬운 사용 권한은 직접 허용한다.
2. iPhone에서 BLE로 연결한다. iPhone에 한국어·영어 키보드를 추가하고, 하드웨어 키보드 설정의 Caps Lock 언어 전환 항목을 확인한다.
3. Setup → 원격 키보드 → "키보드를 기기로 보내기"를 켠다. 입력 대상이 "원격 기기 (iPhone)"로 바뀌고 메뉴 막대에 빨간 "키보드 → 기기"가 표시되는지 본다.
4. iPhone 메모 앱에 영어를 입력하고, Mac 앱에는 입력되지 않는지 확인한다.
5. Mac 트랙패드로 포인터 이동, 클릭, 드래그, 스크롤, 두·세 손가락 제스처를 해 본다. 다른 앱을 클릭한 뒤 다시 입력해도 iPhone으로 입력되는지 확인한다.
6. Caps Lock을 여러 번 눌러 한/영 전환과 입력 결과를 기록한다. Mac의 Caps Lock LED와 입력 소스 변화도 기록한다. 전환되지 않으면 `Control + Space` 결과를 기록한다.
7. `Control + Option`, 단축키, Setup 스위치, 메뉴 막대 "키보드를 Mac으로 되돌리기"로 각각 복귀한다. 복귀할 때마다 Mac 입력이 정상인지, iPhone에 눌린 키가 남지 않았는지 확인한다.
8. 전환을 20회 반복한다. 원격 모드에서 iPhone Bluetooth를 끄고, 앱을 종료한 뒤 Mac 키보드가 정상인지 확인한다.

상세 체크리스트는 `Tests/README.md`의 "MacBook + iPhone"에 있다.

## 9. 비교 가능 메트릭 (기준 `dc717cf` 대비 구현 커밋 `2d97d0b`)

| 항목 | 값 |
|---|---|
| 변경 파일 | 12개 (소스 8, 테스트 3, 문서 1). 이 보고서까지 13개 |
| 추가 / 삭제 행 | +915 / −244 (이 보고서 제외) |
| 신규 의존성 | 없음 |
| 자동 테스트 | 9개 묶음: Swift 하네스 6(이벤트 경로, 키보드 전용 마스크, 라우터, Caps Lock, 시작 실패, 단축키 관리자), Carbon 스모크 1, UI 정적 검사 1, 지역화 검사 1 |
| 통과 / 실패 | 9 / 0 |
| 실기기 테스트 | 0 / 9 실행 (전부 NOT_RUN) |
