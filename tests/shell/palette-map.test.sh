#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
JQ=${JQ:-jq}

out=$("$JQ" -f "$root/modules/features/theming/palette.jq" --arg fallback dark \
  "$root/tests/shell/fixtures/matugen.json")

[ "$(printf '%s' "$out" | "$JQ" -r '.background')" = "#111418" ]
[ "$(printf '%s' "$out" | "$JQ" -r '.surfaceContainer')" = "#272a2f" ]
[ "$(printf '%s' "$out" | "$JQ" -r '.accent')" = "#d6bee4" ]
[ "$(printf '%s' "$out" | "$JQ" -r '.accentAlt')" = "#bbc7db" ]
[ "$(printf '%s' "$out" | "$JQ" -r '.danger')" = "#ffb4ab" ]
[ "$(printf '%s' "$out" | "$JQ" -r '.ansi4')" = "#a0cafd" ]
[ "$(printf '%s' "$out" | "$JQ" -r '.ansi15')" = "#e1e2e8" ]
[ "$(printf '%s' "$out" | "$JQ" -r '._mode')" = "dark" ]
