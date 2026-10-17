{ ... }:

{
  imports = [
    ./settings.nix
    ./keybinds.nix
    ./startup.nix
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    configType = "hyprlang";

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "fuzzel";
    };
  };
}
