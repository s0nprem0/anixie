{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Application launcher
    fuzzel

    # Screenshots
    grim
    slurp

    # Clipboard
    wl-clipboard
    cliphist

    # Laptop controls
    brightnessctl
    playerctl
  ];

  # Desktop notifications
  services.mako = {
    enable = true;
  };
}
