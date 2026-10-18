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
# The candidate list is found with `pgrep -f`, which matches the full command
# line: the recorder is started by its store path, so that path is what appears
# there. Every candidate is then confirmed by its exe, so a shell that merely
# mentions the name in an argument does not count.
#
# Exits 1 when nothing matched. `record --status` and the bar indicator both read
# that as "not recording".

set -uo pipefail

# Overridable so the matching can be exercised against a fixture tree rather than
# the running machine's /proc.
proc_root=${RECORD_PROC_ROOT:-/proc}

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

matched=()
while read -r pid; do
  [ -n "$pid" ] || continue
  # A pid was named, so only that one counts; otherwise every recorder of ours is
  # a candidate. Membership rather than a loop, because `wanted` is a flat list.
  if [ "$wanted" != " " ]; then
    case "$wanted" in
      *" $pid "*) ;;
      *) continue ;;
    esac
  fi
  is_recorder "$pid" && matched+=("$pid")
done < <(pgrep -u "$(id -u)" -f 'gpu-screen-recorder' 2>/dev/null)

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
