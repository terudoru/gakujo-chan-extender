#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || (${1:-} != "" && ${1:-} != "--uninstall") ]]; then
  echo "Usage: $0 [--uninstall]" >&2
  exit 64
fi

app_id="net.yoshida.morebettergakujo"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
if [[ "$data_home" != "/" ]]; then
  data_home="${data_home%/}"
fi
applications_dir="$data_home/applications"
icons_dir="$data_home/icons/hicolor"
desktop_file="$applications_dir/$app_id.desktop"
services_dir="$data_home/dbus-1/services"
service_file="$services_dir/$app_id.service"
launcher_dir="$data_home/$app_id"
launcher_link="$launcher_dir/morebettergakujo"

if [[ ${1:-} == "--uninstall" ]]; then
  rm -f -- "$desktop_file" "$service_file" "$launcher_link"
  rmdir -- "$launcher_dir" 2>/dev/null || true
  for size in 16 32 64 128 256 512; do
    rm -f -- "$icons_dir/${size}x${size}/apps/$app_id.png"
  done
else
  bundle_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
  executable="$bundle_dir/morebettergakujo_flutter"
  if [[ ! -x "$executable" ]]; then
    echo "App executable not found: $executable" >&2
    exit 66
  fi
  if [[ "$launcher_link" == *$'\n'* || "$launcher_link" == *$'\r'* ]]; then
    echo "XDG_DATA_HOME must not contain newline characters: $data_home" >&2
    exit 65
  fi
  mkdir -p -- "$applications_dir" "$services_dir" "$launcher_dir"
  ln -sfn -- "$executable" "$launcher_link"
  # Exec values need both desktop-entry string escaping and argument quoting.
  desktop_exec_path="$(printf '%s' "$launcher_link" | sed \
    -e 's/\\/\\\\\\\\/g' -e 's/"/\\\\"/g' \
    -e 's/`/\\\\`/g' -e 's/\$/\\\\$/g' -e 's/%/%%/g')"
  if [[ "$launcher_link" == *%* ]]; then
    # GLib validates argv[0] before expanding %%, so wrap % paths via sh.
    desktop_exec_line="Exec=/bin/sh -c 'exec \"\$1\"' sh \"$desktop_exec_path\""
  else
    desktop_exec_line="Exec=\"$desktop_exec_path\""
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      Exec=*) printf '%s\n' "$desktop_exec_line" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$bundle_dir/share/$app_id.desktop.in" > "$desktop_file"
  # Single-quoting avoids backslash differences between dbus-broker and dbus-daemon
  # when the path contains $, `, or "; fall back to c_shquote double-quoting otherwise.
  if [[ "$launcher_link" != *\'* && "$launcher_link" != *\\* && ( "$launcher_link" == *\"* || "$launcher_link" == *\$* || "$launcher_link" == *\`* ) ]]; then
    service_exec_line="Exec='$launcher_link'"
  else
    service_exec_path="$(printf '%s' "$launcher_link" | sed \
      -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
      -e 's/`/\\`/g' -e 's/\$/\\$/g')"
    service_exec_line="Exec=\"$service_exec_path\""
  fi
  printf '[D-BUS Service]\nName=%s\n%s\n' \
    "$app_id" "$service_exec_line" > "$service_file"
  chmod 0644 -- "$desktop_file" "$service_file"
  for size in 16 32 64 128 256 512; do
    icon_dir="$icons_dir/${size}x${size}/apps"
    mkdir -p -- "$icon_dir"
    install -m 0644 -- "$bundle_dir/icons/hicolor/${size}x${size}/apps/$app_id.png" \
      "$icon_dir/$app_id.png"
  done
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$applications_dir" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$icons_dir" || true
fi
if command -v gdbus >/dev/null 2>&1; then
  gdbus call --session --dest org.freedesktop.DBus \
    --object-path /org/freedesktop/DBus \
    --method org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
elif command -v dbus-send >/dev/null 2>&1; then
  dbus-send --session --dest=org.freedesktop.DBus --type=method_call \
    /org/freedesktop/DBus org.freedesktop.DBus.ReloadConfig >/dev/null 2>&1 || true
fi
