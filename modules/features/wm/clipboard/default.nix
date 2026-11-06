{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:

let
  cfg = config.anixie.wm.clipboard;
  # The watcher is native in alexie now (`alexie clipboard watch`); the
  # compositor starts it by absolute path, so it does not need a name on
  # PATH. The placeholder carries the subcommand, which app-launch
  # forwards as arguments.
  alexiePkg = inputs.alexie.packages.${pkgs.stdenv.hostPlatform.system}.default;
in

{
  options.anixie.wm.clipboard.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the clipboard popup over cliphist.";
  };

  config = lib.mkIf cfg.enable {
    anixie.theme.template.placeholders."@CLIPBOARD_WATCH@" = "${alexiePkg}/bin/alexie clipboard watch";
  };
}
