{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.browser;

  # Optional autoconfig injection so anixie-bridge.js actually runs and
  # LibreWolf chrome can recolor without a restart. Off by default: it
  # rewrites the LibreWolf install tree and a bad autoconfig file can
  # prevent the browser from launching.
  librewolfPkg = pkgs.librewolf;
  anixieLibrewolf = pkgs.runCommand "librewolf-anixie" { } ''
    set -eu
    mkdir -p "$out"
    cp -a ${librewolfPkg}/. "$out"/
    chmod -R u+w "$out"
    mkdir -p "$out/lib/librewolf/defaults/pref"
    cat > "$out/lib/librewolf/defaults/pref/anixie-autoconfig.js" <<'EOF'
    pref("general.config.filename", "anixie.cfg");
    pref("general.config.obscure_value", 0);
    EOF
    cat > "$out/lib/librewolf/anixie.cfg" <<'EOF'
    try {
      const { Services } = ChromeUtils.import("resource://gre/modules/Services.jsm");
      const dir = Services.dirsvc.get("ProfD", Ci.nsIFile);
      const f = dir.clone();
      f.append("chrome");
      f.append("anixie-bridge.js");
      if (f.exists()) {
        Services.scriptloader.loadSubScript(f.path);
      }
    } catch (e) {
      console.error("anixie autoconfig:", e);
    }
    EOF
  '';

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

  # Browser chrome/content styling adapted from daccfiles browser_stuff.
  # userChrome/userContent are managed by Home Manager (legacy stylesheet pref is
  # enabled automatically). Colors are currently hardcoded; integrate with the
  # theme system if you want them to follow `anixie theme`.

  # Sidebery styles are applied inside Sidebery's settings (Styles editor), not
  # as a profile file. We install a reference copy for convenience.
  sideberySidebarCss = ''
    #root.root {--tabs-height: 36px;}
    #root.root {--tabs-inner-gap: 8px;}
    #root.root {--tabs-margin: 4px;}
    #root.root {--tabs-font: 16px sans-serif;}
    #root.root {--tabs-count-font: 16px sans-serif;}
    #root.root {--general-margin: 4px;}
    #root.root {--general-border-radius: 0px;}

    .Tab[data-active="true"] .body {
      border: 2px solid #ef944dff !important;
      border-radius: 0px;
    }

    .NavigationBar .main-items .nav-item[data-class="panel"] .name-box {
      border-width: 2px !important;
    }

    #root[data-act-el-color-scheme="dark"] {
      --active-el-shadow: none;
    }

    .NavigationBar .nav-item[data-active="true"] {
      border: 1px solid #ef944dff !important;
    }
  '';
in
{
  options.anixie.applications.browser = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install Chromium and LibreWolf (with managed extensions and profile styling), with LibreWolf as the default browser.";
    };

    liveBridge = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Inject an autoconfig bridge into LibreWolf so anixie-bridge.js runs
        and chrome CSS custom properties (--anixie-*) update without a restart.
        Off by default: it rewrites the LibreWolf install tree, and a bad
        autoconfig file can prevent the browser from launching.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.chromium ];

    programs.librewolf = {
      enable = true;
      package = if cfg.liveBridge then anixieLibrewolf else pkgs.librewolf;
      policies.ExtensionSettings = extensionSettings;

      profiles.default = {
        id = 0;
        isDefault = true;
        name = "default";
        path = "default";
        settings = {
          # Enable userChrome/userContent theming (managed by anixie templates).
          "toolkit.legacyUserProfileCustomizations.stylesheets" = true;

          # Minimal/clean UI.
          "browser.uidensity" = 1;
          "browser.compactmode.show" = true;
          "browser.aboutConfig.showWarning" = false;
          "browser.toolbars.bookmarks.visibility" = "never";
          "sidebar.position_start" = true;

          # Functional tweaks: keep interactions responsive and predictable.
          "findbar.highlightAll" = true;
          "full-screen-api.warning.timeout" = 0;
          "browser.tabs.loadBookmarksInTabs" = true;
          "browser.urlbar.suggest.engines" = false;
        };
      };
    };

    # Profile chrome is driven by the active anixie theme generation (see
    # modules/features/theming). HM would otherwise write static store files when
    # `userChrome`/`userContent` are set, so we symlink to the live generation.
    home.file = {
      ".librewolf/default/chrome/userChrome.css".source =
        config.lib.file.mkOutOfStoreSymlink "${config.anixie.theme.stateDir}/live/librewolf-userChrome.css";
      ".librewolf/default/chrome/userContent.css".source =
        config.lib.file.mkOutOfStoreSymlink "${config.anixie.theme.stateDir}/live/librewolf-userContent.css";
      ".librewolf/default/chrome/anixie-bridge.js".source = ./anixie-bridge.js;
    };

    # Sidebery's custom CSS is not read from the profile chrome folder; keep a
    # reference copy you can paste into Sidebery -> Settings -> Styles editor.
    xdg.configFile."librewolf/sidebery-sidebar.css".text = sideberySidebarCss;

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
