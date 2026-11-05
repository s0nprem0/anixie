#!/bin/bash
# Check or signal the recorder this shell started.
#
#   record-process --pid N                exit 0 while N is a running recorder
#   record-process --pid N --signal INT   signal it
#   record-process                        exit 0 while any recorder of ours runs
#
# The executable is checked, not just the process name. Linux truncates a process
# name to 15 characters, so gpu-screen-recorder runs as "gpu-screen-reco" and a
# plain `pgrep -x` would match any other executable sharing that prefix — and a
# process can rename itself besides. Resolving /proc/<pid>/exe settles both.
#
# The candidate list comes from the process table. On the real machine that is
# `pgrep`, which is the fast path; when RECORD_PROC_ROOT points at a fixture
# tree (the tests) the tree is walked directly, so the override is actually
# usable instead of being shadowed by the host's process list.
#
# Exits 1 when nothing matched. `record --status` and the bar indicator both read
# that as "not recording".

set -uo pipefail

# Overridable so the matching can be exercised against a fixture tree rather than
# the running machine's /proc.
proc_root=${RECORD_PROC_ROOT:-/proc}
# A trailing slash would make the /proc fast-path check miss and double up in
# paths, so normalize before anything reads it.
if [ "$proc_root" != "/" ]; then
  proc_root=${proc_root%/}
fi

usage() {
  printf 'Usage: record-process [--pid <pid>] [--signal INT|KILL]\n' >&2
  exit 2
}

wanted=" "
signal=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pid)
      [ $# -ge 2 ] || usage
      case "$2" in
        '' | *[!0-9]*) usage ;;
      esac
      wanted+="$2 "
      shift 2
      ;;
    --signal)
      [ $# -ge 2 ] || usage
      case "$2" in
        INT | KILL) signal="$2" ;;
        *) usage ;;
      esac
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

is_recorder() {
  local exe
  exe=$(readlink "$proc_root/$1/exe" 2>/dev/null) || return 1
  # Linux appends this when an upgrade unlinks a still-running executable.
  exe=${exe% (deleted)}
  exe=${exe##*/}
  [ "$exe" = "gpu-screen-recorder" ]
}

# Whether pid $1 belongs to the current user. A missing status file (a fixture
# tree, or a pid that vanished) is not a reason to drop it.
same_user() {
  local uid
  [ -r "$proc_root/$1/status" ] || return 0
  # pgrep -u matches the effective uid, which is the second number on the
  # Uid line (real, effective, saved, fs). Fall back to the first when the
  # line carries a single value, so simple fixture trees keep working.
  uid=$(awk '/^Uid:/{if (NF >= 3) print $3; else print $2; exit}' "$proc_root/$1/status" 2>/dev/null)
  [ -z "$uid" ] || [ "$uid" = "$(id -u)" ]
}

matched=()

if [ "$wanted" != " " ]; then
  # A pid was named, so only those are candidates.
  for pid in $wanted; do
    [ -n "$pid" ] || continue
    same_user "$pid" || continue
    is_recorder "$pid" && matched+=("$pid")
  done
else
  if [ "$proc_root" = "/proc" ]; then
    while read -r pid; do
      [ -n "$pid" ] || continue
      is_recorder "$pid" && matched+=("$pid")
    done < <(pgrep -u "$(id -u)" -f 'gpu-screen-recorder' 2>/dev/null)
  else
    for entry in "$proc_root"/[0-9]*; do
      [ -d "$entry" ] || continue
      pid=${entry##*/}
      case "$pid" in *[!0-9]*) continue ;; esac
      same_user "$pid" || continue
      is_recorder "$pid" && matched+=("$pid")
    done
  fi
fi

[ ${#matched[@]} -gt 0 ] || exit 1

if [ -n "$signal" ]; then
  delivered=0
  for pid in "${matched[@]}"; do
    # The pid can be reused between discovery and kill, so the exe is re-checked
    # here rather than trusted from the loop above.
    if is_recorder "$pid" && kill "-$signal" "$pid" 2>/dev/null; then
      delivered=1
    fi
  done
  # A recorder that exited before its signal had stopped anyway, so only a signal
  # that reached nothing is a failure.
  [ "$delivered" -eq 1 ] || exit 1
fi

exit 0
