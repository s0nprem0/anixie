#!/bin/sh
# Rebuild the system.
#
#   update               build and activate now (os switch)
#   update boot          build for the next boot
#   update test          activate a throwaway generation
#   update --allow-dirty build even with untracked files (see below)
#
# The same command is installed as `rebuild`, which is what the nrs/nrb/nrt
# aliases call; the usage above uses the name the `anixie` front door shows.
#
# Everything goes through `nh -e auto`. That is what makes it work from an
# ordinary shell: activating writes /nix/var/nix/profiles/system, which is
# root-owned, so nh does the build and the store work as you and elevates only
# the activation — and finds sudo for that by itself. Without it the switch fails
# with "Permission denied" on the profile symlink, which reads like a broken nix
# store and is not one.
#
# A flake built from a git tree only contains files git knows about. An untracked
# QML file is therefore missing from the store while the panels that reference it
# ship, and the shell crash-loops on a file that exists in the working tree. The
# check below refuses that build by default; --allow-dirty is the deliberate way
# to say the untracked files do not matter. Staged files are tracked in the
# index, so `git add` is enough to get past it, but committing the change keeps
# the generation matching the history.
#
# `nixos-rebuild` without --flake is not behind this: it falls back to the channel
# evaluator and fails on a missing <nixos-config>, which is the error this exists
# to make impossible to hit by accident. `anixie update` and the `nrs`/`nrb`/`nrt`
# aliases all come through here, so the flags are written once.
set -eu

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

mode=""
allow_dirty=0

# Rotate the arguments: modes are consumed here, --allow-dirty is consumed here,
# and everything else is moved to the end and handed to nh unchanged. The
# rotation preserves the remaining arguments exactly, including ones with
# spaces, which a rebuilt "$*" would not. The case subject stays "$1" so the
# table check can read this dispatch like every other command's.
n=$#
while [ "$n" -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --allow-dirty)
      allow_dirty=1
      ;;
    switch | boot | test)
      if [ -n "$mode" ]; then
        die "only one mode at a time (got \"$mode\" and \"$1\")"
      fi
      mode=$1
      ;;
    *)
      set -- "$@" "$1"
      ;;
  esac
  shift
  n=$((n - 1))
done

mode=${mode:-switch}

# The flake path is absolute and substituted at build time. A tree copied out of
# git (or evaluated from a tarball) has no .git, and there is nothing to check
# there; that build is correct to run.
check_tree() {
  [ -d "@FLAKE@/.git" ] || return 0

  if ! command -v git >/dev/null 2>&1; then
    printf '%s: warning: git is not on PATH, skipping the untracked-file check\n' "${0##*/}" >&2
    return 0
  fi

  untracked=$(git -C "@FLAKE@" ls-files --others --exclude-standard)

  if [ -n "$untracked" ]; then
    if [ "$allow_dirty" -eq 1 ]; then
      printf '%s: warning: untracked files are not part of the build:\n%s\n' "${0##*/}" "$untracked" >&2
    else
      printf '%s: these files are untracked and would be invisible to the build:\n%s\n' "${0##*/}" "$untracked" >&2
      die "stage or commit them first, or rerun with --allow-dirty"
    fi
  fi

  modified=$(git -C "@FLAKE@" status --porcelain --untracked-files=no)
  if [ -n "$modified" ]; then
    printf '%s: note: uncommitted tracked changes are included in this build; commit them if the generation should match the history\n' "${0##*/}" >&2
  fi
}

check_tree

exec nh -e auto os "$mode" "@FLAKE@#@HOST@" "$@"
