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
  stateDir = config.my.theme.stateDir;

  # The generated desktop wallpaper and its dimensions. A gradient rather than an
  # image file, so every palette carries its own without shipping pictures. The
  # shell draws stills on its background layer; videos still go through awww,
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
        "@AWWW@"
        "@AWWW_DAEMON@"
        "@PGREP@"
        "@PKILL@"
        "@QUICKSHELL@"
        "@WIDTH@"
        "@HEIGHT@"
      ]
      [
        stateDir
        "${config.xdg.dataHome}/anixie"
        "${./themes.json}"
        config.my.theme.theme
        "${pkgs.jq}/bin/jq"
        "${pkgs.imagemagick}/bin/magick"
        "${pkgs.awww}/bin/awww"
        "${pkgs.awww}/bin/awww-daemon"
        "${pkgs.procps}/bin/pgrep"
        "${pkgs.procps}/bin/pkill"
        "${pkgs.quickshell}/bin/quickshell"
        "1920"
        "1080"
      ]
      (builtins.readFile ./wallpaper.sh)
  );

  # The global text-size knob. Writes the kitty include and the shell's state
  # file, and tells GTK and the running shell through their own controls.
  textsize = pkgs.writeShellScriptBin "textsize" (
    builtins.replaceStrings
      [ "@STATE_DIR@" "@GSETTINGS@" "@GSETTINGS_SCHEMA_DIR@" "@QUICKSHELL@" ]
      [
        stateDir
        "${pkgs.glib}/bin/gsettings"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
        "${pkgs.quickshell}/bin/quickshell"
      ]
      (builtins.readFile ./textsize.sh)
  );

  # The theme files for the applications that are not the shell, the compositor
  # or kitty. Separate from `theme` because it runs on every switch and only the
  # applications it names should pay for it.
  themeApps = pkgs.writeShellScriptBin "theme-apps" (
    builtins.replaceStrings
      [
        "@PALETTES@"
        "@STATE_DIR@"
        "@JQ@"
        "@TMUX@"
        "@HELIX_TEMPLATE@"
        "@YAZI_TEMPLATE@"
        "@HYPRLOCK_TEMPLATE@"
        "@QT6CT_COLORS_TEMPLATE@"
        "@GTK_TEMPLATE@"
        "@POINTER_CURSOR_THEME@"
        "@POINTER_CURSOR_SIZE@"
      ]
      [
        "${./themes.json}"
        stateDir
        "${pkgs.jq}/bin/jq"
        "${pkgs.tmux}/bin/tmux"
        "${./templates/helix.toml}"
        "${./templates/yazi.toml}"
        "${./templates/hyprlock.conf}"
        "${./templates/qt6ct-colors.conf}"
        "${./templates/gtk-settings.ini}"
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
        "@MATUGEN@"
        "@MAGICK@"
        "@FFMPEG@"
        "@SHA256SUM@"
        "@STAT@"
        "@GENERATED@"
        "@ANIXIE_LIB@"
      ]
      [
        "${./themes.json}"
        stateDir
        config.my.theme.theme
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.glib}/bin/gsettings"
        "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}/glib-2.0/schemas"
        "${pkgs.jq}/bin/jq"
        "${wallpaper}/bin/wallpaper"
        "${themeApps}/bin/theme-apps"
        "${pkgs.matugen}/bin/matugen"
        "${pkgs.imagemagick}/bin/magick"
        "${pkgs.ffmpeg}/bin/ffmpeg"
        "${pkgs.coreutils}/bin/sha256sum"
        "${pkgs.coreutils}/bin/stat"
        "${stateDir}/palette.json"
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./theme.sh)
  );
in
{
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

  # The palette file's own path, as a template placeholder, so a config that has
  # to read the palettes at runtime — the Hyprland borders do — can point at it
  # without a second copy of the path.
  my.theme.template.placeholders."@PALETTES@" = "${./themes.json}";

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
        printf '%s\n' ${lib.escapeShellArg config.my.theme.mode} >"$state/mode"
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
  };
}
