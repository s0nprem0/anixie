#!/bin/sh
# The application side of the menu.
#
#   menu                 the menu: every command and every application
#   menu apps            the menu, applications only
#   menu firefox         launch an application without asking
#   menu list            names and icons, for the menu's own provider
#
# The searching and the drawing are the shell's picker now, which is what makes
# the applications able to carry their icons — the old launcher handed the whole
# applications directory to fuzzel through XDG_DATA_DIRS and let fuzzel do both.
# What is left here is the question NixOS makes awkward: which applications are
# installed, and what each one's icon is called.
#
# A desktop entry on a normal Linux lives in one of the XDG data directories.
# On NixOS it lives inside the store path of the package that ships it, and
# nothing puts those on the search path — so a launcher that walks XDG_DATA_DIRS
# finds five system utilities and misses Firefox. They are found instead by
# asking Nix what the profile closes over, which is a few hundred paths and
# takes about a second.
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

# The menu itself. Bare `menu` is the menu; `menu apps` is the same menu with the
# applications filter, which is now all the icon-carrying launcher needs to be —
# the picker draws each entry's icon, so there is no separate launcher mode to
# keep in step. `list` is what the menu's Applications provider reads.
case "${1:-}" in
  "")
    exec "@MENU_TREE@"
    ;;
  apps)
    exec "@MENU_TREE@" --only Applications
    ;;
  list)
    # Names and their icons, tab-separated, in the order the farm holds them,
    # deduplicated: two desktop entries can carry the same Name, and the menu
    # cannot tell those apart.
    #
    # One awk over every file rather than one awk per file. The closure holds a
    # few hundred desktop entries, and spawning a process for each of them cost
    # about a quarter of a second on every menu open — for a loop that only had
    # to read some lines.
    #
    # The icon is the entry's own Icon= line, which is the same name fuzzel's
    # launcher mode resolved for itself, so the menu draws what the launcher drew
    # without needing the launcher.
    #
    # A change of FILENAME is what says a new file has started, so whatever the
    # last one collected is flushed then. GNU awk's ENDFILE would do the same and
    # is shorter, but this is portable and the shell's awk is not guaranteed to
    # be GNU's.
    set -- "$apps"/*.desktop
    [ -e "$1" ] || exit 0

    awk -F= '
      FILENAME != file { flush(); file = FILENAME; name = ""; icon = ""; inentry = 0 }
      /^\[/ { inentry = ($0 == "[Desktop Entry]") }
      inentry && /^Name=/ && name == "" { name = substr($0, 6) }
      inentry && /^Icon=/ && icon == "" { icon = substr($0, 6) }
      END { flush() }
      function flush() {
        if (name != "" && !seen[name]++) printf "%s\t%s\n", name, icon
      }
    ' "$@"
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
