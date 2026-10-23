{
  config,
  lib,
  pkgs,
  ...
}:

let
  dark = config.anixie.theme.mode == "dark";
  stateDir = config.anixie.theme.stateDir;
  render = config.anixie.theme.template.render;
  defaultSettings = pkgs.writeText "anixie-gtk-settings.ini" (render ./templates/gtk-settings.ini);
in
{
  anixie.theme.template.placeholders = {
    "@GTK_THEME@" = if dark then "Adwaita-dark" else "Adwaita";
    "@GTK_ICON@" = if dark then "Papirus-Dark" else "Papirus-Light";
    "@GTK_DARK@" = if dark then "1" else "0";
    "@CURSOR_THEME@" = config.home.pointerCursor.name;
    "@CURSOR_SIZE@" = toString config.home.pointerCursor.size;
  };

  gtk = {
    enable = true;

    theme = {
      name = if dark then "Adwaita-dark" else "Adwaita";
      package = pkgs.gnome-themes-extra;
    };

    iconTheme = {
      name = if dark then "Papirus-Dark" else "Papirus-Light";
      package = pkgs.papirus-icon-theme;
    };

    font = {
      name = "JetBrains Mono";
      size = 10;
    };
  };

  # GTK3 reads settings.ini directly on Wayland, and GTK4/libadwaita uses the
  # same values plus the gsettings colour scheme. Keeping the files in the state
  # directory lets a theme switch rewrite them without a rebuild.
  xdg.configFile = {
    "gtk-3.0/settings.ini" = lib.mkForce {
      source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/gtk-3.0-settings.ini";
    };
    "gtk-4.0/settings.ini" = lib.mkForce {
      source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/gtk-4.0-settings.ini";
    };
  };

  home.activation.anixieGtkSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state=${lib.escapeShellArg stateDir}
    mkdir -p "$state"
    [ -f "$state/gtk-3.0-settings.ini" ] ||
      install -m 644 ${defaultSettings} "$state/gtk-3.0-settings.ini"
    [ -f "$state/gtk-4.0-settings.ini" ] ||
      install -m 644 ${defaultSettings} "$state/gtk-4.0-settings.ini"
  '';
}
