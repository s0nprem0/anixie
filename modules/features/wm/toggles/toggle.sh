#!/bin/bash
# The modes you flip on for an hour and off again.
#
#   toggle                pick one, showing what is on
#   toggle nightlight     warm the screen, or put it back
#   toggle idle           stop the screen locking, or start it again
#   toggle dnd            silence notifications, or let them through
#   toggle stayawake      hold off blanking, sleeping and suspending
#   toggle status         one line per toggle, for the bar
#
# Each of these is the same switch the bar's indicator flips and the same state
# the panel shows, so there is one answer to "is it on" rather than three. The
# bar asks `toggle status`; the keys call `toggle <name>`.
#
# `idle` is the odd name: it means the idle *lock*, so turning it "off" is what
# leaves the machine awake. That is the reference's naming, and it reads right
# the moment you see the coffee-cup indicator appear.

set -uo pipefail

hyprctl="@HYPRCTL@"
quickshell="@QUICKSHELL@"


# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# ---- night light ----
#
# hyprsunset reports its current temperature, and identity — the value the
# daytime profile uses — leaves that reading untouched rather than clearing it,
# so "warmer than neutral" is what says a tint is actually applied.

nightlight_state() {
  local t
  t=$("$hyprctl" hyprsunset temperature 2>/dev/null) || t=""
  if [ -n "$t" ] && [ "$t" -lt 6000 ] 2>/dev/null; then
    printf 'on'
  else
    printf 'off'
  fi
}

nightlight_toggle() {
  if [ "$(nightlight_state)" = "on" ]; then
    "$hyprctl" hyprsunset temperature 6500 >/dev/null 2>&1
  else
    "$hyprctl" hyprsunset temperature 4000 >/dev/null 2>&1
  fi
  # Push the temperature that is now in force, so the bar shows it without asking.
  t=$("$hyprctl" hyprsunset temperature 2>/dev/null) || t=""
  "$quickshell" ipc call indicator nightlight "${t:-0}" >/dev/null 2>&1 || true
}

# ---- idle lock ----
#
# The shell owns the idle cycle now: its screensaver, blanking and lock timers
# are one switch, exposed as the `idle` IPC target. The logind listener handles
# the pre-suspend lock as well, so there is no second daemon to ask about.

idle_state() {
  local state
  state=$("$quickshell" ipc call idle status 2>/dev/null) || state="off"
  case "$state" in
    on) printf 'on' ;;
    *) printf 'off' ;;
  esac
}

idle_toggle() {
  "$quickshell" ipc call idle toggle >/dev/null 2>&1 || die "the shell is not running"
}

# ---- do not disturb ----
#
# Owned by the shell, which is also what draws the toasts, so the switch is an
# IPC call into it rather than a flag file somewhere it would have to watch.

dnd_state() {
  local state
  state=$("$quickshell" ipc call notify status 2>/dev/null) || state="off"
  case "$state" in
    on) printf 'on' ;;
    *) printf 'off' ;;
  esac
}

dnd_toggle() {
  "$quickshell" ipc call notify toggle >/dev/null 2>&1 || die "the shell is not running"
}

# ---- stay awake ----
#
# A logind inhibitor rather than another toggle of the same daemon. `idle` only
# stops the shell's screensaver and lock timers; the sleep class and logind's
# lid action are separate, and an empty battery is the desktop's own policy.
# This one blocks idle, sleep and handle-lid-switch while it runs.
#
# The inhibitor is a service rather than a backgrounded `sleep infinity`: an
# inhibitor only exists while its process holds the lock, and one launched from
# a shell dies with it — the machine would go back to sleeping while the
# indicator still claimed otherwise.

stayawake_state() {
  if systemctl --user is-active --quiet anixie-stayawake; then
    printf 'on'
  else
    printf 'off'
  fi
}

stayawake_toggle() {
  if systemctl --user is-active --quiet anixie-stayawake; then
    systemctl --user stop anixie-stayawake
  else
    systemctl --user start anixie-stayawake
  fi
  "$quickshell" ipc call indicator stayawake "$(stayawake_state)" >/dev/null 2>&1 || true
}

# ---- the group ----

state_of() {
  case "$1" in
    nightlight) nightlight_state ;;
    idle) idle_state ;;
    dnd) dnd_state ;;
    stayawake) stayawake_state ;;
    *) die "no toggle called \"$1\"" ;;
  esac
}

label() {
  case "$1" in
    nightlight) printf 'Night light' ;;
    idle) printf 'Idle lock' ;;
    dnd) printf 'Silence notifications' ;;
    stayawake) printf 'Stay awake' ;;
  esac
}

toggle_one() {
  case "$1" in
    nightlight) nightlight_toggle ;;
    idle) idle_toggle ;;
    dnd) dnd_toggle ;;
    stayawake) stayawake_toggle ;;
    *) die "no toggle called \"$1\"" ;;
  esac
}

names() {
  printf '%s\n' nightlight idle dnd stayawake
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  status)
    # A single toggle prints just its state, so a caller that wants one — the
    # menu's labels — does not have to run the whole list and pick a line out of
    # it.
    if [ $# -ge 2 ]; then
      state_of "$2"
      exit 0
    fi

    for name in $(names); do
      printf '%s %s\n' "$name" "$(state_of "$name")"
    done
    ;;
  list)
    for name in $(names); do
      printf '%s\t%s\n' "$(label "$name")" "$(state_of "$name")"
    done
    ;;
  nightlight | idle | dnd | stayawake)
    toggle_one "$1"
    printf '%s: %s\n' "$(label "$1")" "$(state_of "$1")"
    ;;
  "")
    # The list carries its own state, so the picker says what is on before you
    # choose rather than after — and the state is the row's own trailing field
    # rather than part of its text, so the shell draws it dimmed on the right.
    #
    # The value is the toggle's name, so choosing a row runs `toggle <name>`
    # directly. It used to hand the chosen *line* back to a case arm that matched
    # on its first word, which meant renaming a label here silently broke the
    # picker: "Night light" became an unknown argument the day it was renamed.
    for name in $(names); do
      printf '%s\t%s\t\t%s\n' "$(label "$name")" "$name" "$(state_of "$name")"
    done | pick --title 'toggle' --on-select 'toggle {}'
    exit 0
    ;;
  *)
    printf 'toggle: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
