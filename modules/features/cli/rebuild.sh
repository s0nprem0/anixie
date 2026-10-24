#!/bin/sh
# Rebuild the system.
#
#   update               build and activate now (os switch)
#   update boot          build for the next boot
#   update test          activate a throwaway generation
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
# `nixos-rebuild` without --flake is not behind this: it falls back to the channel
# evaluator and fails on a missing <nixos-config>, which is the error this exists
# to make impossible to hit by accident. `anixie update` and the `nrs`/`nrb`/`nrt`
# aliases all come through here, so the flags are written once.
set -eu

# shellcheck source=/dev/null
. "@ANIXIE_LIB@"

case "${1:-switch}" in
  -h | --help)
    usage
    exit 0
    ;;
  switch | boot | test)
    mode=${1:-switch}
    ;;
  *)
    die "unknown mode \"${1:-}\" (try --help)"
    ;;
esac

if [ $# -gt 0 ]; then
  shift
fi
exec nh -e auto os "$mode" "@FLAKE@#@HOST@" "$@"
