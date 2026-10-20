#!/usr/bin/env bash
# Put the hyprlang config back, without needing a rebuild.
#
# The Lua config's binds cannot be removed by `hyprctl reload` — they are
# registered against a Lua state, and reloading a hyprlang config does not clear
# them. If the keyboard stops behaving, this points ~/.config/hypr at the
# hyprlang files from a build and reloads.
#
# Usage:
#   ./revert-hyprland.sh [FILES]
#
# FILES is a home-manager-files store path (the directory that holds .config/hypr;
# find the one in use with `readlink ~/.config/hypr/hypridle.conf`). With no
# argument, the build the running system already points at is re-applied, which
# repairs a hand-edited config but not a bad build. To recover a known-good one:
#
#   git checkout <commit> -- modules/features/wm/hyprland/
#   nix build --impure --no-link --print-out-paths \
#     '.#nixosConfigurations.vivobook.config.home-manager.users.son.home-files'
#   ./revert-hyprland.sh <the /nix/store path it prints>
#
# This file is deliberately not installed by the flake: it has to be runnable
# when the configuration it would rebuild is the thing that is broken.
set -euo pipefail

die() {
  printf 'revert-hyprland: %s\n' "$1" >&2
  exit 1
}

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

# The home-manager-files build the running config points at, if it points at one.
current_files() {
  local link="$HOME/.config/hypr/hypridle.conf" target
  [ -L "$link" ] || return 1
  # One hop, not `readlink -f`: the file inside home-manager-files is itself a
  # symlink to the generated file in another store path, and following it all the
  # way would walk out of the build and leave us with the wrong root.
  target=$(readlink "$link") || return 1
  case "$target" in
    /*) ;;
    *) target="$(dirname "$link")/$target" ;;
  esac
  # .../home-manager-files/.config/hypr/hypridle.conf -> up three is the root.
  dirname "$(dirname "$(dirname "$target")")"
}

# A path may be the files root (.config/hypr inside it) or the hypr dir itself.
resolve() {
  local p="$1"
  if [ -d "$p/.config/hypr" ]; then
    printf '%s\n' "$p/.config/hypr"
  elif [ -d "$p" ] && [ -f "$p/hyprland.conf" ]; then
    printf '%s\n' "$p"
  else
    die "no hyprland.conf under $p"
  fi
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

files="${1:-}"
if [ -z "$files" ]; then
  files=$(current_files) || {
    die "cannot tell which build is running; pass a home-manager-files path (try --help)"
  }
fi

conf=$(resolve "$files")
[ -f "$conf/hyprland.conf" ] || die \
  "$conf has no hyprland.conf — the running build is probably the Lua one; pass the home-manager-files path of a hyprlang build (try --help)"

cd "$HOME/.config/hypr"
rm -f hyprland.lua .luarc.json
ln -sfn "$conf/hyprland.conf" hyprland.conf
ln -sfn "$conf/hypridle.conf" hypridle.conf
ln -sfn "$conf/hyprsunset.conf" hyprsunset.conf

hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null 2>&1 || true
hyprctl reload >/dev/null

printf 'hyprlang config restored from %s\n' "$conf"
printf 'A reload may not be enough; restart Hyprland if the keys still misbehave.\n'
