{ ... }:

{
  imports = [
    ./settings.nix
    ./keybinds.nix
    ./startup.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "fuzzel";
    };
  };
}
