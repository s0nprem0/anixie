#!/bin/sh
# notify — send a notification the shell can draw and keep.
#
# A front door to notify-send for the things the freedesktop action API cannot
# carry through history: a glyph for the icon slot, a click command, and up to
# three labelled commands. All travel as hints, so they survive the popup moving
# into history and still work when a replay is clicked.
#
#   notify [options] SUMMARY [BODY] [--action LABEL CMD [ARG...]]...
#          [--with ARG...]
#   notify [options] SUMMARY [BODY] [--exec COMMAND [ARG...]]
#
#   -g, --glyph GLYPH       the glyph itself, for callers that can write one
#   -G, --glyph-code HEX    the same, by Unicode code point (e.g. f017)
#   --action LABEL CMD...   a labelled button; up to three, first one is the click
#   --with ARG...           appended to every action; takes the rest of the line
#   -e, --exec COMMAND...   command and arguments run when the card is clicked
#   -a, --app-name NAME     sender name (default: anixie-action)
#   -u, --urgency LEVEL     low, normal or critical (default: low)
#   -t, --expire-time MS    how long the toast stays, in milliseconds
#   -i, --icon NAME         themed icon name or image path
#   -h, --help
#
# The app name defaults to anixie-action, which the shell trusts through
# do-not-disturb: a confirmation for something the user just did should not
# vanish because a chat app asked for quiet.
set -eu

notify_send="@NOTIFY_SEND@"
jq="@JQ@"

usage() {
  cat <<'EOF'
notify — send a notification the shell can draw and keep

Usage:
  notify [options] SUMMARY [BODY] [--action LABEL CMD [ARG...]]...
         [--with ARG...]
  notify [options] SUMMARY [BODY] [--exec COMMAND [ARG...]]

Options:
  -g, --glyph GLYPH       glyph for the icon slot
  -G, --glyph-code HEX    glyph by Unicode code point (e.g. f017)
  --action LABEL CMD...   a labelled button; up to three, first one is the click
  --with ARG...           appended to every action; takes the rest of the line
  -e, --exec COMMAND...   command and arguments run when the card is clicked
  -a, --app-name NAME     sender name (default: anixie-action)
  -u, --urgency LEVEL     low, normal or critical (default: low)
  -t, --expire-time MS    how long the toast stays, in milliseconds
  -i, --icon NAME         themed icon name or image path
  -h, --help              this message
EOF
}

fail() {
  printf 'notify: %s\n' "$1" >&2
  exit 2
}

# Turn a Unicode code point into the bytes of its UTF-8 encoding. POSIX printf
# has no \u escape, but it does interpret octal escapes, so the bytes are built
# by hand. Hex keeps callers readable: an invisible glyph literal in a shell
# script is a maintenance trap.
glyph_from_code() {
  code=$1
  case "$code" in
    '' | *[!0-9a-fA-F]*) return 2 ;;
  esac
  n=$((0x$code))

  if [ "$n" -le 127 ]; then
    printf '%b' "$(printf '\\%03o' "$n")"
  elif [ "$n" -le 2047 ]; then
    printf '%b' "$(printf '\\%03o\\%03o' \
      "$((0xc0 | (n >> 6)))" "$((0x80 | (n & 0x3f)))")"
  elif [ "$n" -le 65535 ]; then
    printf '%b' "$(printf '\\%03o\\%03o\\%03o' \
      "$((0xe0 | (n >> 12)))" \
      "$((0x80 | ((n >> 6) & 0x3f)))" \
      "$((0x80 | (n & 0x3f)))")"
  elif [ "$n" -le 1114111 ]; then
    printf '%b' "$(printf '\\%03o\\%03o\\%03o\\%03o' \
      "$((0xf0 | (n >> 18)))" \
      "$((0x80 | ((n >> 12) & 0x3f)))" \
      "$((0x80 | ((n >> 6) & 0x3f)))" \
      "$((0x80 | (n & 0x3f)))")"
  else
    return 2
  fi
}

want() {
  [ "$2" -ge 2 ] || {
    printf 'notify: %s needs a value\n' "$1" >&2
    exit 2
  }
}

app=anixie-action
urgency=low
glyph=""
exec_json=""
actions_json="[]"
action_count=0
with_json="[]"
with_present=0
icon=""
expire=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -g | --glyph)
      want "$1" "$#"
      glyph=$2
      shift 2
      ;;
    -G | --glyph-code)
      want "$1" "$#"
      glyph=$(glyph_from_code "$2") || {
        printf 'notify: invalid code point "%s"\n' "$2" >&2
        exit 2
      }
      shift 2
      ;;
    -a | --app-name)
      want "$1" "$#"
      app=$2
      shift 2
      ;;
    -u | --urgency)
      want "$1" "$#"
      urgency=$2
      shift 2
      ;;
    -t | --expire-time)
      want "$1" "$#"
      expire=$2
      shift 2
      ;;
    -i | --icon)
      want "$1" "$#"
      icon=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -?*)
      printf 'notify: unknown option "%s"\n' "$1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

[ "$#" -ge 1 ] || {
  printf 'notify: a summary is required\n' >&2
  exit 2
}
summary=$1
shift
body=""
if [ "$#" -gt 0 ] && [ "$1" != "--exec" ] && [ "$1" != "-e" ] \
  && [ "$1" != "--action" ] && [ "$1" != "--with" ]; then
  body=$1
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -e | --exec)
      [ "$action_count" -eq 0 ] ||
        fail "--exec and --action cannot be combined: the card click runs the first action"
      shift
      [ "$#" -ge 1 ] || fail "--exec needs a command"
      exec_json=$("$jq" -cn '$ARGS.positional' --args -- "$@") ||
        fail "could not encode the click command"
      break
      ;;
    --action)
      [ "$action_count" -lt 3 ] || fail "a notification takes at most 3 actions"
      shift
      [ "$#" -ge 2 ] || fail "--action needs a label and a command"
      action_label=$1
      [ -n "$action_label" ] || fail "--action needs a non-empty label"
      shift

      # The action's own words are caller literals. They end at the next
      # --action/--with/--exec; untrusted data goes after --with instead.
      action_words="[]"
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --action | --with | --exec | -e) break ;;
        esac
        action_words=$(printf '%s' "$action_words" |
          "$jq" -cn --argjson a "$action_words" --arg w "$1" '$a + [$w]') ||
          fail "could not encode an action argument"
        shift
      done

      action_argc=$(printf '%s' "$action_words" | "$jq" -r 'length') ||
        fail "could not read the action arguments"
      [ "$action_argc" -ge 1 ] || fail "--action needs a command after the label"

      action_obj=$(printf '%s' "$action_words" |
        "$jq" -cn --arg label "$action_label" --argjson argv "$action_words" \
          '{label: $label, argv: $argv}') ||
        fail "could not encode the action"
      actions_json=$(printf '%s' "$actions_json" |
        "$jq" -c --argjson action "$action_obj" '. + [$action]') ||
        fail "could not collect the actions"
      action_count=$((action_count + 1))
      ;;
    --with)
      shift
      with_json="[]"
      while [ "$#" -gt 0 ]; do
        with_json=$(printf '%s' "$with_json" |
          "$jq" -cn --argjson a "$with_json" --arg w "$1" '$a + [$w]') ||
          fail "could not encode a --with argument"
        shift
      done
      with_present=1
      break
      ;;
    *)
      fail "unexpected argument \"$1\""
      ;;
  esac
done

[ "$with_present" -eq 0 ] || [ "$action_count" -gt 0 ] ||
  fail "--with gives arguments to --action; it needs at least one action"

if [ "$action_count" -gt 0 ]; then
  if [ "$with_present" -eq 1 ]; then
    actions_json=$(printf '%s' "$actions_json" |
      "$jq" -c --argjson with "$with_json" 'map(.argv += $with)') ||
      fail "could not append --with to the actions"
  fi
  # The first action is also the click, as it is on Omarchy.
  exec_json=$(printf '%s' "$actions_json" | "$jq" -c '.[0].argv') ||
    fail "could not set the first action as the click command"
fi

set -- "$notify_send" -a "$app" -u "$urgency"
[ -n "$icon" ] && set -- "$@" -i "$icon"
[ -n "$expire" ] && set -- "$@" -t "$expire"
[ -n "$glyph" ] && set -- "$@" "--hint=string:anixie-glyph:$glyph"
[ -n "$exec_json" ] && set -- "$@" "--hint=string:anixie-exec:$exec_json"
[ "$action_count" -gt 0 ] &&
  set -- "$@" "--hint=string:anixie-actions:$actions_json"

exec "$@" "$summary" "$body"
