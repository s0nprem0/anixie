{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.anixie.daemon;
  alexiePkg = inputs.alexie.packages.${pkgs.system}.default;
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
