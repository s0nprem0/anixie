{
  pkgs,
  config,
  host,
  flakeDir,
  ...
}:

{
  # The front door. Everything it dispatches to is installed elsewhere in
  # features/; this only names them in one place.
  home.packages = [
    (pkgs.writeShellScriptBin "anixie" (builtins.readFile ./anixie.sh))

    # Rebuild, shared by `anixie update` and the nrs/nrb/nrt aliases so the
    # nh flags live in one place.
    (pkgs.writeShellScriptBin "rebuild" (
      builtins.replaceStrings
        [ "@ANIXIE_LIB@" "@FLAKE@" "@HOST@" ]
        [
          "${./lib.sh}"
          "${config.home.homeDirectory}/${flakeDir}"
          host
        ]
        (builtins.readFile ./rebuild.sh)
    ))
  ];
}
