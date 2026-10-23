{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.clipboard;

  # cliphist keeps the history and is fed by the compositor's clipboard watchers
  # (see hyprland/config/70-startup.lua); this is only the picking of one entry
  # back out.
  clipboard = pkgs.writeShellScriptBin "clipboard" (
    builtins.replaceStrings
      [
        "@CLIPHIST@"
        "@WL_COPY@"
        "@FILE@"
      ]
      [
        "${pkgs.cliphist}/bin/cliphist"
        "${pkgs.wl-clipboard}/bin/wl-copy"
        "${pkgs.file}/bin/file"
      ]
      (builtins.readFile ./clipboard.sh)
  );

  # Kept separate from the picker because it is started once at session start
  # and outlives every invocation of `clipboard`.
  clipboardWatch = pkgs.writeShellScriptBin "clipboard-watch" (
    builtins.replaceStrings
      [
        "@CLIPHIST@"
        "@WL_PASTE@"
      ]
      [
        "${pkgs.cliphist}/bin/cliphist"
        "${pkgs.wl-clipboard}/bin/wl-paste"
      ]
      (builtins.readFile ./clipboard-watch.sh)
  );
in

{
  options.anixie.wm.clipboard.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the clipboard picker over cliphist.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      clipboard
      clipboardWatch
    ];
  };
}
