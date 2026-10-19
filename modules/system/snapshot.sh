#!/bin/sh
# Btrfs snapshots of /home.
#
# The system already rolls back through NixOS generations, so what is worth
# snapshotting is the data Nix does not own. /home is a btrfs subvolume
# (subvol=home in hardware-configuration.nix), and the snapshots are read-only
# copies kept on the root subvolume, in a directory that is not itself inside
# /home — which is the whole reason a snapshot can be taken live, with nothing
# unmounted and no service stopped. A snapshot of / would be a snapshot into
# itself, so it is deliberately not attempted; boot a previous generation for
# that instead.
#
# The timer in modules/system/snapshot.nix runs `snapshot create auto` daily. The
# rest is for the command line:
#
#   snapshot                 create one, tagged "manual"
#   snapshot create [tag]    create one
#   snapshot list            newest first
#   snapshot restore NAME    copy a snapshot back over /home
#   snapshot prune [keep]    delete all but the newest N (default below)
#
# restore is a copy, not a subvolume swap: /home is mounted and busy, so it
# cannot be replaced underneath the running session. rsync puts the old files
# back in place; programs already running keep the copies they have open until
# they are restarted.
set -eu

DEST="@DEST@"
KEEP="@KEEP@"
BTRFS="@BTRFS@"
SUDO="@SUDO@"
RSYNC="@RSYNC@"

die() {
  printf 'snapshot: %s\n' "$1" >&2
  exit 1
}

# Root when the timer runs it, sudo when a person does.
run() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else "$SUDO" "$@"; fi
}

create() {
  label="${1:-manual}"
  ts="$(date +%Y%m%d-%H%M%S)"
  run mkdir -p "$DEST"
  run "$BTRFS" subvolume snapshot -r /home "$DEST/home-$ts-$label" ||
    die "could not snapshot /home"
  prune >/dev/null
  printf 'home-%s-%s\n' "$ts" "$label"
}

list() {
  run mkdir -p "$DEST"
  if [ -z "$(run ls -A "$DEST" 2>/dev/null)" ]; then
    echo "No snapshots."
    return
  fi
  run ls -1 -- "$DEST" | grep -v '^\.' | sort -r
}

# Newest first, keep the head, delete the rest.
prune() {
  keep="${1:-$KEEP}"
  run mkdir -p "$DEST"
  run ls -1 -- "$DEST" 2>/dev/null | grep -v '^\.' | sort -r | tail -n +$((keep + 1)) |
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      run "$BTRFS" subvolume delete "$DEST/$name" >/dev/null 2>&1 || true
    done
}

restore() {
  [ $# -ge 1 ] && [ -n "$1" ] || die "restore needs a snapshot name (see: snapshot list)"
  src="$DEST/$1"
  run test -d "$src" || die "no snapshot called \"$1\""
  printf 'Restoring %s over /home...\n' "$1"
  run "$RSYNC" -aHAX --delete "$src"/ /home/
  printf 'Done. Running programs keep the files they have open until restarted.\n'
}

case "${1:-}" in
  "" | create) create "${2:-manual}" ;;
  list | ls) list ;;
  prune) prune "${2:-$KEEP}" ;;
  restore) restore "${2:-}" ;;
  *)
    die "usage: snapshot [create [tag] | list | restore NAME | prune [keep]]"
    ;;
esac
