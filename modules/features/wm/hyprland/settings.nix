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

    # Keys for the screenshot picker, scoped to slurp's layer surface so they do
    # nothing at any other time.
    #
    # slurp names its layer "selection" — not "slurp", which is what you would
    # guess, and which matches nothing. Without these the picker can only be
    # driven with the mouse.
    layerrule = {
      name = "anixie-screenshot-picker";
      matchlayer = "/^selection$/";

      binds = {
        # RETURN takes the whole window under the pointer, CTRL+RETURN the
        # monitor. TAB moves between windows and CTRL+TAB goes back.
        "code:36" = "exec, shot-pick --take-window";
        "CTRL, code:36" = "exec, shot-pick --take-fullscreen";

        "code:15" = "exec, shot-pick --select-window next";
        "CTRL, code:15" = "exec, shot-pick --select-window prev";

        # The nearest window in that direction, rather than the nearest window
        # overall: moving left should find the one to the left.
        "code:105" = "exec, shot-pick --select-window left";
        "code:106" = "exec, shot-pick --select-window right";
        "code:103" = "exec, shot-pick --select-window up";
        "code:108" = "exec, shot-pick --select-window down";
      };
    };
  };
}
