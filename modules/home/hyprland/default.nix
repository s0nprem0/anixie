{
  wayland.windowManager.hyprland = {
    enable = true;

    settings = {
      "$mod" = "SUPER";
      "$terminal" = "kitty";
      "$menu" = "wofi --show drun";

      exec-once = [
        "waybar"
      ];

      bind = [
        "$mod, RETURN, exec, $terminal"
        "$mod, SPACE, exec, $menu"
        "$mod, Q, killactive,"
        "$mod, F, fullscreen,"
        "$mod, V, togglefloating,"
        "$mod, M, exit,"

        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"

        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"

        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
      ];

      general = {
        gaps_in = 5;
        gaps_out = 10;
        border_size = 2;
        resize_on_border = true;

        "col.active_border" = "rgba(e0a458ff)";
        "col.inactive_border" = "rgba(414652aa)";
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

      misc = {
        force_default_wallpaper = 0;
      };
    };
  };
}
