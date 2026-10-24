{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.clipboard;

  mkScript = import ../../cli/scripts.nix { inherit pkgs; };

  # cliphist keeps the history and is fed by the compositor's clipboard watchers
  # (see hyprland/config/70-startup.lua); this is only the picking of one entry
  # back out.
  clipboard = mkScript {
    name = "clipboard";
    file = ./clipboard.sh;
    bins = {
      "@CLIPHIST@" = "${pkgs.cliphist}/bin/cliphist";
      "@WL_COPY@" = "${pkgs.wl-clipboard}/bin/wl-copy";
      "@FILE@" = "${pkgs.file}/bin/file";
      "@ANIXIE_LIB@" = "${../../cli/lib.sh}";
    };
  };

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
    description = "Whether to install the clipboard picker over cliphist.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ clipboard.package ];

    # The watcher is a long-running helper, not a command. Handing its path to
    # the compositor keeps it out of the user's PATH.
    anixie.theme.template.placeholders."@CLIPBOARD_WATCH@" = clipboardWatch.command;
  };
}
