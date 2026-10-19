{ pkgs, ... }:

{
  # zathura reads a PDF; xournalpp is the one that fills in the form or signs it,
  # which is the thing a PDF in a laptop's downloads folder usually wants.
  home.packages = [
    pkgs.zathura
    pkgs.xournalpp
  ];
}
