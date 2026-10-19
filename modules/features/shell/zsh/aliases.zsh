# Better ls (eza required; fall back to plain ls if absent)
if (( $+commands[eza] )); then
  alias ls='eza --icons'
  alias ll='eza -lh --icons --git'      # detailed listing
  alias la='eza -lah --icons --git'     # detailed listing including hidden files
  alias tree='eza --tree --icons'       # tree view
fi

alias git_personal='git config user.email "s0nprem0@proton.me" && git config user.name "s0nprem0"'
alias git_academic='git config user.email "jaysonbulugagao@gmail.com" && git config user.name "202302986"'

# Rebuilds, through nh (NH_FLAKE points at ~/nix-dots).
#
# -e auto is what makes these work from an ordinary shell. Activating a system
# writes /nix/var/nix/profiles/system, which is root-owned, so nh does the build
# and the store work as you and elevates only the activation — and finds sudo for
# that by itself. Without it the switch fails with "Permission denied" on the
# profile symlink, which reads like a broken nix store and is not one.
#
# `nixos-rebuild` without --flake is not behind these: it falls back to the
# channel evaluator and fails on a missing <nixos-config>, which is the error this
# exists to make impossible to hit by accident.
alias nrs='nh -e auto os switch'   # build and activate now
alias nrb='nh -e auto os boot'     # build for the next boot
alias nrt='nh -e auto os test'     # activate a throwaway generation
