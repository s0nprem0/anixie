#!/bin/sh
# Feed new clipboard contents into cliphist.
#
# cliphist has no way to know where a selection came from, and password managers
# mark secrets with a hint in the offered MIME types. Storing those would put
# passwords in the history and, worse, in every preview the picker builds. Drop
# the selection instead of storing it.
#
#   clipboard-watch          watch text and images
#   clipboard-watch store    the child mode run once per new selection
#
# wl-paste runs --watch commands through a shell, so the child mode is this
# script again rather than a function that would not exist in that shell.

set -u

cliphist="@CLIPHIST@"
wl_paste="@WL_PASTE@"

is_sensitive() {
  types=$("$wl_paste" --list-types 2>/dev/null || true)
  case "$types" in
    *passwordManagerHint*)
      return 0
      ;;
  esac
  return 1
}

case "${1:-watch}" in
  store)
    if is_sensitive; then
      # Drain the selection so wl-paste can finish its offer, but never let it
      # reach cliphist or, later, a preview file on disk.
      cat >/dev/null
      exit 0
    fi
    exec "$cliphist" store
    ;;
  watch)
    # The path is quoted for the shell wl-paste starts, not for this one. A Nix
    # store path has no quotes or spaces, so this is safe to build by hand.
    watch_child="'$0' store"
    "$wl_paste" --type text --watch "$watch_child" &
    text_watcher=$!
    "$wl_paste" --type image --watch "$watch_child" &
    image_watcher=$!

    trap 'kill "$text_watcher" "$image_watcher" 2>/dev/null' TERM INT
    wait
    ;;
  *)
    echo "usage: clipboard-watch [watch|store]" >&2
    exit 2
    ;;
esac
