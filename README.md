# Onyx Mobile

Pocket AMP의 **Onyx 커스텀 펌웨어**를 위한 Android·iOS 모바일 앱입니다.
Flutter 화면과 Android/iOS의 네이티브 Bluetooth LE를 사용합니다. WebView나
브라우저의 Web Bluetooth API를 사용하지 않습니다.

| 화면 | 기능 |
| --- | --- |
| 톤 | 8개 이펙트, 모델·파라미터·바이패스, 체인 순서, 프리셋 전환·저장 |
| 설정 | 입력 게인·게이트, 출력, 리미터, 전체 EQ, 스테레오, USB 오디오 |
| 연주 | 그루브, 40개 리듬 패턴, 스톰프 버튼 지정, 앰프 튜너 제어 |
| NAM·IR | WAV → IR 변환, IR 임시 적용·저장·교체, 저장 모델 이름 변경·삭제, NAM 변환 |
| 프리셋 | 80개 프리셋 읽기, JSON 백업·공유, 순정 ABKX 변환, 선택 복원·검증 |

첫 화면의 **데모로 둘러보기**는 앰프 없이 화면과 프리셋 작업을 확인하는
로컬 데모입니다. 오디오를 재생하거나 Bluetooth에 연결하지 않습니다.

## 설치와 연결

Android 테스트 APK와 iOS 빌드 산출물은 `artifacts/`에 보관합니다.
Android 7.0 이상, iOS 15.0 이상을 대상으로 합니다.
Android APK를 휴대폰에 설치한 뒤 **앰프 연결**을 선택하고 근처 기기 권한을
허용하세요. iOS는 개발자 서명 후 Xcode 또는 TestFlight로 설치합니다.
시뮬레이터 빌드는 실제 iPhone에 설치할 수 없습니다.

앰프의 전원을 켜고 Bluetooth MIDI 기기를 선택하세요. 다른 편집 앱에
연결되어 있다면 먼저 그 연결을 종료해야 합니다. 목록에 기기가 보이지
않으면 **전체 BLE 기기** 검색을 사용하세요. Android 11 이하에서는 OS의
위치 권한과 위치 서비스가 필요합니다.

프리셋 읽기에는 Onyx **1.08 이상**, 확인 응답을 사용하는 프리셋 복원과
IR 전송에는 **1.13 이상**이 필요합니다. 원본 펌웨어와 동일하게 **NAM
업로드와 펌웨어 설치는 USB/PC 에디터에서** 진행합니다. 튜너 음정은
앰프 화면에서 확인합니다.

## 개발과 빌드

검증에 사용한 SDK는 **Flutter 3.50.0 / Dart 3.14.0**입니다. SDK와 패키지
버전은 [tools/toolchain.json](tools/toolchain.json), `pubspec.lock`에 기록합니다.
Android SDK와 JDK, iOS용 macOS·Xcode가 필요합니다. iOS 플러그인은 Swift
Package Manager로 연결합니다.

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d <명시한-기기-ID>
```

```sh
./tools/build.sh check
./tools/build.sh android
./tools/build.sh ios
python3 tools/package.py
```

Flutter가 PATH에 없으면 `FLUTTER_BIN=/path/to/flutter`를 지정하세요.
아이콘은 macOS에서 `swift tools/generate_icons.swift .`로 다시 생성합니다.
스토어용 서명과 배포 절차는 [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md)에
정리했습니다.

## 코드와 검증 범위

`lib/core/`는 MIDI·프리셋·파일 변환, `lib/services/`는 네이티브 BLE와
파일 입출력, `lib/ui/`는 Flutter 화면입니다. Android 권한 요청은 Kotlin,
iOS 설정 연결은 Swift로 구현했습니다. 프리셋 복원은 전송을 마친 뒤
각 슬롯을 다시 읽어 바이트 단위로 비교합니다. 응답이 없거나 검증이
실패하면 다음 슬롯을 덮어쓰지 않고 중단합니다.

자동 테스트와 빌드·시뮬레이터 검증 결과는 [docs/TESTING.md](docs/TESTING.md)에
기록합니다. **실제 Pocket AMP의 BLE 연결·전송·오디오 동작은 실기기로
추가 검증해야 합니다.**

네이티브 실행 검증은 Android 에뮬레이터 또는 iOS 시뮬레이터의 ID를 명시합니다.

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d <에뮬레이터-또는-시뮬레이터-ID>
```

배포 파일과 해당 버전의 소스 ZIP은 `artifacts/`에 생성됩니다.
`manifest.json`에는 각 파일의 SHA-256·크기·서명 구성을 기록합니다.
소스 ZIP에는 라이선스와 고정한 의존성 버전을 포함하며, 빌드 캐시·로컬 경로·
개인 서명 키를 제외합니다. 네이티브 실행 검증에서 촬영한 화면은
`artifacts/screenshots/`에 저장합니다.

## 원본과 라이선스

[Pocket-Onyx](https://github.com/28spawn/Pocket-Onyx)의 웹 에디터와 MIDI
문서를 참고해 Dart로 이식했습니다. 고정한 원본 커밋은
`8ebf3090d8df82a3f5e8806aec964c1e1e9079d1`이며 해시는
[vendor/onyx/upstream.json](vendor/onyx/upstream.json)에 있습니다.
앱에서 원본 HTML을 실행하지 않습니다.

Copyright © 2026 The Onyx Authors (@28spawn). 앱 소스는 **GPL-3.0-only**입니다.
자세한 내용은 [LICENSE](LICENSE), [vendor/onyx/NOTICE.md](vendor/onyx/NOTICE.md)를
확인하세요. 바이너리 배포 시 해당 버전의 소스와 빌드 지침도 함께 제공하세요.

개인정보 안내: [docs/PRIVACY.md](docs/PRIVACY.md).
