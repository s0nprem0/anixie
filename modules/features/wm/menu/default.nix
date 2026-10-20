{
  pkgs,
  ...
}:

{
  # The menu, as a command. The menu itself lives in the shell — its tree is
  # quickshell/menu.json and its keys are global shortcuts — so this is only the
  # way in for scripts: `menu --list` to read it, `menu firefox` to launch
  # something without asking.
  home.packages = [
    (pkgs.writeShellScriptBin "menu" (
      builtins.replaceStrings
        [ "@QUICKSHELL@" "@ANIXIE_LIB@" ]
        [ "${pkgs.quickshell}/bin/quickshell" "${../../cli/lib.sh}" ]
        (
        builtins.readFile ./menu.sh
      )
    ))
  ];
}
