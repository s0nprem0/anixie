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
  options.anixie.applications.media = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install mpv, the media player.";
    };

    obs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install OBS Studio for screen recording and streaming.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.mpv ] ++ lib.optionals cfg.obs [ pkgs.obs-studio ];
  };
}
