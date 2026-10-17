{ config, ... }:

let
  render = config.my.theme.template.render;
in
{
  services.mako = {
    enable = true;

    settings = {
      background-color = render "@BG_ALPHA_F2@";
      text-color = render "@FG@";
      border-color = render "@ACCENT@";

      border-size = 2;
      border-radius = 8;

      padding = "10";
      margin = "10";

      default-timeout = 5000;

      "urgency=high" = {
        border-color = render "@DANGER@";
      };
    };
  };
}
