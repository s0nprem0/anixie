{ pkgs, ... }:

{
  # Everyday CLI tools that have no configuration of their own. Tools that
  # do get their own directory under features/shell/ instead, so this stays
  # limited to bare binaries.
  home.packages = with pkgs; [
    difftastic
    github-cli
    httpie
    jq
    lazygit
    nix-output-monitor
    ripgrep
    tmux
    yq
  ];
}
