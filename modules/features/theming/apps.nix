{
  config,
  ...
}:

let
  # One palette, every app. Each of these is read when its program starts, so a
  # theme switched at runtime reaches the shell, Hyprland and kitty at once and
  # the rest at their next start — see theme.sh, which is honest about it.
  render = config.my.theme.template.render;
  c = config.my.theme.colors;
  light = config.my.theme.mode == "light";
in
{
  # ---- Helix ----
  #
  # Inherits a built-in theme so the syntax set stays complete — Helix has far
  # more scopes than a palette has colours, and a theme that names only some of
  # them inherits the system colours for the rest anyway. The light and dark
  # base16 themes are the two that match the palette's mode. What the palette
  # does own is the chrome and the handful of syntax roles you actually read:
  # background, text, gutter, selection, statusline, comments, keys, strings.
  programs = {
    helix = {
      settings.theme = "anixie";

      themes.anixie = {
        inherits = if light then "base16_default_light" else "base16_default_dark";

        "ui.background" = {
          bg = c.background;
        };
        "ui.text" = {
          fg = c.foreground;
        };
        "ui.cursor" = {
          fg = c.background;
          bg = c.primary;
        };
        "ui.cursor.primary" = {
          fg = c.background;
          bg = c.primary;
        };
        "ui.cursor.match" = {
          fg = c.accentAlt;
          bg = c.surface;
        };
        "ui.selection" = {
          bg = c.surface;
        };
        "ui.selection.primary" = {
          bg = c.surface;
        };
        "ui.linenr" = {
          fg = c.muted;
        };
        "ui.linenr.selected" = {
          fg = c.primary;
        };
        "ui.statusline" = {
          fg = c.foreground;
          bg = c.surface;
        };
        "ui.statusline.inactive" = {
          fg = c.muted;
          bg = c.surface;
        };
        "ui.statusline.normal" = {
          fg = c.background;
          bg = c.primary;
        };
        "ui.statusline.insert" = {
          fg = c.background;
          bg = c.success;
        };
        "ui.statusline.select" = {
          fg = c.background;
          bg = c.accentAlt;
        };
        "ui.popup" = {
          fg = c.foreground;
          bg = c.surface;
        };
        "ui.window" = {
          fg = c.muted;
        };
        "ui.menu" = {
          fg = c.foreground;
          bg = c.surface;
        };
        "ui.menu.selected" = {
          fg = c.background;
          bg = c.primary;
        };
        "ui.virtual.whitespace" = {
          fg = c.muted;
        };
        "ui.virtual.indent-guide" = {
          fg = c.surface;
        };

        comment = {
          fg = c.muted;
        };
        keyword = {
          fg = c.primary;
        };
        "keyword.directive" = {
          fg = c.accent;
        };
        string = {
          fg = c.success;
        };
        function = {
          fg = c.accent;
        };
        variable = {
          fg = c.foreground;
        };
        constant = {
          fg = c.accentAlt;
        };
        "constant.numeric" = {
          fg = c.accentAlt;
        };
        type = {
          fg = c.accentAlt;
        };
        operator = {
          fg = c.muted;
        };
        punctuation = {
          fg = c.muted;
        };
        "markup.heading" = {
          fg = c.primary;
          modifiers = [ "bold" ];
        };
        "markup.link" = {
          fg = c.accent;
          modifiers = [ "underline" ];
        };
      };
    };

    # ---- Yazi ----
    #
    # The chrome only: the cursor row, tabs, mode badges, the status bar and the
    # which-key strip. File icons keep their own colours — they are a picture of
    # file types, and recolouring them from a palette makes them harder to read,
    # not more consistent.
    yazi.theme = {
      mgr = {
        cwd = {
          fg = c.primary;
        };
        border_style = {
          fg = c.surface;
        };
        marker_selected = {
          fg = c.accent;
          bg = c.accent;
        };
        marker_copied = {
          fg = c.success;
          bg = c.success;
        };
        marker_cut = {
          fg = c.danger;
          bg = c.danger;
        };
        count_selected = {
          fg = c.background;
          bg = c.accent;
        };
        count_copied = {
          fg = c.background;
          bg = c.success;
        };
        count_cut = {
          fg = c.background;
          bg = c.danger;
        };
      };

      tabs = {
        active = {
          fg = c.background;
          bg = c.primary;
        };
        inactive = {
          fg = c.muted;
          bg = c.surface;
        };
      };

      mode = {
        normal_main = {
          fg = c.background;
          bg = c.primary;
        };
        normal_alt = {
          fg = c.primary;
          bg = c.surface;
        };
        select_main = {
          fg = c.background;
          bg = c.accent;
        };
        select_alt = {
          fg = c.accent;
          bg = c.surface;
        };
        unset_main = {
          fg = c.background;
          bg = c.danger;
        };
        unset_alt = {
          fg = c.danger;
          bg = c.surface;
        };
      };

      status = {
        perm_sep = {
          fg = c.muted;
        };
        progress_normal = {
          fg = c.success;
          bg = c.surface;
        };
        progress_error = {
          fg = c.danger;
          bg = c.surface;
        };
      };

      which = {
        border = {
          fg = c.primary;
        };
        cand = {
          fg = c.accent;
        };
        rest = {
          fg = c.muted;
        };
        desc = {
          fg = c.muted;
        };
        separator_style = {
          fg = c.surface;
        };
      };

      confirm = {
        border = {
          fg = c.primary;
        };
        title = {
          fg = c.primary;
        };
      };

      notify = {
        title_info = {
          fg = c.success;
        };
        title_warn = {
          fg = c.accentAlt;
        };
        title_error = {
          fg = c.danger;
        };
      };

      pick = {
        border = {
          fg = c.primary;
        };
        active = {
          fg = c.accent;
        };
      };

      input = {
        border = {
          fg = c.primary;
        };
        selected = {
          reversed = true;
        };
      };

      cmp = {
        border = {
          fg = c.primary;
        };
        active = {
          reversed = true;
        };
      };

      tasks = {
        border = {
          fg = c.primary;
        };
        hovered = {
          fg = c.accent;
        };
      };

      help = {
        border = {
          fg = c.primary;
        };
        chord = {
          fg = c.accent;
        };
      };

      spot = {
        border = {
          fg = c.primary;
        };
        title = {
          fg = c.primary;
        };
      };
    };

    # ---- btop ----
    #
    # btop only ships its own theme names, so `color_theme` names one that is
    # generated. The file itself is written by theme-apps on every switch — at
    # ~/.config/btop/themes/anixie.theme, which is the only place btop looks — so
    # btop follows the palette at its next start rather than the next rebuild.
    btop = {
      enable = true;
      settings.color_theme = "anixie";
    };

    # ---- tmux ----
    #
    # There was no tmux configuration at all before this: the colours are the whole
    # of it, since tmux is used by habit and the keys are not the theme's business.
    tmux = {
      enable = true;

      # The colours are not here: theme-apps rewrites them on every switch, and
      # this config only says where to find them. `-q` so a server that starts
      # before the first `theme apply` has no error to report.
      extraConfig = "source-file -q ${config.my.theme.stateDir}/tmux.conf";
    };

    # ---- the lock screen ----
    #
    # Colours and the clock, not a redesign: a lock screen has to be readable and
    # get out of the way. The wallpaper is the screenshot behind it, blurred, with
    # the palette's background tinted over it so text has something to sit on.
    hyprlock = {
      # The Home Manager module owns the config file; the NixOS one (modules/system/
      # lock.nix) owns the PAM service. Without `enable` here the settings below are
      # accepted and then never written.
      enable = true;

      settings = {
        background = [
          {
            monitor = "";
            path = "screenshot";
            blur_passes = 3;
            blur_size = 8;
            color = render "@BG_RGBA_F2@";
          }
        ];

        input-field = [
          {
            monitor = "";
            size = "320, 52";
            outline_thickness = 2;
            rounding = 0;
            outer_color = render "@BG_RGBA_FF@";
            inner_color = render "@SURFACE_RGBA_FF@";
            font_color = render "@FG_RGBA_FF@";
            dots_size = 0.25;
            dots_spacing = 0.4;
            fade_on_empty = false;
            placeholder_text = "";
            check_color = render "@SUCCESS_RGBA_FF@";
            fail_color = render "@DANGER_RGBA_FF@";
            capslock_color = render "@ACCENT_ALT_RGBA_FF@";
          }
        ];

        label = [
          {
            monitor = "";
            text = "$TIME";
            color = render "@FG_RGBA_FF@";
            font_family = "JetBrainsMono Nerd Font";
            font_size = 72;
            position = "0, 120";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = ''cmd[update:60000] date +"%A, %d %B"'';
            color = render "@MUTED_RGBA_FF@";
            font_family = "JetBrainsMono Nerd Font";
            font_size = 18;
            position = "0, 60";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
