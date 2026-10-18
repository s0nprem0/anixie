#!/bin/sh
# The application launcher.
#
#   menu                 search and launch an application
#   menu firefox         launch it without asking
#
# fuzzel does the searching, the icons and the launching; this only has to
# answer the question NixOS makes awkward: which applications are installed.
#
# A desktop entry on a normal Linux lives in one of the XDG data directories.
# On NixOS it lives inside the store path of the package that ships it, and
# nothing puts those on the search path — so a launcher that walks XDG_DATA_DIRS
# finds five system utilities and misses Firefox. They are found instead by
# asking Nix what the profile closes over, which is a few hundred paths and
# takes about a second.
#
# The entries are then linked into a directory of their own and handed to fuzzel
# through XDG_DATA_DIRS, so fuzzel sees an ordinary applications directory and
# behaves exactly as it would anywhere else: it renders each entry's own icon,
# and it launches the entry rather than a command line reconstructed from it.
#
# The farm is cached under the profile it was built from, so a rebuild
# invalidates it and a keypress does not pay for it.

set -eu

profile="${MENU_PROFILE:-/etc/profiles/per-user/son}"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/anixie-menu"
terminal="${TERMINAL:-@TERMINAL@}"

profile_target=$(readlink -f "$profile" 2>/dev/null || printf 'none')
cache="$cache_dir/$(printf '%s' "$profile_target" | md5sum | cut -d' ' -f1)"
apps="$cache/applications"

if [ ! -d "$apps" ]; then
  # Built beside the cache, not inside it: the finished directory is put in
  # place with a rename, and a rename cannot swap something for a directory it
  # is already inside.
  staging="$cache_dir/.staging.$$"
  rm -rf "$staging"
  mkdir -p "$staging/applications"

  # Both closures: the user's, for what they installed, and the system's, for
  # what a NixOS module brought in. Both are cheap to ask and both hold
  # applications worth launching.
  {
    nix-store -qR "$profile_target" 2>/dev/null
    nix-store -qR /run/current-system/sw 2>/dev/null
  } | sort -u | while read -r path; do
    [ -d "$path/share/applications" ] || continue
    ls "$path/share/applications"/*.desktop 2>/dev/null
  done | while read -r desktop; do
    # Named by its desktop entry id, which is the identifier everything else
    # agrees on. Two packages can ship the same id; the first one wins, since
    # the list is sorted and the alternative is one file overwriting another.
    ln -sfn "$desktop" "$staging/applications/$(basename "$desktop")"
  done

  rm -rf "$cache"
  mkdir -p "$cache_dir"
  mv "$staging" "$cache"
fi

# The menu itself. `apps` is the icon-carrying launcher, kept because the menu is
# text-only — fuzzel's dmenu mode draws no icons — and picking an application is
# the one case where the icon is worth more than the search. `list` is what the
# menu's Applications provider reads.
case "${1:-}" in
  "")
    exec "@MENU_TREE@"
    ;;
  apps)
    # fuzzel's launcher mode: it reads the applications directory itself, so each
    # entry's own icon is resolved through the icon theme rather than by us, and
    # the entry is launched exactly as its Exec line says.
    XDG_DATA_DIRS="$cache:$XDG_DATA_DIRS" exec @FUZZEL@ --prompt='launch ' --width 60 --lines 12
    ;;
  list)
    # Names, in the order the farm holds them, deduplicated: two desktop entries
    # can carry the same Name, and the menu cannot tell those apart.
    for candidate in "$apps"/*.desktop; do
      [ -e "$candidate" ] || continue
      awk -F= '
        /^\[/ { inentry = ($0 == "[Desktop Entry]") }
        inentry && /^Name=/ { print substr($0, 6); exit }
      ' "$candidate"
    done | awk '!seen[$0]++'
    exit 0
    ;;
esac

if [ $# -gt 0 ]; then
  # A named application is launched directly, so the launcher can be scripted.
  #
  # Matched on the entry's Name rather than its file name: the farm is named by
  # desktop id, which is `btop.desktop` for something everyone calls `btop++`.
  entry=""
  for candidate in "$apps"/*.desktop; do
    [ -e "$candidate" ] || continue
    found=$(awk -F= -v want="$1" '
      /^\[/ { inentry = ($0 == "[Desktop Entry]") }
      inentry && /^Name=/ { if (substr($0, 6) == want) { print FILENAME; exit } }
    ' "$candidate")
    [ -n "$found" ] || continue
    entry="$found"
    break
  done

  if [ -z "$entry" ]; then
    printf 'menu: no application called "%s"\n' "$1" >&2
    exit 1
  fi

  command=$(awk -F= '
    /^\[/ { inentry = ($0 == "[Desktop Entry]") }
    !inentry { next }
    /^Exec=/ {
      cmd = substr($0, 6)
      gsub(/%[fFuUick%]/, "", cmd)
      gsub(/[[:space:]]+/, " ", cmd)
      sub(/^ +/, "", cmd); sub(/ +$/, "", cmd)
      print cmd
      exit
    }
  ' "$entry")

  needs_terminal=$(awk -F= '
    /^\[/ { inentry = ($0 == "[Desktop Entry]") }
    inentry && /^Terminal=/ { print (tolower(substr($0, 10)) == "true") ? 1 : 0; exit }
  ' "$entry")

  [ -n "$command" ] || exit 1

  if [ "$needs_terminal" = "1" ]; then
    setsid -f "$terminal" -e "$command" >/dev/null 2>&1
  else
    setsid -f sh -c "$command" >/dev/null 2>&1 &
  fi
  exit 0
fi
