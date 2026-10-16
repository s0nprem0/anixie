{ pkgs, ... }:

{
  imports = [
    ../../configuration.nix
  ];

  programs.hyprland.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
    ];
  };
}
