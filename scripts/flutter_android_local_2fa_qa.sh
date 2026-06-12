#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PACKAGE_NAME="net.yoshida.morebettergakujo"
APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
ARTIFACT_DIR="$ROOT_DIR/build/qa"
ADB_BIN="${ADB:-adb}"
TEST_SECRET="GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
DEBUG_URL="file:///android_asset/qa/two_factor.html"

find_executable() {
  local candidate="$1"
  shift

  if command -v "$candidate" >/dev/null 2>&1; then
    command -v "$candidate"
    return 0
  fi

  for path in "$@"; do
    if [[ -x "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  return 1
}

resolve_adb() {
  local default_sdk_home="$HOME/Library/Android/sdk"
  local sdk_home="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$default_sdk_home}}"

  if [[ "${ADB:-}" == "" ]]; then
    if resolved_adb="$(find_executable adb "$sdk_home/platform-tools/adb" "$default_sdk_home/platform-tools/adb")"; then
      ADB_BIN="$resolved_adb"
    fi
  fi
}

print_tooling_help() {
  cat <<EOF
Android platform-tools adb was not found.

Install Android SDK Platform-Tools, or rerun with:
  ADB=/path/to/adb $0

Common macOS path:
  ADB="\$HOME/Library/Android/sdk/platform-tools/adb" $0
EOF
}

print_device_help() {
  cat <<EOF
No adb device or emulator is connected.

Start an Android emulator from Android Studio Device Manager, then rerun:
  ADB="$ADB_BIN" $0
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --secret)
      TEST_SECRET="${2:?Missing value for --secret}"
      shift 2
      ;;
    --serial)
      SERIAL="${2:?Missing value for --serial}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

resolve_adb
mkdir -p "$ARTIFACT_DIR"

if [[ ! -f "$APK_PATH" ]]; then
  (cd "$ROOT_DIR" && flutter build apk --debug)
fi

if ! command -v "$ADB_BIN" >/dev/null 2>&1 && [[ ! -x "$ADB_BIN" ]]; then
  print_tooling_help
  exit 1
fi

set +e
adb_devices_output="$("$ADB_BIN" devices 2>&1)"
adb_devices_status="$?"
set -e
if [[ "$adb_devices_status" -ne 0 ]]; then
  printf '%s\n' "$adb_devices_output"
  if [[ "$adb_devices_output" == *"Operation not permitted"* ]]; then
    cat <<EOF
adb was found, but its daemon could not open the local socket.
Run this QA script from a normal terminal:
  cd "$ROOT_DIR"
  ADB="$ADB_BIN" $0
EOF
  fi
  exit 1
fi

DEVICES=()
while IFS= read -r serial; do
  DEVICES+=("$serial")
done < <(printf '%s\n' "$adb_devices_output" | awk 'NR > 1 && $2 == "device" {print $1}')
if [[ "${#DEVICES[@]}" -eq 0 ]]; then
  print_device_help
  exit 1
fi

SERIAL="${SERIAL:-${DEVICES[0]}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

echo "Using adb serial: $SERIAL"
"$ADB_BIN" -s "$SERIAL" install -r "$APK_PATH"
"$ADB_BIN" -s "$SERIAL" logcat -c || true
"$ADB_BIN" -s "$SERIAL" shell am force-stop "$PACKAGE_NAME" || true
"$ADB_BIN" -s "$SERIAL" shell am start \
  -n "$PACKAGE_NAME/.MainActivity" \
  --es net.yoshida.morebettergakujo.DEBUG_URL "$DEBUG_URL" \
  --es net.yoshida.morebettergakujo.DEBUG_2FA_SECRET "$TEST_SECRET"

sleep 3
"$ADB_BIN" -s "$SERIAL" exec-out screencap -p > "$ARTIFACT_DIR/${TIMESTAMP}-launch.png"
"$ADB_BIN" -s "$SERIAL" exec-out uiautomator dump /dev/tty > "$ARTIFACT_DIR/${TIMESTAMP}-ui.xml" || true
sleep 5
"$ADB_BIN" -s "$SERIAL" exec-out screencap -p > "$ARTIFACT_DIR/${TIMESTAMP}-postwait.png"
"$ADB_BIN" -s "$SERIAL" exec-out uiautomator dump /dev/tty > "$ARTIFACT_DIR/${TIMESTAMP}-postwait-ui.xml" || true
"$ADB_BIN" -s "$SERIAL" logcat -d > "$ARTIFACT_DIR/${TIMESTAMP}-logcat.txt" || true

echo "QA artifacts written to $ARTIFACT_DIR"

if grep -Eq "MBG_2FA_AUTOFILL_SUCCESS:[0-9]{6}" "$ARTIFACT_DIR/${TIMESTAMP}-logcat.txt"; then
  echo "Local 2FA QA failed: generated TOTP token was written to logcat."
  exit 1
fi

if ! grep -q "2FA QA Page" "$ARTIFACT_DIR/${TIMESTAMP}-postwait-ui.xml"; then
  echo "Local 2FA QA failed: fixture page was not visible in the UI tree."
  exit 1
fi

if grep -q "MBG_2FA_SUBMIT_SUCCESS" "$ARTIFACT_DIR/${TIMESTAMP}-postwait-ui.xml"; then
  echo "Local 2FA QA passed: fixture submitted after 2FA autofill."
  exit 0
fi

if grep -q "MBG_2FA_AUTO_SUBMIT_SUCCESS" "$ARTIFACT_DIR/${TIMESTAMP}-logcat.txt"; then
  echo "Local 2FA QA passed: token-free MBG_2FA_AUTO_SUBMIT_SUCCESS marker was found."
  exit 0
fi

echo "Local 2FA QA failed: fixture was not submitted after 2FA autofill."
echo "Inspect $ARTIFACT_DIR/${TIMESTAMP}-postwait.png and $ARTIFACT_DIR/${TIMESTAMP}-postwait-ui.xml."
exit 1
