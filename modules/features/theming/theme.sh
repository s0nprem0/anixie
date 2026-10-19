#!/bin/bash
# Themes.
#
#   theme                pick one
#   theme list           the names, one per line
#   theme current        the name in use
#   theme set NAME       switch to it
#   theme next | prev    step through the list
#   theme apply          re-apply the current one (run at login)
#
# One palette drives the shell, the compositor's window borders, the terminal and
# the launcher. The shell switches the instant the state file changes — it watches
# it — and the rest are told: Hyprland reloads, kitty takes SIGUSR1.
#
# Everything else is themed when the system is built, from the module's `theme`
# option: the editor (helix), the file manager (yazi), the monitor (btop), tmux
# and the lock screen. Those are store symlinks in ~/.config, which is the point
# of them — a runtime writer would fight the link — so switching at runtime
# leaves them on the palette of the last build until you rebuild. The shell
# switching instantly and the editor waiting for a build is the honest split;
# the alternative is a config file nobody can reproduce.
#
# The palettes are a JSON file rather than a Nix expression because this script
# has to read the same list the shell was built from, and a shell script cannot
# evaluate Nix. One file, two readers, nothing to keep in step by hand.
#
# What it does not reach: GTK and Qt keep their own themes (Adwaita and the icon
# set are picked in Nix and are not per-palette), and anything else whose config
# is generated at build time. Those need a rebuild, and the module's `theme`
# option is what changes them.

set -uo pipefail

palettes="@PALETTES@"
state_dir="@STATE_DIR@"
default_theme="@DEFAULT_THEME@"

quickshell="@QUICKSHELL@"
hyprctl="@HYPRCTL@"
jq="@JQ@"
wallpaper="@WALLPAPER@"

current_file="$state_dir/current"

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

die() {
  printf 'theme: %s\n' "$1" >&2
  exit 1
}

names() {
  "$jq" -r 'keys[]' "$palettes" | sort
}

has() {
  "$jq" -e --arg n "$1" 'has($n)' "$palettes" >/dev/null 2>&1
}

# One colour out of a palette, and the same without its '#' for the formats that
# want it bare.
colour() {
  "$jq" -r --arg n "$1" --arg k "$2" '.[$n][$k]' "$palettes"
}

current() {
  local name=""
  [ -f "$current_file" ] && name=$(tr -d '[:space:]' <"$current_file")
  if [ -n "$name" ] && has "$name"; then
    printf '%s' "$name"
  else
    printf '%s' "$default_theme"
  fi
}

# Write the files the apps read. Everything that follows a theme is materialised
# here rather than rendered at build time, because a build-time value cannot
# change without a rebuild.
materialise() {
  local name="$1"
  mkdir -p "$state_dir" || die "could not create $state_dir"

  printf '%s\n' "$name" >"$current_file"

  # kitty reads this through an include in its generated config, so the same four
  # settings appear whether the theme was built in or set at runtime.
  cat >"$state_dir/kitty.conf" <<EOF
background $(colour "$name" background)
foreground $(colour "$name" foreground)
selection_background $(colour "$name" accent)
selection_foreground $(colour "$name" background)
EOF

  # tmux, btop, and whichever others have learned to read the state directory.
  # A failure here must not take the theme switch with it — the shell and the
  # terminal have already changed by this point.
  "@THEME_APPS@" "$name" >/dev/null 2>&1 || true
}

# The compositor and the terminal have to be told. The shell is told through its
# IPC rather than left to notice: it reads the state file once at startup, and a
# FileView watch on it never fired on this Quickshell, so a running shell has no
# other way to hear about the change.
tell_apps() {
  local name="$1"
  "$quickshell" ipc call theme set "$name" >/dev/null 2>&1 || true
  "$hyprctl" reload >/dev/null 2>&1 || true
  pkill -USR1 -x kitty 2>/dev/null || true

  # The wallpaper follows the palette unless one of your own is set, in which
  # case this is a no-op — the `wallpaper` command owns that decision.
  "$wallpaper" apply >/dev/null 2>&1 || true
}

set_theme() {
  local name="$1"
  has "$name" || die "no theme called \"$name\" (try: theme list)"
  materialise "$name"
  tell_apps "$name"
  printf 'Theme: %s\n' "$name"
}

step() {
  local direction="$1" here target
  here=$(current)

  # Sorted order, wrapping at both ends, so next from the last is the first.
  target=$(
    names | awk -v here="$here" -v dir="$direction" '
      { list[NR] = $0; if ($0 == here) at = NR }
      END {
        if (at == 0) at = 1
        if (dir == "next") at = (at % NR) + 1
        else at = ((at - 2 + NR) % NR) + 1
        print list[at]
      }'
  )

  [ -n "$target" ] || die "could not work out the next theme"
  set_theme "$target"
}

case "${1:-}" in
  -h | --help)
    usage
    ;;
  list)
    names
    ;;
  current)
    current
    ;;
  apply)
    # No change, just make sure the files match the saved choice — this is what
    # login runs, since a fresh boot has the state directory but not the files.
    materialise "$(current)"
    tell_apps "$(current)"
    ;;
  set)
    [ $# -ge 2 ] || die "set needs a theme name"
    set_theme "$2"
    ;;
  next)
    step next
    ;;
  prev | previous)
    step prev
    ;;
  "")
    # The picker runs `theme set <name>` itself, so this has nothing left to do
    # but hand over the names and be done.
    names | pick --title 'theme' --on-select 'theme set {}'
    exit 0
    ;;
  *)
    printf 'theme: unknown argument "%s" (try --help)\n' "$1" >&2
    exit 2
    ;;
esac
