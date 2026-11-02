{ pkgs, ... }:

{
  home.pointerCursor = {
    enable = true;

    name = "macOS";
    package = pkgs.apple-cursor;
    size = 24;

    gtk.enable = true;
    x11.enable = true;
  };
}
