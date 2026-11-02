#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
JQ=${JQ:-jq}
themes="$root/modules/features/theming/themes.json"
tokens="$root/modules/features/theming/tokens.json"

. "$root/modules/features/theming/lib/color.sh"

atleast() {
  awk -v got="$1" -v want="$2" 'BEGIN { exit !(got + 0 >= want + 0) }'
}

names=$("$JQ" -r 'keys[]' "$themes")

for name in $names; do
  for token in $("$JQ" -r '.colors | keys[]' "$tokens"); do
    if ! "$JQ" -e --arg n "$name" --arg k "$token" '.[$n][$k] | type == "string" and length > 0' "$themes" >/dev/null; then
      printf '%s: missing token %s\n' "$name" "$token" >&2
      exit 1
    fi
  done

  mode=$("$JQ" -r --arg n "$name" '.[$n]._mode // empty' "$themes")
  case "$mode" in
    dark | light) ;;
    *)
      printf '%s: invalid _mode "%s"\n' "$name" "$mode" >&2
      exit 1
      ;;
  esac

  pair=$("$JQ" -r --arg n "$name" '.[$n]._pair // empty' "$themes")
  if [ -n "$pair" ] && ! "$JQ" -e --arg p "$pair" 'has($p)' "$themes" >/dev/null; then
    printf '%s: missing _pair %s\n' "$name" "$pair" >&2
    exit 1
  fi

  bg=$("$JQ" -r --arg n "$name" '.[$n].background' "$themes")
  surface=$("$JQ" -r --arg n "$name" '.[$n].surface' "$themes")
  fg=$("$JQ" -r --arg n "$name" '.[$n].foreground' "$themes")
  muted=$("$JQ" -r --arg n "$name" '.[$n].muted' "$themes")

  atleast "$(color_contrast "$fg" "$bg")" 4.5 || {
    printf '%s: foreground/background contrast is too low\n' "$name" >&2
    exit 1
  }
  atleast "$(color_contrast "$fg" "$surface")" 4.5 || {
    printf '%s: foreground/surface contrast is too low\n' "$name" >&2
    exit 1
  }
  atleast "$(color_contrast "$muted" "$surface")" 4.5 || {
    printf '%s: muted/surface contrast is too low\n' "$name" >&2
    exit 1
  }
done
