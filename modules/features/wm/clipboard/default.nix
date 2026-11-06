{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.clipboard;

  mkScript = import ../../cli/scripts.nix { inherit pkgs; };

  # Kept separate from the picker because it is started once at session start
  # and outlives every invocation of `clipboard`. The compositor starts it by
  # absolute path, so it does not need a name on PATH.
  clipboardWatch = mkScript {
    name = "clipboard-watch";
    file = ./clipboard-watch.sh;
    bins = {
      "@CLIPHIST@" = "${pkgs.cliphist}/bin/cliphist";
      "@WL_PASTE@" = "${pkgs.wl-clipboard}/bin/wl-paste";
    };
  };
in

{
  options.anixie.wm.clipboard.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the clipboard popup over cliphist.";
  };

  config = lib.mkIf cfg.enable {
    # The watcher is a long-running helper, not a command. Handing its path to
    # the compositor keeps it out of the user's PATH.
    anixie.theme.template.placeholders."@CLIPBOARD_WATCH@" = clipboardWatch.command;
  };
}
