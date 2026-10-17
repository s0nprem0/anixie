{ pkgs, ... }:

{
  # cups-filters lives here rather than modules/system/printing.nix because
  # home.packages is a Home Manager option, not a NixOS one.
  home.packages = with pkgs; [
    cups-filters
    simple-scan
  ];
}
