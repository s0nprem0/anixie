{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.clipboard;

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
  options.my.wm.clipboard.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the clipboard picker over cliphist.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ clipboard ];
  };
}
