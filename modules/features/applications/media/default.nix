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
      (pkgs.runCommand "obs-studio-ndi"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
          propagatedBuildInputs = [
            (pkgs.wrapOBS {
              plugins = with pkgs.obs-studio-plugins; [ distroav ];
            })
          ];
        }
        ''
          mkdir -p $out/bin
          makeWrapper ${
            pkgs.wrapOBS { plugins = with pkgs.obs-studio-plugins; [ distroav ]; }
          }/bin/obs $out/bin/obs \
            --set NDILIB_REDIST_FOLDER ${pkgs.ndi-6}/lib \
            --prefix LD_LIBRARY_PATH : ${pkgs.ndi-6}/lib
          ln -s ${
            pkgs.wrapOBS { plugins = with pkgs.obs-studio-plugins; [ distroav ]; }
          }/share $out/share 2>/dev/null || true
        ''
      )
    ];

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        # Images: mpv handles stills too, so xdg-open on a picture is not a dead end.
        "image/png" = "mpv.desktop";
        "image/jpeg" = "mpv.desktop";
        "image/jpg" = "mpv.desktop";
        "image/gif" = "mpv.desktop";
        "image/webp" = "mpv.desktop";
        "image/bmp" = "mpv.desktop";
        "image/tiff" = "mpv.desktop";
        "image/svg+xml" = "mpv.desktop";
        "image/avif" = "mpv.desktop";
        "image/heic" = "mpv.desktop";
        # Audio
        "audio/mpeg" = "mpv.desktop";
        "audio/mp3" = "mpv.desktop";
        "audio/flac" = "mpv.desktop";
        "audio/ogg" = "mpv.desktop";
        "audio/wav" = "mpv.desktop";
        "audio/x-wav" = "mpv.desktop";
        "audio/aac" = "mpv.desktop";
        "audio/mp4" = "mpv.desktop";
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
