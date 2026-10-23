{
  config,
  lib,
  pkgs,
  ...
}:

let
  # One palette, every app. Each of these is read when its program starts, so a
  # theme switched at runtime reaches the shell, Hyprland and kitty at once and
  # the rest at their next start — see theme.sh, which is honest about it.
  render = config.my.theme.template.render;
  light = config.my.theme.mode == "light";
  stateDir = config.my.theme.stateDir;

  # The same templates the runtime renderer uses, already rendered with the
  # palette this machine is built from. Activation writes one to the state
  # directory if it is not there yet.
  defaultHelix = pkgs.writeText "anixie-helix.toml" (render ./templates/helix.toml);
  defaultYazi = pkgs.writeText "anixie-yazi.toml" (render ./templates/yazi.toml);
  defaultHyprlock = pkgs.writeText "anixie-hyprlock.conf" (render ./templates/hyprlock.conf);
in
{
  my.theme.template.placeholders."@HELIX_PARENT@" =
    if light then "base16_default_light" else "base16_default_dark";

  # Helix, Yazi and hyprlock read these files. They live in the state directory
  # and are linked into ~/.config, so theme-apps can rewrite them on a switch
  # instead of waiting for the next build.
  xdg.configFile = {
    "helix/themes/anixie.toml".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/helix.toml";
    "yazi/theme.toml".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/yazi.toml";
    "hypr/hyprlock.conf".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/hyprlock.conf";
  };

  home.activation.anixieAppThemes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state=${lib.escapeShellArg stateDir}
    mkdir -p "$state"
    [ -f "$state/helix.toml" ] || install -m 644 ${defaultHelix} "$state/helix.toml"
    [ -f "$state/yazi.toml" ] || install -m 644 ${defaultYazi} "$state/yazi.toml"
    [ -f "$state/hyprlock.conf" ] || install -m 644 ${defaultHyprlock} "$state/hyprlock.conf"
  '';

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
      # The NixOS module (modules/system/lock.nix) owns the PAM service. The
      # config is written by theme-apps and linked in above.
      enable = true;
    };
  };
}
