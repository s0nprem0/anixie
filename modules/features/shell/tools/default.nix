{ config, pkgs, ... }:

{
  # Tools that ship configuration get their own directory under features/shell/
  # instead, so this stays limited to bare binaries.
  home.packages = import ./packages.nix { inherit pkgs; };

  # nh reads this as the default flake for `nh os switch` and friends, so the
  # rebuild aliases work from any directory rather than only from the repo.
  home.sessionVariables.NH_FLAKE = "${config.home.homeDirectory}/nix-dots";
}
