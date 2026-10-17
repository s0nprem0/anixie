{ pkgs, ... }:

pkgs.mkShell {
  name = "nix-dots-dev";

  packages = with pkgs; [
    deadnix
    nil
    nixfmt
    statix
  ];
}
