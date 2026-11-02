#!/bin/sh
# Shared helpers for the anixie commands.
#
# Sourced, not run: each command uses `usage` and `die` as if they were its own.
# Writing them once is what keeps the header-as-manual trick and the error format
# from drifting between a dozen scripts.
#
# It sets no shell options itself, because those are the caller's: every command
# starts with at least `set -u`, and the long-running or best-effort ones stop at
# `set -uo pipefail` on purpose. Those scripts probe optional hardware and
# services where one failure is an answer, not a reason to abort, and they check
# the exit codes that matter. New scripts should follow that split rather than
# adding `-e` to a probe.
#
# The header comment is the manual, so it is printed rather than copied out a
# second time, where it would drift. It runs from line 2 to the first line that
# is not a comment — which is usually `set -eu` — and that line is dropped.
#
# Line 2, not 1: the file Home Manager installs has its own shebang prepended, so
# the script's own `#!/bin/sh` is line 2 and would otherwise print as `!/bin/sh`
# once the leading `#` is stripped. Any shebang line left in range goes first.

usage() {
  sed -n '2,/^[^#]/p' "$0" | sed -e '$d' -e '/^#!/d' -e 's/^# \{0,1\}//'
}

# The program name comes from the script itself rather than a variable each
# command has to set, so an error cannot report the wrong name.
die() {
  printf '%s: %s\n' "${0##*/}" "$1" >&2
  exit 1
}
