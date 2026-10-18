#!/usr/bin/env bash
# Put the hyprlang config back, without needing a rebuild.
#
# The Lua config's binds cannot be removed by `hyprctl reload` — they are
# registered against a Lua state, and reloading a hyprlang config does not
# clear them. If the keyboard stops behaving, this points
# ~/.config/hypr/hyprland.conf at the last good hyprlang build and reloads.
#
# Usage: ./revert-hyprland.sh
set -euo pipefail

GOOD=/nix/store/57dw0xh065is5zhcapq67krm5msdgnjb-home-manager-files
CONF="$GOOD/.config/hypr"

if [ ! -f "$CONF/hyprland.conf" ]; then
  echo "The known-good build is gone from the store: $GOOD" >&2
  echo "Rebuild it instead:" >&2
  echo "  git checkout ce98513 -- modules/features/wm/hyprland/" >&2
  echo "  nix build --impure --no-link '.#nixosConfigurations.vivobook.config.home-manager.users.son.home-files'" >&2
  exit 1
fi

cd "$HOME/.config/hypr"
rm -f hyprland.lua .luarc.json
ln -sfn "$CONF/hyprland.conf" hyprland.conf
ln -sfn "$CONF/hypridle.conf" hypridle.conf
ln -sfn "$CONF/hyprsunset.conf" hyprsunset.conf

hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true
hyprctl reload >/dev/null

echo "hyprlang config restored. reload may need a Hyprland restart to take fully."