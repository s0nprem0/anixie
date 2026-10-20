{ config, pkgs, ... }:

let
  state = "${config.xdg.stateHome}/anixie/powerprofile";

  powerprofile = pkgs.writeShellScriptBin "powerprofile" (
    builtins.replaceStrings
      [ "@STATE@" "@PPD@" "@UDEV@" "@ANIXIE_LIB@" ]
      [
        state
        "${pkgs.power-profiles-daemon}/bin/powerprofilesctl"
        "${pkgs.systemd}/bin/udevadm"
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./powerprofile.sh)
  );
in
{
  home.packages = [ powerprofile ];

  # Applies the stored profile at login and on every plug or unplug. A service
  # rather than a login hook so it keeps working after the cable moves, which is
  # the whole point.
  systemd.user.services.anixie-powerprofile = {
    Unit = {
      Description = "Apply the power profile for the current power source";
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${powerprofile}/bin/powerprofile watch";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
