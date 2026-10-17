{ pkgs, ... }:

{
  home.pointerCursor = {
    enable = true;

    name = "Bibata-Modern-Classic";
    package = pkgs.bibata-cursors;

    gtk.enable = true;
    x11.enable = true;
  };
}
