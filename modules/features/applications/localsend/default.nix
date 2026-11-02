{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.localsend;
in
{
  options.anixie.applications.localsend.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install LocalSend for local file transfers.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.localsend ];
  };
}
