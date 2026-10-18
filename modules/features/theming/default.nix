{ config, pkgs, ... }:

let
  # Where the live choice and the files the apps read live. A state directory, not
  # ~/.config: Home Manager owns those paths as read-only store symlinks, and a
  # theme set at runtime has to be able to write.
  stateDir = config.my.theme.stateDir;

  theme = pkgs.writeShellScriptBin "theme" (
    builtins.replaceStrings
      [
        "@PALETTES@"
        "@STATE_DIR@"
        "@DEFAULT_THEME@"
        "@QUICKSHELL@"
        "@HYPRCTL@"
        "@JQ@"
      ]
      [
        "${./themes.json}"
        stateDir
        config.my.theme.theme
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.jq}/bin/jq"
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

  home.packages = [ theme ];

  # The palette file's own path, as a template placeholder, so a config that has
  # to read the palettes at runtime — the Hyprland borders do — can point at it
  # without a second copy of the path.
  my.theme.template.placeholders."@PALETTES@" = "${./themes.json}";

  # The runtime files are written at login as well as on a switch, because a fresh
  # boot has the state directory but not the files inside it — the include in the
  # kitty config would point at nothing, and the launcher would come up unthemed
  # until the first `theme set`.
  home.file."${stateDir}/.keep".text = "";

  systemd.user.services.anixie-theme-apply = {
    Unit.Description = "Apply the saved theme";
    Unit.PartOf = [ "graphical-session.target" ];
    Service = {
      Type = "oneshot";
      ExecStart = "${theme}/bin/theme apply";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
