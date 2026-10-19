{ config, pkgs, ... }:

let
  # Where the live choice and the files the apps read live. A state directory, not
  # ~/.config: Home Manager owns those paths as read-only store symlinks, and a
  # theme set at runtime has to be able to write.
  stateDir = config.my.theme.stateDir;

  # The generated desktop wallpaper and its dimensions. A gradient rather than an
  # image file, so every palette carries its own without shipping pictures.
  wallpaper = pkgs.writeShellScriptBin "wallpaper" (
    builtins.replaceStrings
      [
        "@STATE_DIR@"
        "@PALETTES@"
        "@DEFAULT_THEME@"
        "@JQ@"
        "@MAGICK@"
        "@AWWW@"
        "@AWWW_DAEMON@"
        "@WIDTH@"
        "@HEIGHT@"
      ]
      [
        stateDir
        "${./themes.json}"
        config.my.theme.theme
        "${pkgs.jq}/bin/jq"
        "${pkgs.imagemagick}/bin/magick"
        "${pkgs.awww}/bin/awww"
        "${pkgs.awww}/bin/awww-daemon"
        "1920"
        "1080"
      ]
      (builtins.readFile ./wallpaper.sh)
  );

  # The global text-size knob. Writes the kitty include and the shell's state
  # file, and tells GTK and the running shell through their own controls.
  textsize = pkgs.writeShellScriptBin "textsize" (
    builtins.replaceStrings
      [ "@STATE_DIR@" "@GSETTINGS@" "@QUICKSHELL@" ]
      [
        stateDir
        "${pkgs.glib}/bin/gsettings"
        "${pkgs.quickshell}/bin/quickshell"
      ]
      (builtins.readFile ./textsize.sh)
  );

  theme = pkgs.writeShellScriptBin "theme" (
    builtins.replaceStrings
      [
        "@PALETTES@"
        "@STATE_DIR@"
        "@DEFAULT_THEME@"
        "@QUICKSHELL@"
        "@HYPRCTL@"
        "@JQ@"
        "@WALLPAPER@"
      ]
      [
        "${./themes.json}"
        stateDir
        config.my.theme.theme
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.jq}/bin/jq"
        "${wallpaper}/bin/wallpaper"
      ]
      (builtins.readFile ./theme.sh)
  );
in
{
  imports = [
    ./colors.nix
    ./template.nix
    ./cursor.nix
    ./fonts.nix
    ./gtk.nix
    ./qt.nix
  ];

  home.packages = [
    theme
    wallpaper
    textsize
  ];

  # The palette file's own path, as a template placeholder, so a config that has
  # to read the palettes at runtime — the Hyprland borders do — can point at it
  # without a second copy of the path.
  my.theme.template.placeholders."@PALETTES@" = "${./themes.json}";

  # The runtime files are written at login as well as on a switch, because a fresh
  # boot has the state directory but not the files inside it — the include in the
  # kitty config would point at nothing, and the launcher would come up unthemed
  # until the first `theme set`.
  #
  # The text-size files get defaults here too, for the same reason: both are
  # included by configs that would otherwise fail to load on a fresh login.
  home.file = {
    "${stateDir}/.keep".text = "";
    "${stateDir}/kitty-font.conf".text = "font_size 11\n";
    "${stateDir}/textscale".text = "100\n";
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
