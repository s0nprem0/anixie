{ config, ... }:

let
  render = config.my.theme.template.render;
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

      background = render "@BG@";
      foreground = render "@FG@";

      selection_background = render "@ACCENT@";
      selection_foreground = render "@BG@";
    };
  };
}
