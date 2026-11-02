#!/bin/sh
# Keyboard shortcuts.
#
#   shortcuts          every described bind, searchable
#
# Hyprland already carries a description for every bind (see
# hyprland/config/00-helpers.lua), so this is a reader over `hyprctl binds -j`
# rather than a second list that would drift. Selecting a row only closes the
# picker: the sheet is for reading.
#
# Modifier bits are Hyprland's: SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 16,
# MOD3 32, SUPER 64, MOD5 128. A bind in a submap says so before the keys,
# since the same combination can mean something else outside it.

set -eu

hyprctl="@HYPRCTL@"
jq="@JQ@"

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

command -v "$hyprctl" >/dev/null 2>&1 || die "hyprctl not found"
command -v "$jq" >/dev/null 2>&1 || die "jq not found"

binds=$("$hyprctl" binds -j 2>/dev/null) || die "could not read binds from Hyprland"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

printf '%s' "$binds" | "$jq" -r '
  def bit($mask; $n): (($mask / $n | floor) % 2) == 1;

  if type != "array" then
    error("expected a JSON array of binds")
  else
    .
  end
  | [
      .[]
      | select(type == "object")
      | select((.has_description // false) == true)
      | select((.description // "") | type == "string")
      | select((.description // "") != "")
      | select((.modmask // 0) | type == "number")
      | {
          description: ((.description // "") | gsub("[\\t\\n\\r]"; " ")),
          submap: ((.submap // "") | tostring | gsub("[\\t\\n\\r]"; " ")),
          modmask: (.modmask // 0),
          key: (((.key // "") | tostring) | gsub("[\\t\\n\\r]"; " "))
        }
    ]
  | sort_by([.description, .submap, .key])
  | .[]
  | (
      [
        if bit(.modmask; 64) then "SUPER" else empty end,
        if bit(.modmask; 4) then "CTRL" else empty end,
        if bit(.modmask; 8) then "ALT" else empty end,
        if bit(.modmask; 1) then "SHIFT" else empty end,
        if bit(.modmask; 2) then "CAPS" else empty end,
        if bit(.modmask; 16) then "MOD2" else empty end,
        if bit(.modmask; 32) then "MOD3" else empty end,
        if bit(.modmask; 128) then "MOD5" else empty end
      ] as $mods
      | ($mods | join(" + ")) as $modstr
      | (if .key == "" then "(none)" else .key end) as $key
      | (if $modstr == "" then $key else $modstr + " + " + $key end) as $combo
      | (if .submap == "" then $combo else "Submap: " + .submap + " · " + $combo end) as $display
      | [
          .description,
          .description,
          "",
          $display,
          ""
        ]
      | @tsv
    )
' >"$tmp" || die "invalid binds JSON or unexpected structure"

if [ ! -s "$tmp" ]; then
  die "no described shortcuts"
fi

pick --title "Keyboard shortcuts" --placeholder "Search shortcuts" --on-select true <"$tmp"