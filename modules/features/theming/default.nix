{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:

let
  # Where the live choice and the files the apps read live. A state directory, not
  # ~/.config: Home Manager owns those paths as read-only store symlinks, and a
  # theme set at runtime has to be able to write.
  stateDir = config.anixie.theme.stateDir;
  # `theme` and `wallpaper` themselves are native in alexie now (both
  # bash versions are gone), so the login services call the binary
  # directly rather than a legacy package.
  alexiePkg = inputs.alexie.packages.${pkgs.stdenv.hostPlatform.system}.default;
  appearance = pkgs.writeShellScriptBin "appearance" (
    builtins.replaceStrings [ "@QUICKSHELL@" ] [ "${pkgs.quickshell}/bin/quickshell" ] (
      builtins.readFile ./appearance.sh
    )
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

  # Template bundle for alexie's native renderer (see
  # `alexie/src/theme/assets.rs` manifest). Assembled as a flat
  # link-farm matching the manifest filenames, including the
  # share-picker style under its subpath.
  themeTemplates = pkgs.linkFarm "anixie-theme-templates" [
    {
      name = "helix.toml";
      path = ./templates/helix.toml;
    }
    {
      name = "yazi.toml";
      path = ./templates/yazi.toml;
    }
    {
      name = "hyprlock.conf";
      path = ./templates/hyprlock.conf;
    }
    {
      name = "qt6ct-colors.conf";
      path = ./templates/qt6ct-colors.conf;
    }
    {
      name = "gtk-settings.ini";
      path = ./templates/gtk-settings.ini;
    }
    {
      name = "gtk-3.0.css";
      path = ./templates/gtk-3.0.css;
    }
    {
      name = "gtk-4.0.css";
      path = ./templates/gtk-4.0.css;
    }
    {
      name = "share-picker/style.css";
      path = ../wm/share-picker/style.css;
    }
    {
      name = "discord.css";
      path = ./templates/discord.css;
    }
    {
      name = "alacritty.toml";
      path = ./templates/alacritty.toml;
    }
    {
      name = "ghostty";
      path = ./templates/ghostty;
    }
    {
      name = "foot.ini";
      path = ./templates/foot.ini;
    }
    {
      name = "vscode.json";
      path = ./templates/vscode.json;
    }
    {
      name = "obsidian.css";
      path = ./templates/obsidian.css;
    }
    {
      name = "librewolf-userChrome.css";
      path = ./templates/librewolf-userChrome.css;
    }
    {
      name = "librewolf-userContent.css";
      path = ./templates/librewolf-userContent.css;
    }
    {
      name = "mpv.conf";
      path = ./templates/mpv.conf;
    }
    {
      name = "zathurarc";
      path = ./templates/zathurarc;
    }
    {
      name = "eza-theme.yml";
      path = ./templates/eza-theme.yml;
    }
    {
      name = "opencode-theme.json";
      path = ./templates/opencode-theme.json;
    }
  ];

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
        "@DISCORD_TEMPLATE@"
        "@ALACRITTY_TEMPLATE@"
        "@GHOSTTY_TEMPLATE@"
        "@FOOT_TEMPLATE@"
        "@VSCODE_TEMPLATE@"
        "@OBSIDIAN_TEMPLATE@"
        "@LIBREWOLF_USERCHROME_TEMPLATE@"
        "@LIBREWOLF_USERCONTENT_TEMPLATE@"
        "@MPV_TEMPLATE@"
        "@ZATHURA_TEMPLATE@"
        "@EZA_TEMPLATE@"
        "@OPENCODE_TEMPLATE@"
        "@PAPIRUS_FOLDERS@"
        "@TOKENS@"
        "@RENDER_LIB@"
        "@COLOR_LIB@"
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
        "${./templates/discord.css}"
        "${./templates/alacritty.toml}"
        "${./templates/ghostty}"
        "${./templates/foot.ini}"
        "${./templates/vscode.json}"
        "${./templates/obsidian.css}"
        "${./templates/librewolf-userChrome.css}"
        "${./templates/librewolf-userContent.css}"
        "${./templates/mpv.conf}"
        "${./templates/zathurarc}"
        "${./templates/eza-theme.yml}"
        "${./templates/opencode-theme.json}"
        "${pkgs.papirus-folders}/bin/papirus-folders"
        "${./tokens.json}"
        "${./lib/render.sh}"
        "${./lib/color.sh}"
        "${pkgs.gnused}/bin/sed"
        config.home.pointerCursor.name
        (toString config.home.pointerCursor.size)
      ]
      (builtins.readFile ./theme-apps.sh)
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

    extraDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Folders scanned after `dirs`, for pictures that ship with a host.";
    };

    default = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      example = "~/Pictures/Wallpapers/forest.jpg";
      description = ''
        Picture used when neither the current theme nor an output has a
        wallpaper choice. Accepts a path in the flake, an absolute path or one
        starting with `~/`. Leave null to use the gradient generated from the
        palette. A runtime choice (`wallpaper use`) still overrides it.
      '';
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

    xdg.configFile."alexie/config.toml".text = ''
      [theme]
      templates_dir = "${themeTemplates}"
      tokens_json = "${./tokens.json}"
      palettes_json = "${./themes.json}"
    '';

    home = {
      packages = [
        appearance
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
          ${alexiePkg}/bin/alexie theme apply >/dev/null 2>&1 || true
        fi
      '';
    };

    systemd.user.services = {
      anixie-theme-apply = {
        Unit.Description = "Apply the saved theme";
        Unit.PartOf = [ "graphical-session.target" ];
        Service = {
          Type = "oneshot";
          ExecStart = "${alexiePkg}/bin/alexie theme apply";
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
          ExecStart = "${alexiePkg}/bin/alexie wallpaper next${
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
          ExecStart = "${alexiePkg}/bin/alexie theme auto";
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
