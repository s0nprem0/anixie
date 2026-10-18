{ pkgs, ... }:

{
  imports = [
    ./settings.nix
    ./keybinds.nix
    ./startup.nix
  ];

  # Tools invoked from keybinds.nix and startup.nix. The bar and the launcher
  # ship their own packages, so only the standalone helpers belong here.
  home.packages = with pkgs; [
    awww
    brightnessctl
    cliphist
    grim
    playerctl
    slurp
    wl-clipboard
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "menu";
    };
  };
}
