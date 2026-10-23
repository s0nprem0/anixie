{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.bluetooth;
in
{
  options.anixie.wm.bluetooth.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install blueman, the Bluetooth manager applet.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.blueman ];
  };
}
