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
#   anixie commands        just the list of groups
#   anixie resolve GROUP   the command a group runs
#   anixie <group> [args]  run a group
#   anixie <group> --help  that command's own help
#
# Every group below is another command on PATH. Adding one is a line in the table
# and nothing else: the help, `commands`, `resolve` and the dispatcher all read
# the same table, so they cannot disagree. The table is also what the shell's
# completion reads, which is why it carries subcommands as data rather than
# leaving them only in each command's prose.
set -eu

# One group per line, five fields:
#
#   name|command|aliases|subcommands|description
#
# `name` is the name the help lists; `command` is the words to exec (it may be
# more than one), `aliases` are other names (space-separated, may be empty),
# `subcommands` are the group's own words (space-separated, may be empty) offered
# by completion, and `description` is the help line — last, so it may contain `|`.
#
# The commands that do real work before handing off (`update`, `bar`) carry their
# whole command line here rather than a case arm of their own.
ANIXIE_GROUPS='
theme|theme||list current set wallpaper next prev apply|palettes: list, set, wallpaper FILE, next, prev, apply
textsize|textsize|text|up down set reset apply|global text size: up, down, set N, reset
wallpaper|wallpaper||list set add next prev generated apply current|desktop background: set FILE, theme, current
display|monitors|monitors|scale internal mirror set list status|monitors: scale, internal, mirror, status
power|powerprofile|powerprofile|set apply show|power profiles per source: set ac|battery PROFILE, show
shot|shot|screenshot|smart region windows fullscreen window copy save annotate preview|screenshots: smart, region, windows, fullscreen
record|record||--status --stop --fullscreen|screen recording
clipboard|clipboard|||clipboard history picker
emoji|emoji|||emoji picker
menu|menu||apps --list --only|application and action menu
webapp|webapp||add list remove|websites as applications: add, list, remove
pick|pick||--title --input --on-select|the generic picker
reminder|reminder||show count clear -i|set and list reminders
toggle|toggle||nightlight idle dnd stayawake status list|night light, idle, do-not-disturb
snapshot|snapshot||create list restore prune|btrfs snapshots of /home: create, list, restore, prune
update|rebuild||switch boot test|rebuild and switch the system
bar|quickshell ipc call bar||toggle on off reset move enable disable background tray|the status bar: toggle, on, off
focus|focus||start stop extend status|focus mode: start, stop, extend, status
screentime|screentime||show json reset path|screen time for today: show, json, reset
'

# The loops below read the table through a here-document rather than a pipe, so
# they run in this shell. A pipeline would put them in a subshell, where `return`
# and the dispatcher's `exec` would apply to the wrong process.

usage() {
  printf 'anixie — desktop command center\n\n'
  printf 'Usage:\n'
  printf '  anixie <group> [args...]\n'
  printf '  anixie commands\n'
  printf '  anixie resolve <group>\n\n'
  printf 'Groups:\n'
  while IFS='|' read -r name cmd aliases subs desc; do
    [ -n "$name" ] || continue
    printf '  %-11s %s\n' "$name" "$desc"
  done <<EOF
$ANIXIE_GROUPS
EOF
}

group_names() {
  while IFS='|' read -r name cmd aliases subs desc; do
    [ -n "$name" ] || continue
    printf '%s\n' "$name"
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
  "" | -h | --help | help)
    usage
    exit 0
    ;;
  commands)
    group_names
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
