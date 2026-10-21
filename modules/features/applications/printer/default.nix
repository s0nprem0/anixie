{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.applications.printer;
in
{
  options.my.applications.printer.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install cups-filters and simple-scan for printing and scanning.";
  };

  config = lib.mkIf cfg.enable {
    # cups-filters lives here rather than modules/system/printing.nix because
    # home.packages is a Home Manager option, not a NixOS one.
    home.packages = with pkgs; [
      cups-filters
      simple-scan
    ];
  };
}
