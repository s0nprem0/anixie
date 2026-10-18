{ config, ... }:

let
  render = config.my.theme.template.render;
in
{
  wayland.windowManager.hyprland.settings = {
    # Native resolution with no HiDPI scaling: the panel is already 1920x1080,
    # so 1.0 gives a full 1920x1080 workspace instead of 1280x720.
    monitor = ",preferred,auto,1";

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

    # The screenshot picker's keys are NOT bound here. Binding them to slurp's
    # layer needs `layerrule { matchlayer = ...; binds { ... } }`, which this
    # Hyprland does not have: `hyprctl getoption layerrule` answers "no such
    # option", and every key in such a block is reported as "config option does
    # not exist". It was written from a shell that targets a newer Hyprland and
    # it produced a config full of errors here rather than working quietly.
    #
    # So the picker is mouse-only for now. The keys it would take — RETURN,
    # CTRL+RETURN, TAB, CTRL+TAB and the arrows — are listed in the usage text of
    # shot-pick, and become bindable the moment this Hyprland grows layerrule.
  };
}
