#!/bin/bash
# Decode the QR code inside a region of the screen, and put its value on the
# clipboard.
#
#   capture-qr
#
# Only QR codes are looked for. zbar reads a dozen symbologies by default, and on
# dense screen content the others false-positive readily — a paragraph of text can
# read as an EAN or a Code 39 and take the clipboard instead — so everything but
# qrcode is switched off.
#
# The decoded value goes to the clipboard and nowhere else. It is not printed, it
# is not in the notification, and the copy is marked sensitive so a clipboard
# manager is asked to skip it. QR codes routinely carry secrets: the otpauth:// URI
# behind a 2FA setup code is the usual one, and neither the session journal nor a
# clipboard history is somewhere that belongs.
#
# The freeze is held across the read, like the screenshot and text captures, so the
# code that was aimed at is the code that is read.

set -uo pipefail

shot_pick="@SHOT_PICK@"
grim="@GRIM@"
wl_copy="@WL_COPY@"
zbar="@ZBAR@"
notify_send="@NOTIFY_SEND@"

runtime_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie"
freeze_pid_file="$runtime_dir/anixie-pick-freeze.pid"

release_freeze() {
  [ -f "$freeze_pid_file" ] || return 0
  kill "$(cat "$freeze_pid_file" 2>/dev/null)" 2>/dev/null
  rm -f "$freeze_pid_file"
}
trap release_freeze EXIT HUP INT TERM

geometry=$("$shot_pick" region --keep-freeze) || exit 1
[ -n "$geometry" ] || exit 1

# `-q` and the discarded stderr are for zbar's "scanned 1 barcode" chatter, which
# would otherwise be read as part of the value.
result=$(
  "$grim" -g "$geometry" - |
    "$zbar" -q --raw -Sdisable -Sqrcode.enable - 2>/dev/null
)

release_freeze

if [ -z "$result" ]; then
  "$notify_send" -u normal -a capture -G f071 "No QR code found" "Nothing in that region decoded as a QR code." >/dev/null 2>&1
  exit 1
fi

# Sensitive, so the value is not retained by a clipboard history. The notification
# names the fact of the copy and not the value, for the same reason.
printf '%s' "$result" | "$wl_copy" --sensitive

"$notify_send" -a capture -G f0c5 "QR code copied" "The decoded value is on the clipboard." >/dev/null 2>&1
