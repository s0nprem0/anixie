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

  iconTheme = if dark then "Papirus-Dark" else "Papirus-Light";

  # The build-time palette, used until theme-apps rewrites the same files for a
  # live theme.
  defaultColors = pkgs.writeText "anixie-qt6ct-colors.conf" (render ./templates/qt6ct-colors.conf);
in
{
  qt = {
    enable = true;

    # Qt resolves a themed icon through QIcon::fromTheme, which has to be told
    # which theme to search. With no platform theme set, Qt searches only
    # hicolor, where Papirus's icons are not — which is why the bar's tray module
    # drew nothing. qt6ct supplies the theme name and palette.
    #
    # The package has to be named: it defaults to null, and Home Manager then
    # writes no config for anything to read.
    platformTheme = {
      name = "qt6ct";
      package = pkgs.qt6Packages.qt6ct;
    };
  };

  # qt6ct's config and palette live in the state directory and are linked into
  # ~/.config, so the theme command can rewrite them for a light or dark switch.
  # `qt6ctSettings` is deliberately unused: Home Manager would write a read-only
  # store symlink in the same place.
  xdg.configFile."qt6ct/qt6ct.conf".source =
    config.lib.file.mkOutOfStoreSymlink "${stateDir}/qt6ct.conf";

  # Seed them before the first theme apply, so an application started early in
  # the session still has a palette to read. Subsequent switches rewrite them.
  home.activation.anixieQt6ct = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state=${lib.escapeShellArg stateDir}
    mkdir -p "$state"
    [ -f "$state/qt6ct-colors.conf" ] ||
      install -m 644 ${defaultColors} "$state/qt6ct-colors.conf"
    if [ ! -f "$state/qt6ct.conf" ]; then
      printf '%s\n' \
        '[Appearance]' \
        "color_scheme_path=$state/qt6ct-colors.conf" \
        'custom_palette=true' \
        'icon_theme=${iconTheme}' \
        'style=Fusion' \
        >"$state/qt6ct.conf"
    fi
  '';
}
