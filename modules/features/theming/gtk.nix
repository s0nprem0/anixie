{ config, pkgs, ... }:

let
  dark = config.my.theme.mode == "dark";
in
{
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
}
