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

binds=$("$hyprctl" binds -j 2>/dev/null) || die "could not read binds from Hyprland"

printf '%s' "$binds" | "$jq" -r '
  def bit($mask; $n): (($mask / $n | floor) % 2) == 1;

  .[]
  | select(.has_description == true and (.description // "") != "")
  | . as $bind
  | (
      [
        if bit($bind.modmask; 64) then "SUPER" else empty end,
        if bit($bind.modmask; 4) then "CTRL" else empty end,
        if bit($bind.modmask; 8) then "ALT" else empty end,
        if bit($bind.modmask; 1) then "SHIFT" else empty end,
        if bit($bind.modmask; 2) then "CAPS" else empty end,
        if bit($bind.modmask; 16) then "MOD2" else empty end,
        if bit($bind.modmask; 32) then "MOD3" else empty end,
        if bit($bind.modmask; 128) then "MOD5" else empty end
      ]
      | join(" + ")
    ) as $mods
  | [
      $bind.description,
      $bind.description,
      "",
      (if $bind.submap != "" then $bind.submap + " · " else "" end)
        + (if $mods == "" then $bind.key else $mods + " + " + $bind.key end),
      ""
    ]
  | @tsv
' | sort | pick --title "Keyboard shortcuts" --placeholder "Search shortcuts" --on-select true
