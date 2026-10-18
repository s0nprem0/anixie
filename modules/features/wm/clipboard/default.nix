{
  pkgs,
  ...
}:

let
  # cliphist keeps the history and is fed by the compositor's clipboard watchers
  # (see hyprland/default.nix); this is only the picking of one entry back out.
  clipboard = pkgs.writeShellScriptBin "clipboard" (
    builtins.replaceStrings
      [
        "@CLIPHIST@"
        "@WL_COPY@"
      ]
      [
        "${pkgs.cliphist}/bin/cliphist"
        "${pkgs.wl-clipboard}/bin/wl-copy"
      ]
      (builtins.readFile ./clipboard.sh)
  );
in

{
  home.packages = [ clipboard ];
}