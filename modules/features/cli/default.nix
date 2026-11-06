{
  config,
  lib,
  pkgs,
  host,
  flakeDir,
  inputs,
  ...
}:

let
  # The bar is QML inside the desktop shell. A host that does not import the wm
  # profile (WSL) has nothing for it to talk to, so it does not get the command
  # or its Quickshell dependency.
  desktop = (config.anixie or { }) ? wm;
in
{
  # The front door. Everything it dispatches to is installed elsewhere in
  # features/; this only names them in one place. Now a Rust binary from the
  # alexie flake, replacing the bash dispatcher.
  home.packages = [
    inputs.alexie.packages.${pkgs.system}.anixie
  ]
  ++ lib.optionals desktop [
    # The bar is QML inside the shell, but patching a widget or moving it from a
    # script should not have to spell out `quickshell ipc call bar`. This also
    # gives `anixie bar --help` a manual of its own rather than ipc's.
    (pkgs.writeShellScriptBin "bar" (
      builtins.replaceStrings
        [ "@ANIXIE_LIB@" "@QUICKSHELL@" ]
        [ "${./lib.sh}" "${pkgs.quickshell}/bin/quickshell" ]
        (builtins.readFile ./bar.sh)
    ))
  ]
  ++ [
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
