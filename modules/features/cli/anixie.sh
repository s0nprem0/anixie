#!/bin/sh
# anixie — one entry point for the desktop's commands.
#
# The tools exist on their own and always will; this is a front door to them, so
# that `anixie theme set gruvbox-dark` and `anixie shot region copy` read the
# same way and there is one place to look for what the desktop can do. It is a
# dispatcher, not a reimplementation: each group hands off to the command of the
# same concern, which is what actually knows how to run.
#
#   anixie                 this help
#   anixie commands        just the list of groups (--aliases adds the rest)
#   anixie help GROUP      a group's own help
#   anixie <group> [args]  run a group
#   anixie <group> --help  the same as `anixie help GROUP`
#   anixie resolve GROUP   the command a group runs
#   anixie subcommands GROUP  the words completion offers for it
#
# Every group below is another command on PATH. Adding one is a line in the table
# and nothing else: the help, `help`, `commands`, `resolve` and the dispatcher all
# read the same table, so they cannot disagree. The table is also what the shell's
# completion reads, which is why it carries subcommands as data rather than
# leaving them only in each command's prose. The flake's `anixie-table` check
# compares those subcommands with each command's dispatch case, so the table
# cannot quietly drift from what the command accepts.
set -eu

# One group per line, five fields:
#
#   name|command|aliases|subcommands|description
#
# `name` is the name the help lists; `command` is the words to exec (it may be
# more than one, and need not match the group's name), `aliases` are other names
# (space-separated, may be empty), `subcommands` are the group's own words
# (space-separated, may be empty) offered by completion and checked against the
# command's dispatch case, and `description` is the help line — last, so it may
# contain `|`.
ANIXIE_GROUPS='
theme|theme||list current set wallpaper wallpaper-mode state migrate auto favorite pin unpin export doctor cursor-size next prev apply|palettes: list, set, wallpaper FILE, state, migrate, auto, favorite, pin, export, doctor, cursor-size
appearance|appearance||toggle open close state|appearance panel
textsize|textsize|text|up down show set reset apply|global text size: up, down, set N, reset
wallpaper|wallpaper||list library set add next prev rotate rotation generated pause resume status apply current|desktop background: set FILE, library, next, rotate, current
display|monitors|monitors|scale internal lid mirror brightness recover wake workspace workspace-step move-window workspaces list set try keep revert identify status|monitors: scale, internal, mirror, status
power|powerprofile|powerprofile|set apply show status automation set-automation charge|power profiles per source and charge ceiling: set ac|battery PROFILE, charge full|limit N
wifi|wifi||band dns password qr|Wi-Fi: band, DNS, password, QR
audio|audio-output|audio-output|set switch|audio output: set, switch
shot|shot|screenshot|smart region windows fullscreen window scroll copy save annotate preview redact text|screenshots: smart, region, windows, fullscreen
record|record||--status --stop --fullscreen --audio --webcam-device --webcam-size|screen recording
clipboard|clipboard||--copy|clipboard history popup
emoji|emoji|||emoji picker
menu|menu||apps --list --only|application and action menu
webapp|webapp||add list remove|websites as applications: add, list, remove
pick|pick||--title --placeholder --input --allow-empty --grouped --on-select --on-cancel|the generic picker
reminder|reminder||show count clear -i|set and list reminders
toggle|toggle||nightlight idle dnd stayawake status list|night light, idle, do-not-disturb
snapshot|snapshot||create list restore prune|btrfs snapshots of /home: create, list, restore, prune
update|rebuild|rebuild|switch boot test|rebuild and switch the system
bar|bar||toggle on off reset reload move enable disable background position get set modules tray|the status bar: toggle, position, layout, settings
focus|focus||start stop extend status|focus mode: start, stop, extend, status
screentime|screentime||show json reset path panel|screen time for today: show, json, reset
'

# The loops below read the table through a here-document rather than a pipe, so
# they run in this shell. A pipeline would put them in a subshell, where `return`
# and the dispatcher's `exec` would apply to the wrong process.

usage() {
  printf 'anixie — desktop command center\n\n'
  printf 'Usage:\n'
  printf '  anixie <group> [args...]\n'
  printf '  anixie help <group>\n'
  printf '  anixie commands [--aliases]\n'
  printf '  anixie resolve <group>\n'
  printf '  anixie subcommands <group>\n\n'
  printf 'Groups:\n'
  while IFS='|' read -r name cmd aliases subs desc; do
    [ -n "$name" ] || continue
    if [ -n "$aliases" ]; then
      printf '  %-11s %s (also: %s)\n' "$name" "$desc" \
        "$(printf '%s' "$aliases" | sed 's/ /, /g')"
    else
      printf '  %-11s %s\n' "$name" "$desc"
    fi
  done <<EOF
$ANIXIE_GROUPS
EOF
}

# Canonical group names, plus the aliases when asked. Completion uses the
# aliases too, so `anixie screenshot` tab-completes like `anixie shot`.
group_names() {
  while IFS='|' read -r name cmd aliases subs desc; do
    [ -n "$name" ] || continue
    printf '%s\n' "$name"
    if [ "${1:-}" = "--aliases" ]; then
      for alias in $aliases; do printf '%s\n' "$alias"; done
    fi
  done <<EOF
$ANIXIE_GROUPS
EOF
}

# The command words a group runs, by its name or any alias. Fails if unknown.
resolve() {
  while IFS='|' read -r name cmd aliases subs desc; do
    case " $name $aliases " in
      *" $1 "*) printf '%s\n' "$cmd"; return 0 ;;
    esac
  done <<EOF
$ANIXIE_GROUPS
EOF
  return 1
}

# A group's own words, one per line, for completion. Fails if unknown.
subcommands() {
  while IFS='|' read -r name cmd aliases subs desc; do
    case " $name $aliases " in
      *" $1 "*)
        for word in $subs; do printf '%s\n' "$word"; done
        return 0
        ;;
    esac
  done <<EOF
$ANIXIE_GROUPS
EOF
  return 1
}

case "${1:-}" in
  "" | -h | --help)
    usage
    exit 0
    ;;
  help)
    if [ $# -ge 2 ]; then
      set -- "$2" --help
    else
      usage
      exit 0
    fi
    ;;
  commands)
    group_names "${2:-}"
    exit 0
    ;;
  resolve)
    [ $# -ge 2 ] || {
      printf 'anixie: resolve needs a group (try: anixie commands)\n' >&2
      exit 2
    }
    resolve "$2" || {
      printf 'anixie: no group called "%s" (try: anixie commands)\n' "$2" >&2
      exit 2
    }
    exit 0
    ;;
  subcommands)
    [ $# -ge 2 ] || {
      printf 'anixie: subcommands needs a group (try: anixie commands)\n' >&2
      exit 2
    }
    subcommands "$2" || {
      printf 'anixie: no group called "%s" (try: anixie commands)\n' "$2" >&2
      exit 2
    }
    exit 0
    ;;
esac

# Everything else is a group. Look it up, drop the group name, and become the
# command — quoting $cmd is wrong here: it is the words to exec, and splitting
# it is the point.
cmd=$(resolve "$1") || {
  printf 'anixie: no group called "%s" (try: anixie commands)\n' "$1" >&2
  exit 2
}
shift
# shellcheck disable=SC2086
exec $cmd "$@"
