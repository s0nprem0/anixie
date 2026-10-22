{
  config,
  lib,
  pkgs,
  ...
}:

let
  dark = config.my.theme.mode == "dark";
  stateDir = config.my.theme.stateDir;

  iconTheme = if dark then "Papirus-Dark" else "Papirus-Light";
  style = if dark then "adwaita-dark" else "adwaita";
in
{
  qt = {
    enable = true;

    # Qt resolves a themed icon through QIcon::fromTheme, which has to be told
    # which theme to search. With no platform theme set, Qt searches only
    # hicolor, where Papirus's icons are not — which is why the bar's tray module
    # drew nothing. qt6ct supplies the theme name.
    #
    # The package has to be named: it defaults to null, and Home Manager then
    # writes no config for anything to read.
    platformTheme = {
      name = "qt6ct";
      package = pkgs.qt6Packages.qt6ct;
    };
  };

  # qt6ct's config is materialised in the state directory and linked into
  # ~/.config, so the theme command can rewrite it for a light or dark switch.
  # `qt6ctSettings` is deliberately unused: Home Manager would write a read-only
  # store symlink in the same place.
  xdg.configFile."qt6ct/qt6ct.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${stateDir}/qt6ct.conf";

  # Seed it before the first theme apply, so an application started early in the
  # session still has a config to read. Subsequent switches rewrite the file.
  home.activation.anixieQt6ct = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state=${lib.escapeShellArg stateDir}
    if [ ! -f "$state/qt6ct.conf" ]; then
      mkdir -p "$state"
      printf '%s\n' '[Appearance]' 'icon_theme=${iconTheme}' 'style=${style}' \
        >"$state/qt6ct.conf"
    fi
  '';
}
