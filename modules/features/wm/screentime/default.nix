{ config, pkgs, ... }:

let
  state = "${config.xdg.stateHome}/anixie/screentime";

  daemonEnabled = config.anixie.daemon.enable or false;
  screentime =
    pkgs.writeShellScriptBin (if daemonEnabled then "screentime-legacy" else "screentime")
      (
        builtins.replaceStrings
          [ "@STATE@" "@JQ@" "@QUICKSHELL@" ]
          [
            state
            "${pkgs.jq}/bin/jq"
            "${pkgs.quickshell}/bin/quickshell"
          ]
          (builtins.readFile ./screentime.sh)
      );
in
{
  home.packages = [
    screentime
  ];
}
