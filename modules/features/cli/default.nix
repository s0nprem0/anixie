{ pkgs, ... }:

{
  # The front door. Everything it dispatches to is installed elsewhere in
  # features/; this only names them in one place.
  home.packages = [
    (pkgs.writeShellScriptBin "anixie" (builtins.readFile ./anixie.sh))
  ];
}
