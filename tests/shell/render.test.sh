#!/bin/sh
set -eu

root=${REPO_ROOT:-$(pwd)}
. "$root/modules/features/theming/lib/render.sh"

JQ=${JQ:-jq}
SED=${SED:-sed}
TOKENS_JSON="$root/modules/features/theming/tokens.json"
export JQ SED TOKENS_JSON

fixture="$root/tests/shell/fixtures/palette.json"
extras="$root/tests/shell/fixtures/extras.json"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

printf '@BG@ @BG_HEX@ @BG_ALPHA_AA@ @BG_RGBA_AA@ @ANSI_4@ @ANSI_4_HEX@ @GTK_THEME@\n' >"$tmp/sample.tmpl"
render_template "$tmp/sample.tmpl" "$fixture" "$tmp/sample.out" "$extras"
[ "$(cat "$tmp/sample.out")" = "#0f111a 0f111a #0f111aaa rgba(0f111aaa) #123456 123456 Adwaita-dark" ]

for template in "$root"/modules/features/theming/templates/* "$root"/modules/features/wm/share-picker/style.css; do
  out="$tmp/$(basename "$template")"
  render_template "$template" "$fixture" "$out" "$extras"
  if grep -Eq '@[A-Z][A-Z0-9_]*@' "$out"; then
    printf 'unrendered placeholder in %s\n' "$template" >&2
    grep -Eo '@[A-Z][A-Z0-9_]*@' "$out" | sort -u >&2
    exit 1
  fi
done
