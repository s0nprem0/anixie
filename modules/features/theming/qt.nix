{
  config,
  lib,
  pkgs,
  ...
}:

let
  stateDir = config.anixie.theme.stateDir;
  kvantum = config.anixie.theme.kvantum.enable;
in
{
  options.anixie.theme.kvantum.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Use Kvantum for Qt styles; off by default because qt6ct already supplies the palette.";
  };

  config = {
    home.packages = [
      pkgs.libsForQt5.qt5ct
    ]
    ++ lib.optionals kvantum [
      pkgs.qt6Packages.qtstyleplugin-kvantum
      pkgs.libsForQt5.qtstyleplugin-kvantum
    ];

    home.sessionVariables = lib.mkIf kvantum {
      QT_STYLE_OVERRIDE = "kvantum";
    };

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
    # store symlink in the same place. Qt5ct and Kvantum are optional: Qt5ct has
    # its own palette file, and Kvantum is only used when the option above is on.
    xdg.configFile = {
      "qt6ct/qt6ct.conf".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/qt6ct.conf";
      "qt5ct/qt5ct.conf".source = config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/qt5ct.conf";
      "Kvantum/kvantum.kvconfig".source =
        config.lib.file.mkOutOfStoreSymlink "${stateDir}/live/kvantum.kvconfig";
    };
  };
}
