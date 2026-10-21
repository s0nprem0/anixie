{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.applications.media;
in
{
  options.my.applications.media.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install mpv, the media player.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.mpv ];
  };
}
