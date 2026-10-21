{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.applications.browser;
in
{
  options.my.applications.browser.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Chromium and Firefox, with Firefox as the default browser.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      chromium
      firefox
    ];

    # Firefox wrote these itself while ~/.config/mimeapps.list was still its own
    # to write. Home Manager owns that file now and a browser cannot change a
    # read-only link, so the defaults it set have to be stated here or they go.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = builtins.listToAttrs (
        map
          (type: {
            name = type;
            value = "firefox.desktop";
          })
          [
            "x-scheme-handler/http"
            "x-scheme-handler/https"
            "x-scheme-handler/chrome"
            "text/html"
            "application/xhtml+xml"
            "application/x-extension-htm"
            "application/x-extension-html"
            "application/x-extension-shtml"
            "application/x-extension-xhtml"
            "application/x-extension-xht"
          ]
      );
    };
  };
}
