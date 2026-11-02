{ config, pkgs, ... }:

let
  state = "/run/anixie/performance";

  tune = pkgs.writeShellScriptBin "performance-tune" (
    builtins.replaceStrings
      [ "@STATE@" "@PPD@" "@BUSCTL@" "@SYSCTL@" "@SED@" "@STDBUF@" ]
      [
        state
        "${pkgs.power-profiles-daemon}/bin/powerprofilesctl"
        "${config.systemd.package}/bin/busctl"
        "${pkgs.procps}/bin/sysctl"
        "${pkgs.gnused}/bin/sed"
        "${pkgs.coreutils}/bin/stdbuf"
      ]
      (builtins.readFile ./performance.sh)
  );
in
{
  # power-profiles-daemon has no hook for "the profile changed, now tune the
  # rest of the machine", so this service watches its D-Bus object instead. The
  # script itself explains which knobs it moves and why they are put back.
  systemd.services.anixie-performance-tune = {
    description = "Apply the extras for the performance power profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig = {
      ExecStart = "${tune}/bin/performance-tune watch";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
