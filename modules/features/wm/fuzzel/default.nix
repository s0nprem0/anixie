{ config, ... }:

let
  render = config.my.theme.template.render;
in
{
  programs.fuzzel = {
    enable = true;

    settings = {
      main = {
        terminal = "kitty";
        font = "JetBrains Mono:size=11";
        prompt = "❯ ";
        width = 50;
        horizontal-pad = 20;
        vertical-pad = 12;
        inner-pad = 8;
      };

      colors = {
        background = render "@BG_BARE_FF@";
        text = render "@FG_BARE_FF@";
        match = render "@ACCENT_BARE_FF@";
        selection = render "@SURFACE_BARE_FF@";
        selection-text = render "@FG_BARE_FF@";
        border = render "@ACCENT_BARE_FF@";
      };

      border = {
        width = 2;
        radius = 8;
      };
    };
  };
}
