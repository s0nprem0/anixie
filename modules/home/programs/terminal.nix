{ config, ... }:

let
  c = config.my.theme.colors;
in
{
  programs.kitty = {
    enable = true;

    font = {
      name = "JetBrains Mono";
      size = 11;
    };

    settings = {
      background_opacity = "0.96";

      background = c.background;
      foreground = c.foreground;

      selection_background = c.accent;
      selection_foreground = c.background;
    };
  };
}
