#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 1 || (${1:-} != "" && ${1:-} != "--uninstall") ]]; then
  echo "Usage: $0 [--uninstall]" >&2
  exit 64
fi

app_id="net.yoshida.morebettergakujo"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
applications_dir="$data_home/applications"
icons_dir="$data_home/icons/hicolor"
desktop_file="$applications_dir/$app_id.desktop"
services_dir="$data_home/dbus-1/services"
service_file="$services_dir/$app_id.service"

if [[ ${1:-} == "--uninstall" ]]; then
  rm -f -- "$desktop_file" "$service_file"
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
  mkdir -p -- "$applications_dir" "$services_dir"
  # Exec values need both desktop-entry string escaping and argument quoting.
  exec_path="$(printf '%s' "$executable" | sed \
    -e 's/\\/\\\\\\\\/g' -e 's/"/\\\\"/g' \
    -e 's/`/\\\\`/g' -e 's/\$/\\\\$/g' -e 's/%/%%/g')"
  while IFS= read -r line; do
    case "$line" in
      Exec=*) printf 'Exec="%s"\n' "$exec_path" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$bundle_dir/share/$app_id.desktop.in" > "$desktop_file"
  # D-Bus also unescapes the value before parsing arguments, without field codes.
  service_exec_path="$(printf '%s' "$executable" | sed \
    -e 's/\\/\\\\\\\\/g' -e 's/"/\\\\"/g' \
    -e 's/`/\\\\`/g' -e 's/\$/\\\\$/g')"
  printf '[D-BUS Service]\nName=%s\nExec="%s"\n' \
    "$app_id" "$service_exec_path" > "$service_file"
  chmod 0644 "$desktop_file" "$service_file"
  for size in 16 32 64 128 256 512; do
    icon_dir="$icons_dir/${size}x${size}/apps"
    mkdir -p -- "$icon_dir"
    install -m 0644 "$bundle_dir/icons/hicolor/${size}x${size}/apps/$app_id.png" \
      "$icon_dir/$app_id.png"
  done
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$applications_dir" || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$icons_dir" || true
fi
