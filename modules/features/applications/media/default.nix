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
    home.packages = [
      pkgs.mpv
    ]
    ++ lib.optionals cfg.obs [
      (pkgs.wrapOBS {
        plugins = with pkgs.obs-studio-plugins; [ distroav ];
      })
    ];

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "video/mp4" = "mpv.desktop";
        "video/x-m4v" = "mpv.desktop";
        "video/quicktime" = "mpv.desktop";
        "video/x-matroska" = "mpv.desktop";
        "video/webm" = "mpv.desktop";
        "video/x-msvideo" = "mpv.desktop";
        "video/avi" = "mpv.desktop";
        "video/vnd.avi" = "mpv.desktop";
        "video/mpeg" = "mpv.desktop";
        "video/mp2t" = "mpv.desktop";
        "video/3gpp" = "mpv.desktop";
        "video/ogg" = "mpv.desktop";
        "video/x-flv" = "mpv.desktop";
        "video/x-ms-wmv" = "mpv.desktop";
        "application/mxf" = "mpv.desktop";
        "video/dv" = "mpv.desktop";
        "application/x-shockwave-flash" = "mpv.desktop";
      };
    };
  };
}
