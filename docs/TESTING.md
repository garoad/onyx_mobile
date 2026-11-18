# 검증 기록

실행일: 2026-11-18

자동 테스트는 독립적으로 구성한 MIDI·PMP2·ABKX·WAV 입력과 로컬 가상 앰프를
사용합니다. Bluetooth 타임스탬프 경계, Q16 값 보존, CRC, 파일 변환,
요청 직렬화·취소, 마지막 슬라이더 값 저장, 선택 복원과 읽기 검증을 포함합니다.
Flutter 화면 테스트는 작은 휴대폰, 가로 화면, 태블릿과 큰 글자 설정을 확인합니다.

## 실행 결과

| 검증 | 결과 |
| --- | --- |
| Dart 포맷 · `flutter analyze` | 통과, 분석 경고·오류 없음 |
| 자동 테스트 | 28개 모두 통과: MIDI 5, 프리셋 4, 파일 변환 4, 전송 4, 컨트롤러 7, 화면 4 |
| Android 네이티브 실행 | API 37 arm64 에뮬레이터에서 데모 편집·저장·프리셋 전환·전체 읽기·3개 슬롯 복원 검증 통과 |
| iOS 네이티브 실행 | iPhone 17 시뮬레이터에서 동일 흐름 통과 |
| Android 권한 · 검색 화면 | 근처 기기 권한 거절 안내 → 다시 검색 → 허용 → 네이티브 BLE 검색 시작 확인 |
| Android release APK | 설치·실행 통과, 앱 ID·버전 확인, APK v2 서명 검증 및 16 KB ZIP 정렬 검사 통과 |
| Android release AAB | 빌드 통과, 서명 없는 검토용 번들 |
| iOS simulator 앱 | 빌드·설치·실행 통과, 일반 앱 진입점으로 패키징 |
| iOS device release · xcarchive | 빌드·아카이브 통과, arm64, 서명·Team 없음 |
| 소스 ZIP | 네이티브 프로젝트·라이선스·잠금 파일 포함 확인, 캐시·개인 키 제외 확인, 새 경로에서 `flutter pub get --enforce-lockfile` 통과 |

검증 도구: Flutter 3.50.0, Dart 3.14.0, Xcode 26.6. Android 최소 SDK는
24(Android 7.0), target SDK 36, compile SDK 37이며 iOS 최소 버전은 15.0입니다.
앱 ID는 양쪽 모두 `io.onyx.pocket.editor`, 버전은 `0.1.0+1`입니다.

네이티브 흐름 검증은 실제 OS에서 실행한 Flutter 앱과 **로컬 가상 앰프**를
사용합니다. UI 조작과 전송·읽기 검증 로직을 확인한 결과이며, 실제 앰프의
Bluetooth 연결이나 DSP·오디오 결과를 확인한 결과로 해석하면 안 됩니다.
Android 권한·검색 확인도 주변의 실제 앰프를 발견하거나 GATT 통신을 한
검증은 아닙니다.

```sh
./tools/build.sh check
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d <에뮬레이터-또는-시뮬레이터-ID>
./tools/build.sh android
./tools/build.sh ios
python3 tools/package.py
```

`artifacts/manifest.json`에 배포 파일별 크기·SHA-256·서명 상태를 기록합니다.
패키징 도구는 APK·AAB·iOS ZIP·소스 ZIP의 모든 항목에 CRC 검사를 수행합니다.
화면 캡처는 `artifacts/screenshots/`에 있습니다. APK는 로컬 테스트용
Android Debug 키로 서명했고 AAB와 iOS 아카이브는 서명 전 파일입니다.
스토어 게시·TestFlight 배포는 수행하지 않았습니다.

## 실제 앰프에서 남은 확인

실제 Pocket AMP는 작업 환경에 없어 실기기 검증을 수행하지 않았습니다.
배포 전에 실제 Android/iPhone과 Onyx 앰프로 다음을 확인하세요.

- 권한 허용·거절 후 재시도, MIDI 기기 검색과 재연결
- 모델·파라미터 조절, 기기에서의 조절을 앱으로 동기화, 프리셋 저장
- 소수의 테스트 슬롯 백업·복원, 연결이 끊길 때 전송 중단
- 임시 IR, 새 IR 저장, 기존 IR 교체, 사용자 모델 관리
- 앱을 백그라운드로 보낸 뒤 복귀, 전원 끄기·켜기 후 재연결

실기기 전송을 시작할 때는 별도로 보관한 백업과 테스트 슬롯을 사용하세요.
