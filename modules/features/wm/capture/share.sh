#!/bin/sh
set -eu

runtime_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie"
last_capture_file="$runtime_dir/last-capture"

if [ ! -f "$last_capture_file" ]; then
  @NOTIFY_SEND_RAW@ -a capture -u normal -t 3000 "Share" "No recent capture to share." >/dev/null 2>&1 || true
  exit 1
fi

last=$(cat "$last_capture_file" 2>/dev/null || true)
[ -n "$last" ] && [ -f "$last" ] || {
  @NOTIFY_SEND_RAW@ -a capture -u normal -t 3000 "Share" "Recent capture not found." >/dev/null 2>&1 || true
  exit 1
}

# Try to use the shell's picker if available; otherwise fallback to common actions
if command -v pick >/dev/null 2>&1; then
  printf '%s\n' "Copy file URI" "Copy path" "Edit in satty" "Show in folder" "Compress with transcode" | \
    pick --title 'Share capture' --on-select "
      case {} in
        'Copy file URI')
          printf 'file://%s\n' \"\$(realpath -- '$last')\" | @WL_COPY@ --type text/uri-list >/dev/null 2>&1 && @NOTIFY_SEND_RAW@ -a capture -u low -t 2000 'Shared' 'Copied file URI' >/dev/null 2>&1 || true
          ;;
        'Copy path')
          printf '%s' '$last' | @WL_COPY@ --type text/plain >/dev/null 2>&1 && @NOTIFY_SEND_RAW@ -a capture -u low -t 2000 'Shared' 'Copied path' >/dev/null 2>&1 || true
          ;;
        'Edit in satty')
          @SATTY@ --filename '$last' --output-filename '$last' --initial-tool crop >/dev/null 2>&1 &
          ;;
        'Show in folder')
          if command -v dbus-send >/dev/null 2>&1; then
            dbus-send --session --print-reply --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 org.freedesktop.FileManager1.ShowItems array:string:\"file://\$(realpath -- '$last')\" string:\"\" >/dev/null 2>&1 && exit 0 || true
          fi
          xdg-open \"\$(dirname '$last')\" >/dev/null 2>&1 &
          ;;
        'Compress with transcode')
          transcode '$last' >/dev/null 2>&1 &
          ;;
      esac
    "
  exit 0
fi

# Fallback without picker
printf '%s' "$last" | @WL_COPY@ --type text/plain >/dev/null 2>&1
@NOTIFY_SEND_RAW@ -a capture -u low -t 2000 "Share" "Copied path to clipboard" >/dev/null 2>&1 || true
