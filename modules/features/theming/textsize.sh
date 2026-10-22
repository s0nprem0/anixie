#!/bin/sh
# Global text size.
#
# One knob for how large everything reads, moving the shell, GTK applications and
# the terminal together so the desktop stays in proportion. It is a percentage of
# the built-in sizes; 100 is what the configs were written for.
#
#   textsize            show the current percentage
#   textsize up|down    a step larger or smaller
#   textsize set N      an exact percentage (80-200)
#   textsize reset      100
#   textsize apply      re-apply the saved value (run at login)
#
# The value is materialised into files the apps already read at runtime, the same
# way the theme is: a kitty include and a shell state file. GTK has no such file,
# so it is told through its own text-scaling-factor setting, which takes effect
# in running applications.
set -eu

STATE="@STATE_DIR@"
FILE="$STATE/textscale"
KITTY="$STATE/kitty-font.conf"
BASE_FONT=11
GSETTINGS="@GSETTINGS@"
GSETTINGS_SCHEMA_DIR="@GSETTINGS_SCHEMA_DIR@"
QUICKSHELL="@QUICKSHELL@"

STEPS="80 90 100 110 125 150 175 200"
MIN=80
MAX=200

current() {
  if [ -f "$FILE" ]; then
    tr -dc '0-9' <"$FILE"
  else
    echo 100
  fi
}

# Nearest step to a given percentage, so `up`/`down` land on the same ladder.
snap() {
  best=100
  for s in $STEPS; do
    if [ "$s" -le "$1" ]; then best=$s; fi
  done
  echo "$best"
}

apply_one() {
  percent="$1"
  [ "$percent" -ge "$MIN" ] && [ "$percent" -le "$MAX" ] ||
    { printf 'textsize: %s out of range (%s-%s)\n' "$percent" "$MIN" "$MAX" >&2; exit 1; }

  mkdir -p "$STATE"
  printf '%s\n' "$percent" >"$FILE"

  # kitty takes an integer point size; round rather than truncate so 11 at 125%
  # is 14, not 13.
  printf 'font_size %s\n' "$(((BASE_FONT * percent + 50) / 100))" >"$KITTY"

  scale="$(awk "BEGIN { printf \"%.2f\", $percent / 100 }")"
  GSETTINGS_SCHEMA_DIR="$GSETTINGS_SCHEMA_DIR" \
    "$GSETTINGS" set org.gnome.desktop.interface text-scaling-factor "$scale" 2>/dev/null || true
  "$QUICKSHELL" ipc call text set "$scale" >/dev/null 2>&1 || true

  # Tell running terminals to re-read the include.
  pkill -USR1 -x kitty 2>/dev/null || true
}

case "${1:-}" in
  "" | show) current ;;
  apply) apply_one "$(current)" ;;
  reset) apply_one 100 ;;
  set)
    [ $# -ge 2 ] || { echo "textsize: set needs a percentage" >&2; exit 1; }
    apply_one "$2"
    ;;
  up)
    now="$(snap "$(current)")"
    next=$((now + 10))
    [ "$next" -le "$MAX" ] || next=$now
    apply_one "$next"
    ;;
  down)
    now="$(snap "$(current)")"
    prev=$((now - 10))
    [ "$prev" -ge "$MIN" ] || prev=$now
    apply_one "$prev"
    ;;
  *) printf 'textsize: unknown argument "%s"\n' "$1" >&2; exit 2 ;;
esac
