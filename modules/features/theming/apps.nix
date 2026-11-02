{
  config,
  ...
}:

let
  # One palette, every app. Each of these is read when its program starts, so a
  # theme switched at runtime reaches the shell, Hyprland and kitty at once and
  # the rest at their next start — see theme.sh, which is honest about it.
  light = config.anixie.theme.mode == "light";
  stateDir = config.anixie.theme.stateDir;
in
{
  anixie.theme.template.placeholders."@HELIX_PARENT@" =
    if light then "base16_default_light" else "base16_default_dark";

  # Helix, Yazi and hyprlock read these files. They live in the state directory
  # and are linked into ~/.config, so theme-apps can rewrite them on a switch
  # instead of waiting for the next build.
  xdg.configFile = {
    "helix/themes/anixie.toml".source =
      config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/helix.toml";
    "yazi/theme.toml".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/yazi.toml";
    "hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/hyprlock.conf";
    "btop/themes/anixie.theme".source =
      config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/btop.theme";
  };

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
    };

    # ---- Yazi ----
    #
    # Its theme.toml is written by theme-apps from templates/yazi.toml and linked
    # in by the module above, so it follows a runtime switch at the next start.

    # ---- btop ----
    #
    # btop only ships its own theme names, so `color_theme` names one that is
    # generated. The file is written into each generation and linked at
    # ~/.config/btop/themes/anixie.theme, the only place btop looks, so btop
    # follows the palette at its next start rather than the next rebuild.
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
      extraConfig = "source-file -q ${config.anixie.theme.stateDir}/live/tmux.conf";
    };

    # ---- the lock screen ----
    #
    # Colours and the clock, not a redesign: a lock screen has to be readable and
    # get out of the way. The wallpaper is the screenshot behind it, blurred, with
    # the palette's background tinted over it so text has something to sit on.
    hyprlock = {
      # The NixOS module (modules/system/lock.nix) owns the PAM service. The
      # config is written by theme-apps and linked in above.
      enable = true;
    };
  };
}
