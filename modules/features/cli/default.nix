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

    # The bar is QML inside the shell, but patching a widget or moving it from a
    # script should not have to spell out `quickshell ipc call bar`. This also
    # gives `anixie bar --help` a manual of its own rather than ipc's.
    (pkgs.writeShellScriptBin "bar" (
      builtins.replaceStrings
        [ "@ANIXIE_LIB@" "@QUICKSHELL@" ]
        [ "${./lib.sh}" "${pkgs.quickshell}/bin/quickshell" ]
        (builtins.readFile ./bar.sh)
    ))

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
