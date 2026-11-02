{ config, pkgs, ... }:

let
  state = "${config.xdg.stateHome}/anixie/screentime";

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
  home.packages = [
    screentime
    pkgs.jq
  ];
}
