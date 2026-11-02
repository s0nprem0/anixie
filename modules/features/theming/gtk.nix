{
  config,
  lib,
  pkgs,
  ...
}:

let
  dark = config.anixie.theme.mode == "dark";
  stateDir = config.anixie.theme.stateDir;
in
{
  anixie.theme.template.placeholders = {
    "@GTK_THEME@" = if dark then "adw-gtk3-dark" else "adw-gtk3";
    "@GTK_ICON@" = if dark then "Papirus-Dark" else "Papirus-Light";
    "@GTK_DARK@" = if dark then "1" else "0";
    "@CURSOR_THEME@" = config.home.pointerCursor.name;
    "@CURSOR_SIZE@" = toString config.home.pointerCursor.size;
  };

  gtk = {
    enable = true;

    theme = {
      name = if dark then "adw-gtk3-dark" else "adw-gtk3";
      package = pkgs.adw-gtk3;
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

  home.packages = [ pkgs.papirus-folders ];

  # GTK3 reads settings.ini directly on Wayland, and GTK4/libadwaita uses the
  # same values plus the gsettings colour scheme. Keeping the files in the state
  # directory lets a theme switch rewrite them without a rebuild.
  xdg.configFile = {
    "gtk-3.0/settings.ini" = lib.mkForce {
      source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/gtk-3.0-settings.ini";
    };
    "gtk-4.0/settings.ini" = lib.mkForce {
      source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/gtk-4.0-settings.ini";
    };
    "gtk-3.0/gtk.css" = lib.mkForce {
      source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/gtk-3.0.css";
    };
    "gtk-4.0/gtk.css" = lib.mkForce {
      source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/gtk-4.0.css";
    };
  };

  # papirus-folders rewrites symlinks inside the theme, so it needs a writable
  # tree rather than the read-only store path. Copy the theme preserving its
  # relative symlinks: dereferencing them (`cp -L`) turned a 262M tree into 1.6G
  # and made the copy take half a minute. `--no-preserve=mode` makes the copy
  # writable in the first place, so there is nothing to chmod afterwards.
  #
  # The copy is versioned by the store path it came from. A marker from an older
  # generation (or an old dereferenced copy) is rebuilt once, and a Papirus
  # update replaces the tree instead of leaving it stale forever. On btrfs/xfs
  # `--reflink=auto` makes that rebuild a metadata-only copy.
  home.activation.anixiePapirusFolders = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    icons=${lib.escapeShellArg "${config.xdg.dataHome}/icons"}
    src=${lib.escapeShellArg "${pkgs.papirus-icon-theme}/share/icons"}
    marker="$icons/.papirus-source"
    mkdir -p "$icons"

    if [ "$(cat "$marker" 2>/dev/null || true)" != "$src" ]; then
      for theme in Papirus Papirus-Dark Papirus-Light; do
        if [ -d "$icons/$theme" ]; then
          rm -rf "$icons/$theme"
        fi
        cp -r --reflink=auto --no-preserve=mode "$src/$theme" "$icons/$theme" || exit 1
      done
      printf '%s\n' "$src" >"$marker"
    else
      for theme in Papirus Papirus-Dark Papirus-Light; do
        if [ ! -d "$icons/$theme" ]; then
          cp -r --reflink=auto --no-preserve=mode "$src/$theme" "$icons/$theme" || exit 1
        fi
      done
    fi
  '';
}
