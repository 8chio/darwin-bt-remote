# UniUniversalControl 구현 보고서 — Codex

## 1. 기준점

- 저장소: https://github.com/8chio/darwin-bt-remote
- 요구사항: `/Users/hok/Projects/UniUniversalControl/specs/REQUIREMENTS.md` v0.1 전체 확인.
- 시작 브랜치: `feature/direct-input-toggle`
- 시작 SHA: `dc717cfb1182deeecda5bcaf3659275ee5b224ee`
- 작업 위치: `/Users/hok/Projects/UniUniversalControl/codex-dev`
- 작업 브랜치: `experiment/codex`
- 착수 시 HEAD와 원본 브랜치가 모두 위 SHA이며 작업 트리가 깨끗한 것을 확인했다.
- 다른 AI와 시작 SHA가 동일하다는 사용자의 확인을 받았다. 다른 AI의 폴더·소스·결과에는 접근하지 않았다.
- 최종 SHA: 이 보고서를 포함하는 로컬 커밋. `git rev-parse experiment/codex`로 조회하며 최종 응답에도 실제 SHA를 기록한다.
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

## 9. 비교 가능 메트릭

- 기준 SHA 대비 변경 파일: 17개.
- 추가/삭제 행수: +822 / -157 (보고서 포함).
- 신규 외부 의존성: 0.
- 자동 동작/소스 검증: 6개 출력 그룹, 6 PASS / 0 FAIL.
- 별도 검사: 전체 소스 파싱 2개 PASS, BLE 타입 검사 1개 PASS, diff 검사 PASS.
- 앱 빌드: macOS/iOS 2개 BLOCKED (각 exit 65), 성공한 앱 빌드 0개.
- 실기기 검증: 0회, 전 항목 NOT_RUN.
- SwiftUI 최소 재현과 스타일 도구 부재는 환경 문제로 별도 기록했다.
