{ config, pkgs, ... }:

let
  dark = config.my.theme.mode == "dark";
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
    # writes the config below without installing anything to read it.
    platformTheme = {
      name = "qt6ct";
      package = pkgs.qt6Packages.qt6ct;
    };

    # Built from the palette this machine starts on. A runtime light switch
    # changes the icons through gsettings, but Qt keeps this file until the next
    # rebuild.
    qt6ctSettings = {
      Appearance = {
        icon_theme = if dark then "Papirus-Dark" else "Papirus-Light";
        style = if dark then "adwaita-dark" else "adwaita";
      };
    };
  };
}
