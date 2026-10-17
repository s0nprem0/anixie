{ pkgs, ... }:

{
  # Tools that ship configuration get their own directory under features/shell/
  # instead, so this stays limited to bare binaries.
  home.packages = import ./packages.nix { inherit pkgs; };
}
