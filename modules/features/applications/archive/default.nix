{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.archive;
in
{
  options.anixie.applications.archive.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install file-roller, the archive manager.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.file-roller ];
  };
}
