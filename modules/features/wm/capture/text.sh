#!/bin/bash
# Extract the text inside a region of the screen, and put it on the clipboard.
#
#   capture-text
#
# Drag a region around the text and it is OCR'd. A region rather than a window:
# the text worth lifting is usually a few lines inside something, not the whole
# window, and a drag says exactly which lines.
#
# The picker is the screenshot picker, and the freeze is held across the read so
# tesseract sees the frame that was aimed at rather than whatever moved while the
# region was being drawn.
#
# CAPTURE_TEXT_LANGS overrides the language, CAPTURE_TEXT_DPI the resolution
# tesseract is told the image is at. The DPI is not measured — nothing here knows
# the true dots per inch of a screenshot — but tesseract's page segmentation reads
# it, and its own default of 70 is far too low for screen text, so a plausible
# desktop figure is passed instead. It is the first thing to change if the result
# comes back as one line, or as nothing.

set -uo pipefail

shot_pick="@SHOT_PICK@"
grim="@GRIM@"
wl_copy="@WL_COPY@"
tesseract="@TESSERACT@"
notify_send="@NOTIFY_SEND@"

runtime_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}}/anixie"
freeze_pid_file="$runtime_dir/anixie-pick-freeze.pid"

# The picker exits as soon as a region is drawn and leaves the freeze for whoever
# asked for it, so taking it down is this script's job. On every exit path: a
# failed read must not leave a still frame over the desktop.
release_freeze() {
  [ -f "$freeze_pid_file" ] || return 0
  kill "$(cat "$freeze_pid_file" 2>/dev/null)" 2>/dev/null
  rm -f "$freeze_pid_file"
}
trap release_freeze EXIT HUP INT TERM

geometry=$("$shot_pick" region --keep-freeze) || exit 1
[ -n "$geometry" ] || exit 1

text=$(
  "$grim" -g "$geometry" - |
    "$tesseract" stdin stdout \
      --oem 1 --psm 6 --dpi "${CAPTURE_TEXT_DPI:-300}" \
      -l "${CAPTURE_TEXT_LANGS:-eng}" \
      -c preserve_interword_spaces=1 2>/dev/null
)

release_freeze

if [ -z "$text" ]; then
  "$notify_send" -u critical -a capture "No text found" "Nothing in that region was readable." >/dev/null 2>&1
  exit 1
fi

printf '%s' "$text" | "$wl_copy"

# The first line stands in for the whole thing, so the notification says what was
# picked up without repeating a page of it.
first_line=$(printf '%s' "$text" | head -n 1 | cut -c 1-60)
"$notify_send" -a capture "Text copied" "$first_line" >/dev/null 2>&1
