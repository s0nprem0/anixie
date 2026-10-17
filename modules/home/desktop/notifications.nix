{ config, ... }:

let
  c = config.my.theme.colors;
in
{
  services.mako = {
    enable = true;

    settings = {
      background-color = "${c.background}f2";
      text-color = c.foreground;
      border-color = c.accent;

      border-size = 2;
      border-radius = 8;

      padding = "10";
      margin = "10";

      default-timeout = 5000;

      "urgency=high" = {
        border-color = c.danger;
      };
    };
  };
}
