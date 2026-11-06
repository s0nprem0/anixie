{
  config,
  lib,
  pkgs,
  ...
}:

let
  state = "${config.xdg.stateHome}/anixie/screentime";

  daemonEnabled = config.anixie.daemon.enable or false;
  screentime = pkgs.writeShellScriptBin "screentime" (
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
  home.packages = lib.optionals (!daemonEnabled) [ screentime ];
}
