# UniUniversalControl 개발 결과 상세 보고서 — Codex

> **종합 판정: 소스 구현 및 일부 자동 검증 완료, 전체 제품 완료 조건 미달성.**
> 전체 앱 빌드 성공과 실제 Mac+iPhone 동작은 확인되지 않았다.
> 특히 UC-004.2의 종료 단축키 보조키 누출 방지는 현재 코드로 완전히 보장되지 않는다.

작성일: 2026-11-03. 이번 보고서 작성에서는 요구사항 전체, 현재 소스, 기준 SHA 대비 Git diff,
자동 테스트 소스 및 기존 `.build/validation/` 로그를 읽었다. 빌드·테스트를 새로 실행한 결과로
표시하지 않으며, 아래 실행 결과는 개발 단계에서 수행하고 보존한 결과이다.
보고서 작성 전 작업 트리는 깨끗했고, 원본 브랜치와 HEAD의 SHA를 다시 확인했다.
다른 AI의 작업 폴더에는 접근하지 않았다.

### 상태 표기의 의미

- **구현됨**: 실제 소스에 해당 경로가 존재한다. 실기기 성공을 의미하지 않는다.
- **부분 충족**: 구현·자동 검사 증거가 있으나 미구현 부분 또는 검증 공백이 있다.
- **PASS**: 명시한 범위의 검사만 통과했다.
- **BLOCKED**: 실행을 시도했으나 환경 등의 이유로 성공 검증을 마치지 못했다.
- **NOT_RUN**: 해당 실측을 수행하지 않았다.
- 아래 코드상 위험은 정적 검토 결과이며, 실제 iPhone에서 재현한 장애와 구분한다.

## 1. 기준점

- 저장소: https://github.com/8chio/darwin-bt-remote
- 요구사항: `/Users/hok/Projects/UniUniversalControl/specs/REQUIREMENTS.md` v0.1 전체 확인.
- 시작 브랜치: `feature/direct-input-toggle`
- 시작 SHA: `dc717cfb1182deeecda5bcaf3659275ee5b224ee`
- 작업 위치: `/Users/hok/Projects/UniUniversalControl/codex-dev`
- 작업 브랜치: `experiment/codex`
- 착수 시 HEAD와 원본 브랜치가 모두 위 SHA이며 작업 트리가 깨끗한 것을 확인했다.
- 다른 AI와 시작 SHA가 동일하다는 사용자의 확인을 받았다. 다른 AI의 폴더·소스·결과에는 접근하지 않았다.
- 최종 구현 커밋 SHA: `64264c29e2d83264b5eabc0bbdea632ae29b278d`
- 커밋 제목: `Implement macOS keyboard-only remote capture and Caps Lock HID support`
- 이 문서 작성으로 새 커밋은 생성하지 않았다. `DEVELOPMENT_REPORT.md`만 추가하고 기존 소스·테스트·보고서는 수정하지 않았다.
- 원본 브랜치와 라이선스는 유지했다. GitHub Push는 수행하지 않았다.

## 2. 구현 요약

macOS 이벤트 탭은 keyDown, keyUp, flagsChanged만 구독하며 포인팅 이벤트는 소비하지 않는다.
macOS 캡처 경로의 마우스 HID 전송, 커서 숨김, 포인터 연결 해제를 제거했다.
기존 단축키 저장·충돌 거부·중복 토글 방지를 유지하고, 긴급 해제는 시작 단축키 필터보다 먼저 원시 Control+Option 상태를 확인하도록 했다.
Caps Lock은 키코드 57의 flagsChanged 래치 변화마다 표준 HID 0x39 누름과 해제를 보내며 동일 상태와 반복 이벤트를 제거한다.
macOS 트랙패드 페이지, Classic 키보드의 트랙패드, 감도·스크롤·제스처 설정 진입점을 제거했다.
연결 상태, 입력 대상, 설정된 단축키, 긴급 해제 및 클릭 가능한 전환 버튼을 모든 탭 상단에 표시한다.
설정 탭이 사라진다는 이유만으로 캡처를 중단하던 처리를 제거하여 탭 전환과 입력 대상이 독립되도록 했다.
BLE 혼잡 시 누름/해제 보고서가 덮어써지는 기존 경로를 키보드 전용 FIFO로 보완했으며, 종료 시 대기 입력을 폐기하고 중립 보고서를 보낸다.
자동 검증은 통과했지만 전체 앱 빌드는 실행 환경 제한으로 BLOCKED이며 실기기 완료 조건은 NOT_RUN이다.

### 2.1 실제 입력 대상 전환 방식

Bluetooth 페어링을 끊었다가 다른 장치로 넘기는 방식이 아니다. Mac의 키보드 이벤트를
로컬 앱으로 통과시키거나 기존 Bluetooth HID 송신 경로로 보내도록 전환한다.

| 조작 | Mac → iPhone | iPhone → Mac | 구현 근거 |
|---|---|---|---|
| 설정한 전환 단축키 | 가능하도록 구현 | 가능하도록 구현 | `DirectInputShortcutManager.toggle(fromShortcut:)` |
| 앱 상단 전환 버튼 | 가능하도록 구현 | 가능하도록 구현 | `ContentView.keyboardStatus` |
| Setup의 키보드 토글 | 가능하도록 구현 | 가능하도록 구현 | `SetupView.directInputBinding` |
| Control + Option | **불가** | 긴급 해제 | `DirectInputShortcutEvent.isEmergencyRelease`, `intercept` |
| 캡처 중 메뉴 막대 아이콘 클릭 | 해당 없음 | 해제 | `releaseFromStatusItem` |

전환 단축키는 사용자가 별도로 설정한다. 예시 `Command + Shift + D`는 고정 기본값이 아니다.
`Control + Option`을 포함한 전환 단축키 등록은 긴급 해제 충돌로 거부한다.
이 조합만으로 양방향 전환하는 기능은 구현하지 않았으며, 기준 요구사항도 별도 토글과 긴급 해제를 구분한다.

### 2.2 미구현 또는 완료되지 않은 부분

| 항목 | 상태 | 설명 |
|---|---|---|
| 종료 토글의 모든 선행 보조키를 원격에 보내지 않기 | 보장 미구현 / UC-004.2 부분 충족 | 시작 단축키 억제는 있지만 종료 단축키가 완성되기 전 modifier 이벤트는 전달 가능 |
| Mac Caps Lock 래치·LED·입력 소스 원상 복원 | 미구현 | HID 키 해제와 별개인 macOS 로컬 상태를 강제로 복원하는 코드 없음 |
| 실제 물리 Caps Lock 이벤트 경로 및 iPhone 한/영 성공 확인 | NOT_RUN | 합성 이벤트 디코딩과 보고서 생성만 검사 |
| 실제 Control+Space 대체 전환 확인 | NOT_RUN | 디코딩은 검사, iPhone 반응은 미확인 |
| 전체 앱 빌드·실행·화면 렌더링 확인 | BLOCKED | SwiftUI 매크로 오류 때문에 완료하지 못함 |
| 실제 단절·탭 timeout·종료 후 키 고착 방지 확인 | NOT_RUN | 일부 상태 전이는 mock, 권한 실패는 실제 controller+권한 stub으로 검사 |
| 강제 종료·크래시에서 원격 중립 보고서 보장 | 불가능한 경우 존재 | 프로세스 실행이 끝나면 송신 코드를 실행할 수 없음 |

Windows/Android 확장, 클립보드 공유, ESP32, iPhone 현재 언어 조회는 이번 범위에 넣지 않았다.

### 2.3 UC-001~UC-005 요구사항별 판정

요구사항 전체를 실기기까지 **PASS**로 판정할 수 있는 상태는 아니다.
아래 번호는 REQUIREMENTS.md의 각 UC 하위 번호에 대응한다.

| 요구사항 | 소스 구현/증거 | 충족 판정 및 남은 검증 |
|---|---|---|
| UC-001.1 초기/해제 시 로컬 | `isCapturing=false`, `stop()`의 탭 제거 | 구현됨; 실제 로컬 입력 NOT_RUN |
| UC-001.2 연결 후 키보드만 전송 | 연결 검사 후 `sendKeyboard`, 키보드 전용 마스크 | 구현됨; 실제 Bluetooth 수신 NOT_RUN |
| UC-001.3 Mac 일반 키 입력 차단 | 캡처 중 해당 이벤트 callback은 nil 반환 | 구현됨; Secure Input 등 OS 제약과 실측 남음 |
| UC-001.4 포인터·클릭·드래그·스크롤·제스처 | 포인팅 이벤트 구독 및 커서 조작 제거 | 코드/마스크 검사 PASS; 물리 장치 NOT_RUN |
| UC-001.5 포커스 독립 | Setup onDisappear stop 제거; 포커스 연동 전환 없음 | 구현됨; 앱/창 전환 실측 NOT_RUN |
| UC-001.6 포인팅 소비/마우스 보고서 없음 | macOS 캡처 경로에 sendMouse/MouseReport 없음 | 해당 소스 경계·디코더 검사 PASS; 공유 backend 마우스 정의는 보존 |
| UC-001.7 키/보조키 상태 정리 | 키 상태 초기화, backend release 또는 zero | 부분 충족; 원격 고착 실측 및 Mac Caps 상태 복원 미완료 |
| UC-002.1 원격 트랙패드 UI 제거 | 키보드 페이지·Classic 패널의 macOS 경로 제거 | 소스 검사 PASS; 화면 실행 확인 BLOCKED |
| UC-002.2 감도·스크롤·제스처 설정 제거 | Settings 관련 Section은 iOS에서만 생성 | 소스 검사 PASS; 렌더링 미검증 |
| UC-002.3 제거/보존 범위 보고 | 파일별 설명과 보존 범위 명시 | 문서 충족 |
| UC-002.4 HID 연결·토글 유지 | Classic/descriptor 보존, manager 회귀 테스트 | 부분 충족; BLE 공유 backend 변경 실기기 회귀 NOT_RUN |
| UC-003.1 Caps Lock press/release·중복 방지 | keyCode 57 flagsChanged → HID 0x39 2개 보고서 | 보고서 검사 PASS; 물리 이벤트 경로는 NOT_RUN이므로 부분 충족 |
| UC-003.2 Mac/iPhone 언어 상태 분리 | 현재 입력 언어를 조회·동기화하지 않음 | 설계상 충족 |
| UC-003.3 iPhone 설정 안내 | 한국어/영어 Caps 도움말 문자열 | 문구 구현됨; 실제 옵션 존재는 iOS별 확인 필요 |
| UC-003.4 Mac 로컬 Caps/입력 소스 영향 | 강제 복원 로직 없음; 제약 문서화 | NOT_RUN / 미완료 |
| UC-003.5 Control+Space 대체 안내·테스트 | Ctrl+Space 디코딩 회귀 및 도움말 | 안내/디코딩 완료, iPhone 테스트 NOT_RUN |
| UC-003.6 언어 조회/자동 성공 가정 금지 | 보고서 생성과 실제 언어 전환을 별도 표기 | 충족 |
| UC-004.1 설정·충돌·중복 토글 유지 | 기존 hotkey/monitor 보존, manager mock 20회 반복 | 자동 검사 PASS; 실제 Carbon 전달 NOT_RUN |
| UC-004.2 시작/종료 단축키 누출 방지 | 시작 chord suppression, 종료 본키 차단·zero | **부분 충족: 종료 선행 보조키 누출을 막는 보장 없음** |
| UC-004.3 긴급 해제와 클릭 해제 | 원시 Ctrl+Option 우선 확인, 상단/메뉴 막대 버튼 | 구현됨; 실제 입력/클릭 NOT_RUN |
| UC-004.4 단절·탭 실패·종료 복구 | stop 공통 경로, 탭 무효화, BLE 큐 폐기/zero | 부분 검사 PASS; 실제 단절·timeout·종료 NOT_RUN |
| UC-004.5 시작 실패 시 로컬/오류 | 권한·tap/source/enable 실패 정리 및 lastError | 권한 실패 20회 PASS; 실제 tap 생성/활성화 실패 실측 없음 |
| UC-004.6 포커스/클릭으로 대상 불변 | 포커스 해제 처리 없음, Setup disappear 처리 제거 | 소스상 구현됨; 실기기 NOT_RUN |
| UC-005.1 상태·대상·단축키·해제 표시 | 모든 탭 상단 상태 영역 | 구현됨; 실제 표시/레이아웃 BLOCKED |
| UC-005.2 키보드 전용 문구 | macOS용 L10n 및 en/ko 문자열 추가 | 구현됨; 앱 전체 문구/레이아웃 실측 없음 |
| UC-005.3 포인터 숨김/방해 제거 | NSCursor/CGAssociate 호출 제거 | 소스 검사 PASS |
| UC-005.4 Caps Lock 도움말 | DisclosureGroup에 설정·제약·대체법 | 문구 구현됨; 실행 UI 미검증 |

**UC별 요약:** UC-001은 코드 구현·일부 자동 검사 완료, UC-002와 UC-005는 소스/UI 구성 변경 완료이나
앱 빌드/화면 검증 미완료, UC-003은 HID 보고서 생성 완료·실제 한/영 전환 미검증,
UC-004는 복구 경로와 일부 회귀 검사 완료이나 단축키 보조키 누출 방지 및 실측에 미완료 항목이 있다.

## 3. 파일별 변경사항 및 제거/보존 범위

| 파일 | 목적 |
|---|---|
| `BTRemote/DirectInputController.swift` | 키보드 전용 캡처·디코더, Caps Lock 상태/보고서, 원시 긴급 해제, 실패 중립화, 메뉴 막대 클릭 해제 |
| `BTRemote/DirectInputShortcutManager.swift` | 연결 해제 시 공통 stop 경로, 재연결 시 자동 캡처 없음 |
| `BTRemote/HIDInput.swift` | BLE 큐 폐기용 releaseKeyboard 연결, 전원 상태를 연결/활성 판단에 반영 |
| `BTRemote/LowEnergy/HIDPeripheral.swift` | 키보드 순서 보존 전송, 종료·전원·구독 변경 정리, 혼잡 오류 표시 |
| `BTRemote/LowEnergy/KeyboardReportBuffer.swift` | 256 delivery 상한 FIFO, report/boot 순서, overflow 중립화 |
| `BTRemote/ContentView.swift` | 모든 탭의 상태·전환·Caps Lock 도움말, 연결/백엔드 오류 복구 |
| `BTRemote/SetupView.swift` | 설정 탭을 떠나는 것만으로 캡처 중단하지 않음 |
| `BTRemote/KeyboardView.swift` | macOS 트랙패드 페이지 숨김, 이전 선택값 1을 키보드로 이동 |
| `BTRemote/ClassicKeyboardView.swift` | macOS TrackpadPanel 제거 |
| `BTRemote/SettingsView.swift` | macOS 감도·스크롤·제스처 UI 제거 |
| `BTRemote/L10n.swift`, `BTRemote/Localizable.xcstrings` | macOS 키보드 전용 문구, 한국어/영어 상태·도움말 |
| `Tests/DirectInputShortcutTests.swift` | 기존 회귀 및 신규 보고서/복구/FIFO 검증 |
| `Tests/run-direct-input-shortcut-tests.sh` | 실제 FIFO 소스도 테스트에 포함 |
| `Tests/verify-keyboard-only-ui.py` | macOS 조건부 UI와 포인터 API 부재 검사 |
| `Tests/README.md` | 테스트 실행법과 검증 한계 |
| `IMPLEMENTATION_REPORT.md` | 결과·미검증 항목·재현 절차 |

삭제한 사용자 기능은 **macOS 원격 트랙패드 및 마우스 제어 UI/캡처**이다.
iOS의 트랙패드 화면과 Direct Input 구현은 보존했다. iOS DirectInputController 부분은 기준 SHA와 동일한 것을 비교했다.
공유 HID descriptor, Classic 페어링/연결 코드, 마우스·digitizer 보고서 정의, 리모컨 미디어 키, 화면 키보드는 보존했다.
트랙패드 관련 소스 파일은 iOS에서 사용하므로 삭제하지 않았다. BLE 키보드 큐 변경은 공유 백엔드에도 적용되므로 iOS 송신 측 회귀 검증이 추가로 필요하다.

### 3.1 Git 기준 전체 변경·삭제 파일

`git diff --name-status dc717cfb1182deeecda5bcaf3659275ee5b224ee HEAD`를 직접 확인했다.
파일 자체 삭제(D)는 **0개**이며, 기능 제거는 기존 파일의 macOS 코드 삭제/조건부 컴파일로 수행했다.

| Git 상태 | 경로 |
|---|---|
| M — 수정 | `BTRemote/ClassicKeyboardView.swift` |
| M — 수정 | `BTRemote/ContentView.swift` |
| M — 수정 | `BTRemote/DirectInputController.swift` |
| M — 수정 | `BTRemote/DirectInputShortcutManager.swift` |
| M — 수정 | `BTRemote/HIDInput.swift` |
| M — 수정 | `BTRemote/KeyboardView.swift` |
| M — 수정 | `BTRemote/L10n.swift` |
| M — 수정 | `BTRemote/Localizable.xcstrings` |
| M — 수정 | `BTRemote/LowEnergy/HIDPeripheral.swift` |
| A — 신규 | `BTRemote/LowEnergy/KeyboardReportBuffer.swift` |
| M — 수정 | `BTRemote/SettingsView.swift` |
| M — 수정 | `BTRemote/SetupView.swift` |
| A — 신규 | `IMPLEMENTATION_REPORT.md` |
| M — 수정 | `Tests/DirectInputShortcutTests.swift` |
| M — 수정 | `Tests/README.md` |
| M — 수정 | `Tests/run-direct-input-shortcut-tests.sh` |
| A — 신규 | `Tests/verify-keyboard-only-ui.py` |

총 17개 = 기존 파일 수정 14개 + 신규 파일 3개, +822/-157줄이다.
이번에 추가하는 `DEVELOPMENT_REPORT.md`는 위 구현 커밋 통계에 포함하지 않는다.
`DirectInputHotkey.swift`, `DirectInputHotkeyMonitor.swift`, `Classic/HIDClassicDevice.swift`,
`LowEnergy/HIDProfile.swift`, `LICENSE`는 기준 커밋과 동일한 것을 직접 비교했다.

## 4. 검증 결과

환경: macOS 27.0.1 (26A434), arm64, Xcode 27.1 (27A9275), Swift 6.4.
실제 Mac 모델·iPhone 모델/iOS·Bluetooth 모드·키보드 설정 조합은 실기기 검증 시 별도 기록해야 한다.

| 테스트/검사 | 명령 또는 범위 | 결과 | 근거/한계 |
|---|---|---|---|
| Swift 회귀/신규 테스트 | `bash Tests/run-direct-input-shortcut-tests.sh` | PASS | 출력 5개 그룹 모두 PASS; 20회 토글, 20회 권한 실패, 추가 backend reset 검사 |
| UI 소스 경계 | `python3 Tests/verify-keyboard-only-ui.py` | PASS | 1개 그룹; 렌더링/마우스 실측이 아닌 조건부 소스 검사 |
| BLE 실제 소스 타입 검사 | 아래 명령 | PASS | HIDPeripheral·FIFO·HIDReports 등 Swift 6 타입 검사 |
| macOS/iOS 전체 Swift 파싱 | `swiftc -frontend -parse -swift-version 6 -target … -sdk …` + 전체 Swift 파일 | PASS | 두 플랫폼 각각 exit 0; 타입 검사/링크 대체 아님 |
| Xcode 프로젝트 생성 | `xcodegen generate` | PASS | 로컬 생성 프로젝트는 기존 .gitignore에 따라 제외 |
| macOS Release 앱 빌드 | 아래 xcodebuild 명령 | BLOCKED | exit 65, nested sandbox 실패로 SwiftUI StateMacro 실행 불가 |
| iOS Release 앱 빌드 | 아래 xcodebuild 명령 | BLOCKED | exit 65, 같은 SwiftUI 매크로 실패 |
| 최소 SwiftUI 재현 | `swiftc -typecheck -swift-version 6 -module-cache-path .build/ModuleCache .build/SwiftUIMacroProbe.swift` | BLOCKED | 5줄 @State 예제도 동일 실패. OS 권한 우회/샌드박스 해제는 하지 않음 |
| diff 공백/충돌 | `git diff --check` | PASS | 공백 오류 없음 |
| 실제 OS 이벤트 탭·Carbon 등록 | 실제 사용자 세션 | NOT_RUN | OS 권한 승인·입력 주입을 수행하지 않음 |
| Mac 로컬/원격 입력·마우스·제스처·앱 포커스 | 실제 Mac+iPhone | NOT_RUN | 자동 검사로 실기기 정상 동작을 확정하지 않음 |
| Caps Lock 한/영·Control+Space·Mac Caps 상태 | 실제 Mac+iPhone | NOT_RUN | HID 보고서 생성과 실제 수신/언어 전환은 별개 |
| 실제 Bluetooth 단절·재연결·종료·20회 반복 | 실제 Mac+iPhone | NOT_RUN | manager 상태 전이는 mock 검사만 수행 |
| SwiftLint/SwiftFormat | 기존 build.sh의 스타일 단계 | BLOCKED | 도구가 설치되어 있지 않음; 새 의존성 설치 안 함 |

```sh
swiftc -typecheck -swift-version 6 -module-cache-path .build/ModuleCache \
  BTRemote/AppSettings.swift BTRemote/L10n.swift \
  BTRemote/LowEnergy/HIDReports.swift BTRemote/LowEnergy/HIDProfile.swift \
  BTRemote/LowEnergy/KeyboardReportBuffer.swift BTRemote/LowEnergy/HIDPeripheral.swift

xcodebuild -project BTRemote.xcodeproj -scheme BTRemote -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project BTRemote.xcodeproj -scheme BTRemote -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

전체 로그는 로컬 `.build/validation/`에 있다: `automated-tests.log`, `ui-boundaries.log`,
`backend-typecheck.log`, `parse.log`, `macos-build.log`, `ios-build.log`, `macro-probe.log`.
컴파일러의 대표 오류는 `sandbox-exec: sandbox_apply: Operation not permitted` 및
`SwiftUIMacros.StateMacro … swift-plugin-server … malformed response`이다.
실패한 @State 확장 이후 `$tab` 미해결·불변 self·기존 연결 알림 버튼 타입 검사 시간 초과도 함께 발생했다.
이러한 후속 오류가 정상 환경에서 사라지는지는 전체 빌드로 재확인해야 한다.
따라서 앱 빌드 성공, UI 렌더링 성공, Bluetooth 실제 전송 성공을 주장하지 않는다.

## 5. Caps Lock 구현과 제약

시작 시 macOS Caps Lock 플래그를 샘플링한다. 키코드 0x39(57)의 flagsChanged가 이전 래치와 달라지면,
HID usage 0x39를 포함하는 보고서와 이를 제외한 보고서를 연속 생성한다.
동일 래치 이벤트, autorepeat, 별도의 Caps keyDown/keyUp은 중복 전송하지 않는다.
동시에 누른 일반 키와 보조키를 보존하며 6키가 이미 눌린 경우 Caps 보고서에 한 슬롯을 확보한 다음 기존 키를 복원한다.
테스트는 생성된 보고서 바이트를 확인했다. 실제 물리 Caps Lock 이벤트 및 iPhone 한/영 전환은 미검증이다.

사용자는 iPhone에 한국어·영어 키보드를 추가하고, 연결 후 설정 → 일반 → 키보드 → 하드웨어 키보드에서
Caps Lock 언어 전환 옵션의 존재/활성을 확인해야 한다. 이름·제공 여부는 iOS와 기기에 따라 다를 수 있다.
Mac 입력 소스와 iPhone 입력 소스가 같다고 가정하지 않으며, Bluetooth HID로 iPhone의 현재 언어를 읽지 않는다.
macOS 입력 소스 단축키/재매핑이 Caps Lock을 먼저 처리하거나 래치 변화 없는 이벤트를 만들면 이 경로가 동작하지 않을 수 있다.
이벤트 탭은 하위 하드웨어 래치·LED·로컬 입력 소스 변경까지 되돌리지 않는다. 짧은 누름/긴 누름과 Mac 상태를 실제로 확인해야 한다.
대체 조작은 Control+Space이며 **자동으로 Caps Lock을 이 조합으로 바꾸지는 않는다**.
Apple의 [iPhone 외장 키보드 안내](https://support.apple.com/guide/iphone/switch-between-keyboards-iph5948b3f2e/ios)는 Control+Space를 안내한다.
[Apple iPad 안내](https://support.apple.com/en-euro/guide/ipad/ipaddd28d7ed/ipados)는 한국어 등의 Caps Lock 전환 설정을 설명하지만 iPhone 실측의 근거로 사용하지 않았다.

## 6. 안전성

stop은 먼저 캡처 상태를 끄고 이벤트 탭을 비활성화·무효화하며 run-loop source를 제거한다.
키 상태와 시작 단축키 억제를 초기화하고 backend releaseKeyboard 또는 중립 KeyboardReport를 호출한다.
BLE releaseKeyboard는 대기 중인 타이핑을 버리고 중립 보고서만 전송/대기시킨다.
Bluetooth 단절·전원 비활성·백엔드 오류·정상 앱 종료·창 닫기·UI 해제·긴급 해제·탭 비활성화는 stop으로 수렴한다.
권한/탭 생성/소스 생성/탭 활성화 실패도 로컬 입력을 캡처한 채 남기지 않으며 오류를 표시한다.
권한 실패 경로는 실제 controller로, manager 종료/연결 상태 전이는 mock으로 확인했다.
실제 탭 timeout과 정상 캡처 후 OS 복귀는 NOT_RUN이다.
프로세스 강제 종료/크래시에서는 앱이 중립 보고서를 보낼 수 없다. OS 탭 제거 후 로컬 복귀 및 원격 호스트의 연결 끊김 처리는 실측이 필요하다.
완전히 끊긴 Bluetooth 연결에는 보고서를 전달할 수 없으며 재구독용 키보드 캐시는 중립화한다.

## 7. 미해결 항목과 위험

- **P0 / BLOCKED:** 일반 터미널/Xcode에서 전체 macOS/iOS 빌드·링크 재확인이 필요하다. 현재 환경에서는 SwiftUI 매크로 실행이 차단되어 앱 완료 조건을 확정할 수 없다.
- **P0 / NOT_RUN:** 실제 iPhone 수신, Caps Lock 한국어/영어 전환, Mac Caps/입력 소스 영향, 마우스와 멀티터치 유지, 포커스 독립성, 복구 실측.
- **P0 / NOT_RUN:** Secure Input·로그인/권한 화면·macOS 보호/예약 단축키는 session event tap보다 먼저 처리되거나 캡처를 우회할 수 있다. 이 경우 키보드 전용 전송을 보장하지 않는다.
- **P1 / NOT_RUN:** BLE congestion, boot/report 구독, 재페어링, 다중 호스트 및 iOS 송신 측 공유 백엔드 회귀 검증.
- **P1:** 128개 키보드 보고서(256 delivery)를 넘는 혼잡은 입력을 버리고 중립화하며 오류를 표시한다. 전송이 재개되기 전에는 원격 키 해제가 지연될 수 있다.
- **P1:** 6키 동시 입력 중 Caps Lock은 한 키를 잠시 보고서에서 제외했다가 복원한다. 해당 키의 원격 반복 동작은 재확인이 필요하다.
- 자동 테스트는 실제 OS 포인터, 물리 키, Bluetooth 송수신, 언어 상태의 성공을 보증하지 않는다.

### 7.1 이번 소스 재검토에서 확인한 보완 필요 사항

다음은 코드를 수정하지 않고 기록한 정적 검토 결과이다. 기존 구현의 의도와 실제 보장 범위를 구분한다.

1. **종료 단축키 선행 modifier 보고서 — UC-004.2 부분 충족.**
   `DirectInputController.intercept`는 토글을 일반 키의 keyDown에서 판정한다.
   그 전에 Command/Shift 등을 누르면 flagsChanged가 `DirectInputKeyboardState.handle`로 전달되어
   해당 보조키를 포함한 보고서를 생성할 수 있다. 예를 들어 시작 단축키 억제가 이미 해제된 원격 세션에서
   Command → Shift → D로 종료하면 D가 눌리기 전 보조키 보고서는 전송 경로에 들어갈 수 있다.
   stop의 중립 보고서는 최종 눌림 상태 정리이므로 앞서 전달된 이벤트를 취소하지는 않는다.
   기존 `DirectInputShortcutSuppression`은 시작 chord를 대상으로 하며 종료 chord 전체를 예측해 보류하지 않는다.
   따라서 “단축키 키코드·보조키가 전혀 새지 않는다”는 완료 판정은 부적절하다. 실제 iPhone 부작용은 미재현이다.

2. **연결 표시와 키보드 전송 준비의 차이.**
   `HIDInput._lowEnergy.isConnected`는 active connectedCentrals 또는 central.connected를 사용한다.
   실제 `HIDPeripheral.drainKeyboardReports`는 구독된 characteristic이 있는 수신자에게만 보낸다.
   따라서 연결 플래그만으로 키보드 구독 완료/수신 가능을 확정할 수 없다. 구독 전 또는 부분 구독에서
   캡처가 켜지고 보고서는 보내지 못하는 상황이 가능한지 검증해야 한다. 기존 연결 판단의 실기기 한계다.

3. **구독 변경 때 FIFO 전체 초기화.**
   didSubscribeTo/didUnsubscribeFrom은 키보드 외 characteristic 변경에도 keyboardBuffer를 비운다.
   혼잡으로 key-up이 대기하는 동안 다른 구독이 바뀌면 그 release가 제거될 수 있다.
   캐시를 zero로 바꾸는 것과 기존 수신자에게 즉시 neutral을 보내는 것은 다르다.
   FIFO 단위 테스트는 이 CoreBluetooth callback 조합을 검증하지 않으므로 재구독/다중 호스트 회귀 위험으로 남긴다.

4. **전역 키 가로채기의 범위.**
   Mac 일반 문자 입력을 막도록 설계했지만 `.cgSessionEventTap`보다 먼저 처리되는 시스템 키,
   Secure Input, 키 재매핑·입력 소스 처리까지 보장하지 않는다. 매핑 표에 없는 키는 캡처 중
   Mac 이벤트가 소비되면서 원격 보고서는 생성되지 않을 수 있다.
   보조키 매핑은 통합 flags를 leftCtrl/leftShift/leftAlt/leftGUI로 바꾸므로 좌/우 보조키 구분도 보존하지 않는다.
   이 키 매핑 특성은 기준 구현에서 유지된 범위이며, 이번 보고서 작업에서 수정하지 않았다.

5. **자동 테스트 범위의 제한.**
   6 PASS는 6개의 로그 출력 그룹이지 실제 기기 시험 6회나 독립 XCTest 6개가 아니다.
   UI 검사는 소스 문자열/조건부 경로 검사이며 실행 화면 검사도 컴파일 성공 증거도 아니다.
   controller 권한 실패는 테스트용 `AccessibilityPermission.isTrusted=false`를 사용한다.
   정상 event tap 설치·실제 긴급 해제·tap timeout·Carbon 이벤트 전달은 시험하지 않았다.
   backend-typecheck.log는 성공 시 출력이 없는 파일이며, 성공 판정은 개발 당시 exit 0 기록과 함께 해석했다.

이 사항 때문에 본 보고서는 **“모든 P0 완료” 또는 “실사용 검증 완료”로 결론 내리지 않는다**.
후속 수정·실기기 확인이 필요한 항목을 기록했으며, 사용자의 이번 지시에 따라 추가 코드는 변경하지 않았다.

## 8. 실기기 재현 절차

1. 일반 터미널에서 위 프로젝트 생성/빌드와 두 자동 테스트 명령을 실행한다. 실행 앱의 접근성/Bluetooth 권한과 페어링은 사용자가 직접 승인한다.
2. Mac 모델/macOS, iPhone 모델/iOS, BLE 또는 Classic 모드, 한국어·영어 및 Caps Lock 설정 상태를 기록한다.
3. Mac 텍스트 편집기에서 로컬 키보드·클릭·드래그·스크롤·멀티터치가 정상인지 확인한다.
4. iPhone 텍스트 입력란을 선택하고 기존 설정 가능한 단축키 또는 상단 버튼으로 원격 키보드를 켠다. 영어 입력이 iPhone에만 나타나는지 확인한다.
5. Mac 트랙패드로 다른 앱/창/탭을 클릭하고 스크롤·드래그·두/세 손가락 제스처를 사용한다. 키보드 대상은 원격으로 유지되어야 한다.
6. Caps Lock 짧게/길게/연속 누름으로 한국어↔영어를 반복하고 실제 입력 결과, iPhone 설정, Mac 입력 소스·Caps LED 상태를 기록한다. Control+Space 반응도 별도 기록한다.
7. 같은 단축키, Control+Option, 상단 버튼, 메뉴 막대 아이콘 각각으로 해제한다. Shift/Control/Option/Command/일반 키를 누른 상태에서 해제 후 고착 여부도 확인한다.
8. 원격 입력 중 Bluetooth 끊기·재연결·Bluetooth 전원 끄기·앱 정상 종료·창 닫기를 각각 시험한다. 재연결만으로 캡처가 다시 켜지면 안 된다.
9. 최소 20회 모드 전환하고 각 항목을 PASS/FAIL/BLOCKED/NOT_RUN으로 기록한다. 실패 시 모드·키 순서·설정·로그를 함께 남긴다.

### 8.1 실기기 결과 기록표

| 검증 항목 | 현재 결과 | 기록해야 할 내용 |
|---|---|---|
| 로컬 키보드·트랙패드·마우스 | NOT_RUN | 초기/해제 상태에서 Mac 입력 |
| 원격 영어 입력 및 Mac 중복 입력 차단 | NOT_RUN | 동일한 테스트 문자열의 양쪽 결과 |
| 좌/우 클릭·드래그·스크롤·2/3손가락 제스처 | NOT_RUN | 원격 모드 중 Mac 정상 동작 |
| 다른 Mac 앱·창으로 포커스 이동 | NOT_RUN | 키보드는 iPhone으로 유지되는지 |
| Caps Lock 한/영 전환 | NOT_RUN | 짧게/길게/반복 누름, 실제 한국어·영어 문자열 |
| Control+Space 대체 전환 | NOT_RUN | iPhone 반응 및 Mac 예약 단축키 간섭 |
| Mac Caps LED·입력 소스 변화 | NOT_RUN | 전환 전/후 및 캡처 종료 후 상태 |
| 시작/종료 단축키 이벤트 누출 | NOT_RUN | 본키뿐 아니라 보조키만 누른 단계의 iPhone 반응 |
| Ctrl+Option·UI·메뉴 막대 해제 | NOT_RUN | 키 고착과 로컬 복귀 여부 |
| Bluetooth 단절·전원 꺼짐·재연결 | NOT_RUN | 즉시 로컬 복귀, 재연결 자동 캡처 금지 |
| 앱 정상 종료·창 닫기·탭 비활성화 | NOT_RUN | Mac/원격 키 상태 복구 및 오류 표시 |
| 최소 20회 모드 전환 | NOT_RUN | 회차별 성공/실패와 키 고착 여부 |
| 혼잡·구독 변경·boot/report 경로 | NOT_RUN | 키 눌림/해제 유실, 재구독 중립 상태 |
| iOS 송신 측 공유 BLE 회귀 | NOT_RUN | 보존한 iOS 기능에 대한 영향 |

## 9. 비교 가능 메트릭

- 기준 SHA 대비 변경 파일: 17개.
- 추가/삭제 행수: +822 / -157 (보고서 포함).
- 신규 외부 의존성: 0.
- 자동 동작/소스 검증: 6개 출력 그룹, 6 PASS / 0 FAIL.
- 별도 검사: 전체 소스 파싱 2개 PASS, BLE 타입 검사 1개 PASS, diff 검사 PASS.
- 앱 빌드: macOS/iOS 2개 BLOCKED (각 exit 65), 성공한 앱 빌드 0개.
- 실기기 검증: 0회, 전 항목 NOT_RUN.
- SwiftUI 최소 재현과 스타일 도구 부재는 환경 문제로 별도 기록했다.
