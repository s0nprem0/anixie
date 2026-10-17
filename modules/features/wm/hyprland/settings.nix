{ config, ... }:

let
  render = config.my.theme.template.render;
in
{
  wayland.windowManager.hyprland.settings = {
    general = {
      gaps_in = 5;
      gaps_out = 10;
      border_size = 2;
      resize_on_border = true;

      "col.active_border" = render "@PRIMARY_RGBA_FF@";

      "col.inactive_border" = render "@MUTED_RGBA_AA@";
    };

    decoration = {
      rounding = 8;
      active_opacity = 0.97;
      inactive_opacity = 0.94;

      shadow.enabled = true;

      blur = {
        enabled = true;
        size = 5;
        passes = 2;
      };
    };

    input = {
      kb_layout = "us";
      follow_mouse = 1;
      touchpad.natural_scroll = true;
    };

    misc.force_default_wallpaper = 0;
  };
}
