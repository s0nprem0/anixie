{
  config,
  pkgs,
  ...
}:

let
  stateDir = config.anixie.theme.stateDir;
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
    config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/qt6ct.conf";
}
