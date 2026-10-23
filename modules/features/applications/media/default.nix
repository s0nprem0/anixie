{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.media;
in
{
  options.anixie.applications.media.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install mpv, the media player.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.mpv ];
  };
}
