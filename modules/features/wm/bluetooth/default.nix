{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.bluetooth;
in
{
  options.my.wm.bluetooth.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install blueman, the Bluetooth manager applet.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.blueman ];
  };
}
