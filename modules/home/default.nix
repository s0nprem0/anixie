{ pkgs, ... }:

{
  imports = [
    ./options.nix
    ./theme.nix
    ./programs/terminal.nix
    ./waybar.nix
    ./hyprland/default.nix
  ];

  home.username = "son";
  home.homeDirectory = "/home/son";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    wofi
    wl-clipboard
    cliphist
    grim
    slurp
  ];

  xdg.enable = true;
}
