#!/usr/bin/env bash

set -euo pipefail

app_path="${1:-}"
if [[ -z "$app_path" || ! -d "$app_path" ]]; then
  echo "macOS .app bundle not found: ${app_path:-<empty>}" >&2
  exit 1
fi

info_plist="$app_path/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  echo "macOS Info.plist not found: $info_plist" >&2
  exit 1
fi

executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")"
executable_path="$app_path/Contents/MacOS/$executable_name"
if [[ ! -x "$executable_path" ]]; then
  echo "macOS executable is missing or not executable: $executable_path" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

entitlements_path="$(mktemp -t more-better-gakujo-entitlements)"
launch_log="$(mktemp -t more-better-gakujo-launch)"
app_pid=""
cleanup() {
  if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid" 2>/dev/null || true
    wait "$app_pid" 2>/dev/null || true
  fi
  rm -f "$entitlements_path" "$launch_log"
}
trap cleanup EXIT

codesign -d --entitlements :- "$app_path" >"$entitlements_path"
if /usr/libexec/PlistBuddy \
  -c 'Print :keychain-access-groups' \
  "$entitlements_path" >/dev/null 2>&1; then
  echo 'Ad-hoc macOS releases must not claim keychain-access-groups.' >&2
  exit 1
fi

architectures="$(lipo -archs "$executable_path")"
for architecture in x86_64 arm64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    echo "macOS executable is missing $architecture: $architectures" >&2
    exit 1
  fi
done

"$executable_path" >"$launch_log" 2>&1 &
app_pid="$!"
for _ in 1 2 3 4 5; do
  sleep 1
  if ! kill -0 "$app_pid" 2>/dev/null; then
    exit_status=0
    wait "$app_pid" || exit_status="$?"
    app_pid=""
    echo "macOS app exited during launch smoke test (status $exit_status)." >&2
    cat "$launch_log" >&2
    exit 1
  fi
done

echo "macOS release verification passed: $architectures"
