{ config, ... }:

let
  c = config.myDots.theme.colors;
in
{
  programs.kitty = {
    enable = true;

    settings = {
      font_size = 11;
      background_opacity = "0.96";

      background = c.background;
      foreground = c.foreground;

      selection_background = c.accent;
      selection_foreground = c.background;
    };
  };

  programs.git.enable = true;
  programs.starship.enable = true;
}
