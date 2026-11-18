#!/usr/bin/env bash
set -euo pipefail
onyx_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$onyx_root"
onyx_flutter="${FLUTTER_BIN:-flutter}"
if ! command -v "$onyx_flutter" >/dev/null 2>&1; then
  onyx_flutter="$HOME/.local/share/onyx-mobile/flutter/bin/flutter"
fi
if [ ! -x "$onyx_flutter" ] && ! command -v "$onyx_flutter" >/dev/null 2>&1; then
  echo "Flutter 3.50.0 is required. Set FLUTTER_BIN to its executable." >&2
  exit 1
fi
onyx_flutter="$(command -v "$onyx_flutter")"
onyx_mode="${1:-check}"
mkdir -p artifacts
"$onyx_flutter" pub get
case "$onyx_mode" in
  check)
    "$(dirname "$onyx_flutter")/dart" format --output=none --set-exit-if-changed lib test integration_test test_driver
    "$onyx_flutter" analyze
    "$onyx_flutter" test
    ;;
  android)
    "$onyx_flutter" build apk --release
    cp build/app/outputs/flutter-apk/app-release.apk artifacts/Onyx-Mobile-0.1.0-Android.apk
    if [ -n "${ONYX_KEYSTORE_PATH:-}" ]; then
      "$onyx_flutter" build appbundle --release
    else
      ONYX_UNSIGNED_RELEASE=1 "$onyx_flutter" build appbundle --release
    fi
    cp build/app/outputs/bundle/release/app-release.aab artifacts/Onyx-Mobile-0.1.0-Android.aab
    ;;
  ios)
    "$onyx_flutter" build ios --simulator --debug
    ditto -c -k --keepParent build/ios/iphonesimulator/Runner.app artifacts/Onyx-Mobile-0.1.0-iOS-Simulator.zip
    "$onyx_flutter" build ios --release --no-codesign
    xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
      -destination 'generic/platform=iOS' -archivePath artifacts/Onyx-Mobile-0.1.0.xcarchive \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= archive
    ditto -c -k --keepParent artifacts/Onyx-Mobile-0.1.0.xcarchive artifacts/Onyx-Mobile-0.1.0-iOS-Archive.zip
    ;;
  *) echo "Usage: $0 [check|android|ios]" >&2; exit 2 ;;
esac
