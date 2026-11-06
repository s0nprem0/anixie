{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.media;

  # OBS with the NDI output plugin. Built once and reused by the wrapper below.
  obsWrapped = pkgs.wrapOBS {
    plugins = with pkgs.obs-studio-plugins; [ distroav ];
  };
in
{
  options.anixie.applications.media = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install mpv, the media player.";
    };

    vlc = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install VLC, themed to follow the anixie palette.";
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
      pkgs.imv
    ]
    ++ lib.optionals cfg.vlc [
      (pkgs.runCommand "vlc-themed" { } ''
        mkdir -p $out/bin
        cat > $out/bin/vlc <<'EOF'
        #!/bin/sh
        # VLC is a Qt5 application; qt5ct is the platform theme that reads the
        # anixie palette. Force it here so the desktop entry and any caller that
        # bypasses the session environment still get the themed window.
        export QT_QPA_PLATFORMTHEME=qt5ct
        # VLC only flips to its dark variant on request, so follow the live mode
        # instead of leaving it on the (light) default.
        if [ "$(tr -d '[:space:]' < ${config.anixie.theme.stateDir}/mode 2>/dev/null)" = "dark" ]; then
          exec ${pkgs.vlc}/bin/vlc --qt-dark-palette "$@"
        else
          exec ${pkgs.vlc}/bin/vlc "$@"
        fi
        EOF
        chmod +x $out/bin/vlc
        # Keep the store desktop file's icon/theme data reachable.
        if [ -d ${pkgs.vlc}/share ]; then
          ln -s ${pkgs.vlc}/share $out/share
        fi
      '')
    ]
    ++ lib.optionals cfg.obs [
      (pkgs.runCommand "obs-studio-ndi" { } ''
        mkdir -p $out/bin
        # Launch OBS under nice/ionice so its CPU and disk priority stay above
        # background work, which is what removes the periodic scheduling
        # hiccups during a recording.
        cat > $out/bin/obs <<'EOF'
        #!/bin/sh
        export NDILIB_REDIST_FOLDER=${pkgs.ndi-6}/lib
        export LD_LIBRARY_PATH=${pkgs.ndi-6}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
        exec ${pkgs.coreutils}/bin/nice -n -10 ${pkgs.util-linux}/bin/ionice -c2 -n0 ${obsWrapped}/bin/obs "$@"
        EOF
        chmod +x $out/bin/obs
        ln -s ${obsWrapped}/share $out/share 2>/dev/null || true
      '')
    ];

    xdg.desktopEntries = lib.mkIf cfg.vlc {
      vlc = {
        name = "VLC media player";
        genericName = "Media player";
        exec = "vlc %U";
        icon = "vlc";
        terminal = false;
        categories = [ "AudioVideo" "Player" "Video" ];
        mimeType = [ "video/*" "audio/*" ];
      };
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        # Images: mpv handles stills too, so xdg-open on a picture is not a dead end.
        "image/png" = "imv.desktop";
        "image/jpeg" = "imv.desktop";
        "image/jpg" = "imv.desktop";
        "image/gif" = "imv.desktop";
        "image/webp" = "imv.desktop";
        "image/bmp" = "imv.desktop";
        "image/tiff" = "imv.desktop";
        "image/svg+xml" = "imv.desktop";
        "image/avif" = "imv.desktop";
        "image/heic" = "imv.desktop";
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
