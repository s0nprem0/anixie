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
#   anixie <group> [args]  run a group
#   anixie <group> --help  that command's own help
#
# Every group below is another command on PATH. Adding one is a case arm here and
# nothing else.
set -eu

usage() {
  cat <<'EOF'
anixie — desktop command center

Usage:
  anixie <group> [args...]
  anixie commands

Groups:
  theme        palettes: list, set, next, prev, apply
  textsize     global text size: up, down, set N, reset
  wallpaper    desktop background: set FILE, theme, current
  display      monitors: scale, internal, mirror, status
  power        power profiles per source: set ac|battery PROFILE, show
  shot         screenshots: smart, region, windows, fullscreen
  record       screen recording
  clipboard    clipboard history picker
  emoji        emoji picker
  menu         application and action menu
  pick         the generic picker
  reminder     set and list reminders
  toggle       night light, idle, do-not-disturb
  snapshot     btrfs snapshots of /home: create, list, restore, prune
  update       rebuild and switch the system
  bar          the status bar: toggle, on, off
EOF
}

case "${1:-}" in
  "" | -h | --help | help) usage ;;
  commands)
    # Just the Groups block, one name per line.
    usage | sed -n '/^Groups:/,/^[[:space:]]*$/p' | sed '1d' | awk '{ print $1 }'
    ;;
  theme)
    shift
    exec theme "$@"
    ;;
  textsize | text)
    shift
    exec textsize "$@"
    ;;
  wallpaper)
    shift
    exec wallpaper "$@"
    ;;
  display | monitors)
    shift
    exec monitors "$@"
    ;;
  power | powerprofile)
    shift
    exec powerprofile "$@"
    ;;
  shot | screenshot)
    shift
    exec shot "$@"
    ;;
  record)
    shift
    exec record "$@"
    ;;
  clipboard)
    shift
    exec clipboard "$@"
    ;;
  emoji)
    shift
    exec emoji "$@"
    ;;
  menu)
    shift
    exec menu "$@"
    ;;
  pick)
    shift
    exec pick "$@"
    ;;
  reminder)
    shift
    exec reminder "$@"
    ;;
  toggle)
    shift
    exec toggle "$@"
    ;;
  snapshot)
    shift
    exec snapshot "$@"
    ;;
  update)
    shift
    exec nh os switch "$@"
    ;;
  bar)
    shift
    exec quickshell ipc call bar "$@"
    ;;
  *)
    printf 'anixie: no group called "%s" (try: anixie commands)\n' "$1" >&2
    exit 2
    ;;
esac
