{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.anixie.daemon;
  alexiePkg = inputs.alexie.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.anixie.daemon.enable = lib.mkEnableOption "alexie Rust daemon + CLI";

  config = lib.mkIf cfg.enable {
    home.packages = [
      alexiePkg
      (pkgs.writeShellScriptBin "monitors" ''
        exec ${alexiePkg}/bin/alexie monitors "$@"
      '')
      (pkgs.writeShellScriptBin "menu" ''
        exec ${alexiePkg}/bin/alexie menu "$@"
      '')
      (pkgs.writeShellScriptBin "theme" ''
        exec ${alexiePkg}/bin/alexie theme "$@"
      '')
      (pkgs.writeShellScriptBin "wallpaper" ''
        exec ${alexiePkg}/bin/alexie wallpaper "$@"
      '')
      (pkgs.writeShellScriptBin "shot" ''
        exec ${alexiePkg}/bin/alexie shot "$@"
      '')
      (pkgs.writeShellScriptBin "record" ''
        exec ${alexiePkg}/bin/alexie record "$@"
      '')
      (pkgs.writeShellScriptBin "transcode" ''
        exec ${alexiePkg}/bin/alexie transcode "$@"
      '')
      (pkgs.writeShellScriptBin "capture-text" ''
        exec ${alexiePkg}/bin/alexie capture-text "$@"
      '')
      (pkgs.writeShellScriptBin "capture-qr" ''
        exec ${alexiePkg}/bin/alexie capture-qr "$@"
      '')
      (pkgs.writeShellScriptBin "capture-share" ''
        exec ${alexiePkg}/bin/alexie capture-share "$@"
      '')
      (pkgs.writeShellScriptBin "webcam-overlay" ''
        exec ${alexiePkg}/bin/alexie webcam-overlay "$@"
      '')
      (pkgs.writeShellScriptBin "clipboard" ''
        exec ${alexiePkg}/bin/alexie clipboard "$@"
      '')
      (pkgs.writeShellScriptBin "emoji" ''
        exec ${alexiePkg}/bin/alexie emoji "$@"
      '')
      (pkgs.writeShellScriptBin "focus" ''
        exec ${alexiePkg}/bin/alexie focus "$@"
      '')
      (pkgs.writeShellScriptBin "screentime" ''
        exec ${alexiePkg}/bin/alexie screentime "$@"
      '')
      (pkgs.writeShellScriptBin "toggle" ''
        exec ${alexiePkg}/bin/alexie toggle "$@"
      '')
      (pkgs.writeShellScriptBin "webapp" ''
        exec ${alexiePkg}/bin/alexie webapp "$@"
      '')
      (pkgs.writeShellScriptBin "snapshot" ''
        exec ${alexiePkg}/bin/alexie snapshot "$@"
      '')
    ];

    systemd.user.services.alexie = {
      Unit = {
        Description = "alexie daemon";
        After = [ config.wayland.systemd.target ];
        PartOf = [ config.wayland.systemd.target ];
      };
      Service = {
        Type = "exec";
        ExecStart = "${alexiePkg}/bin/alexie daemon";
        Restart = "on-failure";
        RestartSec = "2s";
      };
      Install = {
        WantedBy = [ config.wayland.systemd.target ];
      };
    };
  };
}
