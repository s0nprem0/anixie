{
  pkgs,
  config,
  ...
}:

{
  # A website as an application. Chromium is the implementation because `--app`
  # is the thing that actually removes the browser chrome; Firefox has no
  # equivalent without an extension.
  home.packages = [
    (pkgs.writeShellScriptBin "webapp" (
      builtins.replaceStrings
        [ "@APPS@" "@BROWSER@" "@UPDATE_DB@" ]
        [
          "${config.xdg.dataHome}/applications"
          "${pkgs.chromium}/bin/chromium"
          "${pkgs.desktop-file-utils}/bin/update-desktop-database"
        ]
        (builtins.readFile ./webapp.sh)
    ))
  ];
}
