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
# wl-paste runs the watched command directly, so the child mode is this script
# again with an explicit "store" argument.

set -u

cliphist="@CLIPHIST@"
wl_paste="@WL_PASTE@"

# Single-instance guard. The compositor starts this on hyprland.start; a
# restart (or a double exec) would otherwise stack a second watcher feeding
# duplicate entries into cliphist. PID file in XDG_RUNTIME_DIR survives
# restarts of this script but not a login (tmpfs), which is the right lifetime.
pid_file="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/clipboard-watch.pid"
if [ -f "$pid_file" ]; then
  existing=$(cat "$pid_file" 2>/dev/null || true)
  if [ -n "${existing:-}" ] && kill -0 "$existing" 2>/dev/null; then
    exit 0
  fi
fi
mkdir -p "$(dirname "$pid_file")" 2>/dev/null || true
printf '%s\n' "$$" > "$pid_file" 2>/dev/null || true
trap 'rm -f "$pid_file" 2>/dev/null' TERM INT EXIT

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
    # wl-paste execs the watched command directly (it does not invoke a shell),
    # so pass the script and its "store" argument as separate argv entries.
    "$wl_paste" --type text --watch "$0" store &
    text_watcher=$!
    "$wl_paste" --type image --watch "$0" store &
    image_watcher=$!

    trap 'kill "$text_watcher" "$image_watcher" 2>/dev/null' TERM INT
    wait
    ;;
  *)
    echo "usage: clipboard-watch [watch|store]" >&2
    exit 2
    ;;
esac
