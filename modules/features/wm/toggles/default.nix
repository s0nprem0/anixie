{ pkgs, ... }:

let
  # The modes the bar's indicators show, as one command. The keys call it, the
  # indicator polls it, and the picker lists it — one answer to "is it on".
  toggle = pkgs.writeShellScriptBin "toggle" (
    builtins.replaceStrings
      [
        "@HYPRCTL@"
        "@QUICKSHELL@"
        "@FUZZEL@"
      ]
      [
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.fuzzel}/bin/fuzzel"
      ]
      (builtins.readFile ./toggle.sh)
  );
in
{
  home.packages = [ toggle ];
}
