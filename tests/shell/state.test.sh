#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

STATE_DIR="$tmp/theme"
DEFAULT_THEME="tokyo-night"
JQ=${JQ:-jq}
FLOCK=${FLOCK:-flock}
export STATE_DIR DEFAULT_THEME JQ FLOCK

. "$root/modules/features/theming/lib/state.sh"

mkdir -p "$STATE_DIR"
printf 'catppuccin-mocha\n' >"$STATE_DIR/current"
printf 'dark\n' >"$STATE_DIR/mode"
printf '{"background":"#1e1e2e"}\n' >"$STATE_DIR/palette.json"

state_migrate
"$JQ" -e '.version == 1 and .source == "preset" and .theme == "catppuccin-mocha"' "$STATE_DIR/state.json" >/dev/null

"$JQ" '.future = true' "$STATE_DIR/state.json" >"$tmp/state.json"
mv "$tmp/state.json" "$STATE_DIR/state.json"
state_ensure
"$JQ" -e '.version == 1 and .future == true' "$STATE_DIR/state.json" >/dev/null

printf 'not json\n' >"$STATE_DIR/state.json"
state_ensure
"$JQ" -e '.version == 1' "$STATE_DIR/state.json" >/dev/null
[ -f "$STATE_DIR/state.json.bad" ]

state_set_theme "gruvbox-dark" preset
"$JQ" -e '.version == 1 and .theme == "gruvbox-dark" and .source == "preset" and .recent[0] == "gruvbox-dark"' "$STATE_DIR/state.json" >/dev/null

rm -f "$STATE_DIR/current"
state_migrate
"$JQ" -e '.version == 1' "$STATE_DIR/state.json" >/dev/null
