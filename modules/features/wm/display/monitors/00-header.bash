#!/bin/bash
# Monitor control for what the brightness and function keys do not cover.
#
#   monitors scale [up|down|set N|reset]   step the focused monitor's scale
#   monitors internal [on|off|toggle]      the laptop panel's power
#   monitors lid [close|open|toggle|reconcile]
#                                          clamshell handling for the lid
#   monitors mirror [on|off|toggle]        mirror the laptop onto an external
#   monitors brightness [up|down|set N|max|min] [STEP]
#                                          the focused display's backlight
#   monitors list                          every output as JSON, for the panel
#   monitors set OUTPUT scale VALUE        one output's scale
#   monitors set OUTPUT transform VALUE    rotation and flipping
#   monitors set OUTPUT disabled yes|no    turn one output off or on
#   monitors set OUTPUT position VALUE     auto, auto-left/right/up/down, XxY
#   monitors set OUTPUT mode VALUE         preferred, highres, highrr, WxH[@R]
#   monitors set OUTPUT mirror VALUE       none, or the output to mirror
#   monitors try OUTPUT SETTING VALUE      apply with an automatic revert
#   monitors keep                          keep the pending try
#   monitors revert                        undo the pending try now
#   monitors identify                      flash each output's name on it
#   monitors recover                       clear a stale internal-off state
#   monitors wake                          cycle DPMS on every output
#   monitors workspace N                   focus the Nth workspace of this monitor
#   monitors workspace-step next|prev      move one workspace within its block
#   monitors move-window N                 move the window to that workspace
#   monitors workspaces sync|show|reset    per-monitor workspace blocks
#   monitors status                        one line per monitor
#
# Scaling steps through 1x, 1.25x, 1.5x, 1.6x, 2x, 3x and 4x — the ratios worth having
# between "this is a 1080p panel" and "this is a 6K one". Only the focused monitor
# is stepped, which is what makes the keys usable with a second screen attached.
#
# `set` is the same machinery aimed at a named output rather than the focused one,
# which is what the Displays panel needs: it lists every screen and changes this
# one, and a panel that could only reach whichever was focused would be useless
# with two.
#
# `try` is the same change with a guard: the previous value is kept in a pending
# file and a transient systemd timer puts it back unless `keep` is run first. A
# mode or a scale that the panel cannot display then costs fifteen seconds rather
# than a trip to a TTY. `revert` does the same thing immediately, which is what
# the panel's Revert button and the timer both call.
#
# The chosen values are written to a state file that
# features/wm/hyprland/config/20-settings.lua reads when it loads, so they survive
# a config reload and a reboot instead of
# snapping back. That state includes the mirror target, position and mode as
# well as scale, rotation and on/off, because a reload would otherwise
# re-apply the output's ordinary rule and quietly end a mirror or reset the
# arrangement. There is nowhere else to keep them:
# `hyprctl keyword` is refused by the Lua config manager — "keyword can't work
# with non-legacy parsers" — and Hyprland has no runtime monitor dispatcher.
# `hl.monitor` through `hyprctl eval` is the only way in, and it remembers
# nothing by itself.

# Every jq program below is single-quoted on purpose: they are jq, not shell, and
# $n / $k are jq's own variables rather than the shell expanding anything.
# shellcheck disable=SC2016

set -uo pipefail

hyprctl="@HYPRCTL@"
jq="@JQ@"
brightnessctl="@BRIGHTNESSCTL@"
ddcutil="@DDCUTIL@"
quickshell="@QUICKSHELL@"
systemd_run="@SYSTEMD_RUN@"
systemctl="@SYSTEMCTL@"

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/anixie"
state_file="$state_dir/display.conf"
pending_file="$state_dir/display-pending"
lid_file="$state_dir/lid"
workspace_file="$state_dir/workspaces.json"

# The transient unit a `try` leaves behind. The timer is the authority on
# reverting: it keeps working if the panel is closed or the shell restarts.
revert_unit="anixie-display-revert"
revert_seconds=15

# The ladder, as words so membership can be tested with `case` rather than a float
# comparison bash cannot do.
ladder="1 1.25 1.5 1.6 2 3 4"

# Rotation, as Hyprland numbers them. hl.monitor takes the index into this list,
# not the degrees, and rejects a transform above its own maximum — so these are
# the names to show and the indices to send.
transform_names="normal 90 180 270 flipped flipped-90 flipped-180 flipped-270"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

# Active outputs only. A disabled output cannot be focused, and it is not a
# place to mirror onto.
