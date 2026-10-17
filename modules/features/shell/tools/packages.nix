# Single source of truth for the everyday CLI tools that have no configuration
# of their own. Consumed by ./default.nix (installed into the user profile) and
# by the devshells, so `nix develop` covers the same ground without the two
# lists drifting apart.
{ pkgs, ... }:

with pkgs;
[
  difftastic
  github-cli
  httpie
  jq
  lazygit
  nix-output-monitor
  ripgrep
  tmux
  yq
]
