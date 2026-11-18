# Android·iOS 배포

현재 앱 ID는 두 플랫폼 모두 `io.onyx.pocket.editor`, 표시 이름은
`Onyx Mobile`, 버전은 `0.1.0+1`입니다. 스토어 계정과 배포 서명은 저장소에
포함하지 않습니다. 이 저장소에서 빌드했다고 스토어에 게시되지는 않습니다.

## Android

`flutter build apk --release`는 배포 키가 없는 경우 로컬 테스트용 debug
키로 서명합니다. 휴대폰에 직접 설치할 수 있지만 Play 스토어용으로
사용하지 마세요. 최초 배포 전에 본인의 고유 앱 ID를 결정하세요.

Play용 키를 환경 변수로 설정하면 release APK와 AAB에 해당 키를 사용합니다.

```sh
export ONYX_KEYSTORE_PATH=/absolute/path/publisher.jks
export ONYX_KEY_ALIAS=onyx
# ONYX_KEYSTORE_PASSWORD와 ONYX_KEY_PASSWORD는 안전한 로컬 환경에서 설정
flutter build appbundle --release
```

서명하지 않은 검토용 AAB는 다음과 같이 생성합니다.

```sh
ONYX_UNSIGNED_RELEASE=1 flutter build appbundle --release
```

Play Console에서 앱을 만들고, 본인의 키로 서명한 AAB와 스토어 설명,
개인정보 처리방침 URL, 스크린샷을 등록합니다. 내부 테스트로 실제 앰프
검증을 마친 뒤 공개 배포합니다. 테스트 APK에 사용한 임시 debug 키는
배포 키로 전환하지 않습니다.

## iOS

```sh
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

Xcode의 Runner → Signing & Capabilities에서 Apple Developer Team과 본인의
Bundle Identifier를 설정하세요. 연결한 실제 iPhone을 명시적으로 선택해
앱을 실행하거나, Product → Archive 후 Organizer에서 App Store Connect로
전송하세요. 이후 TestFlight에서 검증하고 심사를 요청합니다.

`./tools/build.sh ios`가 만드는 `.xcarchive`는 **서명 전 보관 파일**입니다.
해당 아카이브를 Organizer에서 배포하거나 같은 소스를 본인의 Team으로
다시 Archive할 수 있습니다. 시뮬레이터용 `.app`과 ZIP은 실기기 설치용이
아닙니다. 서명 없는 IPA를 설치 가능한 파일로 제공하지 않습니다.

## 스토어 정보 초안

표시 이름: Onyx Mobile

설명: Pocket AMP의 Onyx 커스텀 펌웨어를 위한 모바일 톤 에디터입니다.
Bluetooth로 이펙트와 프리셋을 조절하고, 캐비닛 IR을 가져오고,
80개 프리셋을 파일로 백업·공유·복원할 수 있습니다. Onyx 커스텀 펌웨어와
호환되는 Pocket AMP가 필요합니다. NAM 업로드와 펌웨어 설치는 USB로
컴퓨터에서 진행합니다.

앱 내 계정, 광고, 분석·추적 기능은 없습니다. 개인정보 처리는
`docs/PRIVACY.md`와 실제 배포한 코드에 맞춰 기재하세요. 이 문서를
공개 URL로 게시하고 스토어에 등록할 수 있습니다.

GPL-3.0-only 원본을 사용하므로 해당 버전의 소스 ZIP, LICENSE, 빌드 지침을
바이너리와 함께 제공해야 합니다. 원본 저작권 표기와 라이선스를 유지하세요.
