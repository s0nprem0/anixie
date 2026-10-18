{ pkgs, ... }:

{
  home.packages = [ pkgs.thunar ];

  # kitty and yazi both claim folders in their desktop entries, and with no
  # default the winner is whichever entry happens to be read first — a
  # terminal, for a "show in folder" clicked in a browser. Yazi is still a
  # keystroke away as `y`.
  xdg.mimeApps = {
    enable = true;
    defaultApplications."inode/directory" = "thunar.desktop";
  };
}
