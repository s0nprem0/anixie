{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Where the live choice and the files the apps read live. A state directory, not
  # ~/.config: Home Manager owns those paths as read-only store symlinks, and a
  # theme set at runtime has to be able to write.
  stateDir = config.anixie.theme.stateDir;
  wallpaperDirs = lib.escapeShellArg (lib.concatStringsSep "\n" config.anixie.theme.wallpaper.dirs);
  wallpaperRecursive = if config.anixie.theme.wallpaper.recursive then "true" else "false";

  # The generated desktop wallpaper and its dimensions. A gradient rather than an
  # image file, so every palette carries its own without shipping pictures. The
  # shell draws stills on its background layer; videos go through mpvpaper,
  # because the shell has no video renderer yet. This command picks the owner and
  # tells a running shell what to show.
  wallpaper = pkgs.writeShellScriptBin "wallpaper" (
    builtins.replaceStrings
      [
        "@STATE_DIR@"
        "@DATA_DIR@"
        "@PALETTES@"
        "@DEFAULT_THEME@"
        "@JQ@"
        "@MAGICK@"
        "@FFMPEG@"
        "@MPVPAPER@"
        "@HYPRCTL@"
        "@PGREP@"
        "@PKILL@"
        "@QUICKSHELL@"
        "@WIDTH@"
        "@HEIGHT@"
        "@WALLPAPER_DIRS@"
        "@WALLPAPER_RECURSIVE@"
        "@SHA256SUM@"
        "@STAT@"
        "@ANIXIE_LIB@"
      ]
      [
        stateDir
        "${config.xdg.dataHome}/anixie"
        "${./themes.json}"
        config.anixie.theme.theme
        "${pkgs.jq}/bin/jq"
        "${pkgs.imagemagick}/bin/magick"
        "${pkgs.ffmpeg}/bin/ffmpeg"
        "${pkgs.mpvpaper}/bin/mpvpaper"
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.procps}/bin/pgrep"
        "${pkgs.procps}/bin/pkill"
        "${pkgs.quickshell}/bin/quickshell"
        "1920"
        "1080"
        wallpaperDirs
        wallpaperRecursive
        "${pkgs.coreutils}/bin/sha256sum"
        "${pkgs.coreutils}/bin/stat"
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./wallpaper.sh)
  );

  # The global text-size knob. Writes the kitty include and the shell's state
  # file, and tells GTK and the running shell through their own controls.
  textsize = pkgs.writeShellScriptBin "textsize" (
    builtins.replaceStrings
      [
        "@STATE_DIR@"
        "@GSETTINGS@"
        "@GSETTINGS_SCHEMA_DIR@"
        "@QUICKSHELL@"
        "@ANIXIE_LIB@"
      ]
      [
        stateDir
        "${pkgs.glib}/bin/gsettings"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
        "${pkgs.quickshell}/bin/quickshell"
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./textsize.sh)
  );

  # The theme files for the applications that are not the shell, the compositor
  # or kitty. Separate from `theme` because it runs on every switch and only the
  # applications it names should pay for it.
  themeApps = pkgs.writeShellScriptBin "theme-apps" (
    builtins.replaceStrings
      [
        "@STATE_DIR@"
        "@JQ@"
        "@HELIX_TEMPLATE@"
        "@YAZI_TEMPLATE@"
        "@HYPRLOCK_TEMPLATE@"
        "@QT6CT_COLORS_TEMPLATE@"
        "@GTK_TEMPLATE@"
        "@GTK3_CSS_TEMPLATE@"
        "@GTK4_CSS_TEMPLATE@"
        "@SHARE_PICKER_TEMPLATE@"
        "@TOKENS@"
        "@RENDER_LIB@"
        "@SED@"
        "@POINTER_CURSOR_THEME@"
        "@POINTER_CURSOR_SIZE@"
      ]
      [
        stateDir
        "${pkgs.jq}/bin/jq"
        "${./templates/helix.toml}"
        "${./templates/yazi.toml}"
        "${./templates/hyprlock.conf}"
        "${./templates/qt6ct-colors.conf}"
        "${./templates/gtk-settings.ini}"
        "${./templates/gtk-3.0.css}"
        "${./templates/gtk-4.0.css}"
        "${../wm/share-picker/style.css}"
        "${./tokens.json}"
        "${./lib/render.sh}"
        "${pkgs.gnused}/bin/sed"
        config.home.pointerCursor.name
        (toString config.home.pointerCursor.size)
      ]
      (builtins.readFile ./theme-apps.sh)
  );

  theme = pkgs.writeShellScriptBin "theme" (
    builtins.replaceStrings
      [
        "@PALETTES@"
        "@STATE_DIR@"
        "@DEFAULT_THEME@"
        "@QUICKSHELL@"
        "@HYPRCTL@"
        "@GSETTINGS@"
        "@GSETTINGS_SCHEMA_DIR@"
        "@JQ@"
        "@WALLPAPER@"
        "@THEME_APPS@"
        "@AUTO_LIGHT@"
        "@AUTO_DARK@"
        "@AUTO_SCHEDULE@"
        "@MATUGEN@"
        "@TMUX@"
        "@MAGICK@"
        "@FFMPEG@"
        "@SHA256SUM@"
        "@STAT@"
        "@GENERATED@"
        "@PALETTE_JQ@"
        "@COLOR_LIB@"
        "@STATE_LIB@"
        "@FLOCK@"
        "@ANIXIE_LIB@"
      ]
      [
        "${./themes.json}"
        stateDir
        config.anixie.theme.theme
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.glib}/bin/gsettings"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
        "${pkgs.jq}/bin/jq"
        "${wallpaper}/bin/wallpaper"
        "${themeApps}/bin/theme-apps"
        (lib.escapeShellArg config.anixie.theme.auto.schedule.light)
        (lib.escapeShellArg config.anixie.theme.auto.schedule.dark)
        (if config.anixie.theme.auto.schedule.enable then "true" else "false")
        "${pkgs.matugen}/bin/matugen"
        "${pkgs.tmux}/bin/tmux"
        "${pkgs.imagemagick}/bin/magick"
        "${pkgs.ffmpeg}/bin/ffmpeg"
        "${pkgs.coreutils}/bin/sha256sum"
        "${pkgs.coreutils}/bin/stat"
        "${stateDir}/palette.json"
        "${./palette.jq}"
        "${./lib/color.sh}"
        "${./lib/state.sh}"
        "${pkgs.util-linux}/bin/flock"
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./theme.sh)
  );
in
{
  options.anixie.theme.wallpaper = {
    dirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "${config.home.homeDirectory}/Pictures/Wallpapers"
        "${config.home.homeDirectory}/Pictures"
        "${config.xdg.dataHome}/anixie/backgrounds"
      ];
      description = "Folders scanned by the wallpaper library.";
    };

    recursive = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the wallpaper library scans folders recursively.";
    };
  };

  options.anixie.theme.auto = {
    schedule = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Switch between paired light and dark palettes on a schedule.";
      };
      light = lib.mkOption {
        type = lib.types.str;
        default = "07:00";
        description = "When the light palette starts (HH:MM).";
      };
      dark = lib.mkOption {
        type = lib.types.str;
        default = "19:00";
        description = "When the dark palette starts (HH:MM).";
      };
    };

    rotation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Rotate through the wallpaper library on a timer.";
      };
      interval = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "Interval between automatic wallpaper changes.";
      };
      shuffle = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Pick a random wallpaper instead of the next one.";
      };
    };
  };

  imports = [
    ./colors.nix
    ./template.nix
    ./apps.nix
    ./matugen.nix
    ./cursor.nix
    ./fonts.nix
    ./gtk.nix
    ./qt.nix
  ];

  config = {
    # The palette file's own path, as a template placeholder, so a config that has
    # to read the palettes at runtime — the Hyprland borders do — can point at it
    # without a second copy of the path.
    anixie.theme.template.placeholders."@PALETTES@" = "${./themes.json}";

    home = {
      packages = [
        theme
        wallpaper
        textsize
      ];

      # The runtime files are written at login as well as on a switch, because a
      # fresh boot has the state directory but not the files inside it — the include
      # in the kitty config would point at nothing, and the launcher would come up
      # unthemed until the first `theme set`.
      file."${stateDir}/.keep".text = "";

      # kitty's include and the shell's text-size file have to be writable: the
      # textsize command rewrites them, and a home.file entry would be a read-only
      # store symlink. Seed them from activation instead, replacing a link left by
      # an older generation. `mode` and `palette.json` are left to the theme
      # service for the same reason.
      activation.anixieThemeState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        state=${lib.escapeShellArg stateDir}
        mkdir -p "$state"
        for file in kitty-font.conf mode textscale; do
          if [ -L "$state/$file" ]; then
            value=$(cat "$state/$file" 2>/dev/null || true)
            rm -f "$state/$file"
            if [ -n "$value" ]; then printf '%s\n' "$value" >"$state/$file"; fi
          fi
        done
        if [ ! -f "$state/kitty-font.conf" ]; then
          printf 'font_size 11\n' >"$state/kitty-font.conf"
        fi
        if [ ! -f "$state/textscale" ]; then
          printf '100\n' >"$state/textscale"
        fi
        if [ ! -f "$state/mode" ]; then
          printf '%s\n' ${lib.escapeShellArg config.anixie.theme.mode} >"$state/mode"
        fi

        if [ ! -f "$state/live/palette.json" ]; then
          ${theme}/bin/theme apply >/dev/null 2>&1 || true
        fi
      '';
    };

    systemd.user.services = {
      anixie-theme-apply = {
        Unit.Description = "Apply the saved theme";
        Unit.PartOf = [ "graphical-session.target" ];
        Service = {
          Type = "oneshot";
          ExecStart = "${theme}/bin/theme apply";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      # The text size is materialised separately from the theme so the two do not
      # have to know about each other, but both run at login.
      anixie-textsize-apply = {
        Unit = {
          Description = "Apply the saved text size";
          PartOf = [ "graphical-session.target" ];
          After = [ "anixie-theme-apply.service" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${textsize}/bin/textsize apply";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      anixie-wallpaper-rotate = lib.mkIf config.anixie.theme.auto.rotation.enable {
        Unit.Description = "Rotate the wallpaper";
        Service = {
          Type = "oneshot";
          ExecStart = "${wallpaper}/bin/wallpaper next${
            if config.anixie.theme.auto.rotation.shuffle then " --random" else ""
          }";
        };
      };

      anixie-theme-auto = lib.mkIf config.anixie.theme.auto.schedule.enable {
        Unit = {
          Description = "Apply the light or dark palette for this time of day";
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${theme}/bin/theme auto";
        };
      };
    };

    systemd.user.timers = {
      anixie-wallpaper-rotate = lib.mkIf config.anixie.theme.auto.rotation.enable {
        Unit.Description = "Rotate the wallpaper periodically";
        Timer = {
          OnBootSec = "5min";
          OnUnitActiveSec = config.anixie.theme.auto.rotation.interval;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };

      anixie-theme-auto = lib.mkIf config.anixie.theme.auto.schedule.enable {
        Unit.Description = "Check the light/dark schedule";
        Timer = {
          OnCalendar = "*:0/15";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    };
  };
}
