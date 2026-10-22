# hypridle is kept only as the pre-suspend guard now (see hypridle.conf); the
# idle timers and the lock live in the shell. The daemon itself is enabled in
# modules/system/lock.nix.
{ pkgs, ... }:

{
  xdg.configFile."hypr/hypridle.conf".text =
    builtins.replaceStrings [ "@QUICKSHELL@" ] [ "${pkgs.quickshell}/bin/quickshell" ]
      (builtins.readFile ./hypridle.conf);
}
