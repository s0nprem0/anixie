{
  nixpkgs,
  system ? "x86_64-linux",
  ...
}:

let
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };
in
pkgs.mkShell {
  name = "nix-dots-dev";

  packages = with pkgs; [
    deadnix
    nil
    nixfmt
    statix
  ];
}
