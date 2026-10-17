{ pkgs, ... }:

{
  home.packages = with pkgs; [
    fuzzel
    grim
    slurp
    wl-clipboard
    cliphist
    brightnessctl
    playerctl
    awww
  ];
}
