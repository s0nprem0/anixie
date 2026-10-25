#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
. "$root/modules/features/theming/lib/color.sh"

JQ=${JQ:-jq}

check() {
  awk -v got="$1" -v want="$2" 'BEGIN { exit !(got + 0 == want + 0) }'
}

atleast() {
  awk -v got="$1" -v want="$2" 'BEGIN { exit !(got + 0 >= want + 0) }'
}

check "$(color_luminance '#ffffff')" 1
check "$(color_luminance '#000000')" 0
check "$(color_contrast '#ffffff' '#000000')" 21

[ "$(color_mix '#000000' '#ffffff' 0)" = "#000000" ]
[ "$(color_mix '#000000' '#ffffff' 1)" = "#ffffff" ]

adjusted=$(color_adjust_contrast '#111111' '#0f111a' 4.5)
atleast "$(color_contrast "$adjusted" '#0f111a')" 4.5

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$root/tests/shell/fixtures/palette.json" "$tmp/palette.json"
"$JQ" --arg v '#222222' '.foreground = $v' "$tmp/palette.json" >"$tmp/bad.json"

color_palette_fix "$tmp/bad.json"
fg=$("$JQ" -r '.foreground' "$tmp/bad.json")
atleast "$(color_contrast "$fg" '#0f111a')" 4.5
atleast "$(color_contrast "$fg" '#1a1c2b')" 4.5
