{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.webapps;
in
{
  options.my.wm.webapps.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the webapp command, which turns a website into a Chromium --app desktop entry.";
  };

  config = lib.mkIf cfg.enable {
    # A website as an application. Chromium is the implementation because `--app`
    # is the thing that actually removes the browser chrome; Firefox has no
    # equivalent without an extension.
    home.packages = [
      (pkgs.writeShellScriptBin "webapp" (
        builtins.replaceStrings
          [ "@APPS@" "@BROWSER@" "@UPDATE_DB@" "@ANIXIE_LIB@" ]
          [
            "${config.xdg.dataHome}/applications"
            "${pkgs.chromium}/bin/chromium"
            "${pkgs.desktop-file-utils}/bin/update-desktop-database"
            "${../../cli/lib.sh}"
          ]
          (builtins.readFile ./webapp.sh)
      ))
    ];
  };
}
