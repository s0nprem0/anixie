{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.files;
in
{
  options.anixie.applications.files.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Thunar as the file manager and default directory handler.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.thunar ];

    # kitty and yazi both claim folders in their desktop entries, and with no
    # default the winner is whichever entry happens to be read first — a
    # terminal, for a "show in folder" clicked in a browser. Yazi is still a
    # keystroke away as `y`.
    xdg.mimeApps = {
      enable = true;
      defaultApplications."inode/directory" = "thunar.desktop";
    };
  };
}
