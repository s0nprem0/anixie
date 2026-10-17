{ config, ... }:

let
  c = config.my.theme.colors;
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
        background = "${builtins.substring 1 6 c.background}ff";
        text = "${builtins.substring 1 6 c.foreground}ff";
        match = "${builtins.substring 1 6 c.accent}ff";
        selection = "${builtins.substring 1 6 c.surface}ff";
        selection-text = "${builtins.substring 1 6 c.foreground}ff";
        border = "${builtins.substring 1 6 c.accent}ff";
      };

      border = {
        width = 2;
        radius = 8;
      };
    };
  };
}
