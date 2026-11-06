{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.menu;
  daemonEnabled = config.anixie.daemon.enable or false;
in
{
  options.anixie.wm.menu.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the menu command, which reads quickshell/menu.json.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.optionals (!daemonEnabled) [
      (pkgs.writeShellScriptBin "menu" (
        builtins.replaceStrings
          [ "@QUICKSHELL@" "@ANIXIE_LIB@" ]
          [ "${pkgs.quickshell}/bin/quickshell" "${../../cli/lib.sh}" ]
          (builtins.readFile ./menu.sh)
      ))
    ];
  };
}
