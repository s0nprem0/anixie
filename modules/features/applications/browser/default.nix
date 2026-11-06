{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.browser;

  # Force-installed extensions via browser policies. AMO "latest" URLs resolve to
  # the current version; installation is performed by the browser on profile use.
  extensionSettings = {
    "uBlock0@raymondhill.net" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
      installation_mode = "force_installed";
    };
    "{3c078156-979c-498b-8990-85f7987dd929}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/sidebery/latest.xpi";
      installation_mode = "force_installed";
    };
    "FirefoxColor@mozilla.com" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/firefox-color/latest.xpi";
      installation_mode = "force_installed";
    };
    "addon@darkreader.org" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
      installation_mode = "force_installed";
    };
    "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}" = {
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/styl-us/latest.xpi";
      installation_mode = "force_installed";
    };
  };
in
{
  options.anixie.applications.browser.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install Chromium and LibreWolf (with managed extensions), with LibreWolf as the default browser.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.chromium ];

    programs.librewolf = {
      enable = true;
      policies.ExtensionSettings = extensionSettings;
    };

    # LibreWolf/Firefox would write these itself while ~/.config/mimeapps.list was
    # still its own to write. Home Manager owns that file now and a browser cannot
    # change a read-only link, so the defaults have to be stated here or they go.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = builtins.listToAttrs (
        map
          (type: {
            name = type;
            value = "librewolf.desktop";
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
