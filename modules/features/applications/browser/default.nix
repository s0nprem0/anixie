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
  userChrome = ''
    #TabsToolbar { display: none !important; }
    #sidebar-panel-header { display: none !important; }
    #sidebar-box { padding-inline-start: 0px !important; }

    * { border-radius: 0px !important; }
  '';

  userContent = ''
    @-moz-document url-prefix("about:") {
      body {
        background-color: #0f0f0f !important;
        color: #f4decd !important;
      }

      * {
        border-radius: 0px !important;
      }

      button:hover, .button:hover {
        background-color: #ef934d !important;
        color: #0f0f0f !important;
      }

      * {
        --text-color:               #f4decd !important;
        --color-accent-primary:     light-dark(#ef934d55, #ef934d) !important;
        --color-accent-secondary:   light-dark(#f4b58555, #f4b585) !important;
      }

      * {
        --color-blue-0:  #71b4d6 !important;
        --color-blue-10: #71b4d6 !important;
        --color-blue-20: #71b4d6 !important;
        --color-blue-30: #71b4d6 !important;
        --color-blue-40: #71b4d6 !important;
        --color-blue-50: #71b4d6 !important;
        --color-blue-60: #71b4d6 !important;
        --color-blue-70: #71b4d6 !important;
        --color-blue-80: #71b4d6 !important;
        --color-blue-90: #71b4d6 !important;
        --color-cyan-0:  #7ec9a3 !important;
        --color-cyan-10: #7ec9a3 !important;
        --color-cyan-20: #7ec9a3 !important;
        --color-cyan-30: #7ec9a3 !important;
        --color-cyan-40: #7ec9a3 !important;
        --color-cyan-50: #7ec9a3 !important;
        --color-cyan-60: #7ec9a3 !important;
        --color-cyan-70: #7ec9a3 !important;
        --color-cyan-80: #7ec9a3 !important;
        --color-cyan-90: #7ec9a3 !important;
        --color-gray-0:  #fcfbff !important;
        --color-gray-05: #f7f6fb !important;
        --color-gray-10: #efedf2 !important;
        --color-gray-15: #e3e2e7 !important;
        --color-gray-20: #d6d5da !important;
        --color-gray-25: #c7c6cb !important;
        --color-gray-30: #b7b6ba !important;
        --color-gray-35: #a6a4a9 !important;
        --color-gray-40: #949297 !important;
        --color-gray-45: #817f84 !important;
        --color-gray-50: #67666a !important;
        --color-gray-55: #515054 !important;
        --color-gray-60: #3f3e42 !important;
        --color-gray-65: #312f33 !important;
        --color-gray-70: #252428 !important;
        --color-gray-75: #1d1b1f !important;
        --color-gray-80: #171519 !important;
        --color-gray-85: #131215 !important;
        --color-gray-90: #121114 !important;
        --color-green-0:  #7ec97e !important;
        --color-green-10: #7ec97e !important;
        --color-green-20: #7ec97e !important;
        --color-green-30: #7ec97e !important;
        --color-green-40: #7ec97e !important;
        --color-green-50: #7ec97e !important;
        --color-green-60: #7ec97e !important;
        --color-green-70: #7ec97e !important;
        --color-green-80: #7ec97e !important;
        --color-green-90: #7ec97e !important;
        --color-orange-0:  #ef934d !important;
        --color-orange-10: #ef934d !important;
        --color-orange-20: #ef934d !important;
        --color-orange-30: #ef934d !important;
        --color-orange-40: #ef934d !important;
        --color-orange-50: #ef934d !important;
        --color-orange-60: #ef934d !important;
        --color-orange-70: #ef934d !important;
        --color-orange-80: #ef934d !important;
        --color-orange-90: #ef934d !important;
        --color-pink-0:  #ef934d !important;
        --color-pink-10: #ef934d !important;
        --color-pink-20: #ef934d !important;
        --color-pink-30: #ef934d !important;
        --color-pink-40: #ef934d !important;
        --color-pink-50: #ef934d !important;
        --color-pink-60: #ef934d !important;
        --color-pink-70: #ef934d !important;
        --color-pink-80: #ef934d !important;
        --color-pink-90: #ef934d !important;
        --color-purple-0:  #ef934d !important;
        --color-purple-10: #ef934d !important;
        --color-purple-20: #ef934d !important;
        --color-purple-30: #ef934d !important;
        --color-purple-40: #ef934d !important;
        --color-purple-50: #ef934d !important;
        --color-purple-60: #ef934d !important;
        --color-purple-70: #ef934d !important;
        --color-purple-80: #ef934d !important;
        --color-purple-90: #ef934d !important;
        --color-red-0:  #f16e65 !important;
        --color-red-10: #f16e65 !important;
        --color-red-20: #f16e65 !important;
        --color-red-30: #f16e65 !important;
        --color-red-40: #f16e65 !important;
        --color-red-50: #f16e65 !important;
        --color-red-60: #f16e65 !important;
        --color-red-70: #f16e65 !important;
        --color-red-80: #f16e65 !important;
        --color-red-90: #f16e65 !important;
        --color-violet-0:  #ef934d !important;
        --color-violet-10: #ef934d !important;
        --color-violet-20: #ef934d !important;
        --color-violet-30: #ef934d !important;
        --color-violet-40: #ef934d !important;
        --color-violet-50: #ef934d !important;
        --color-violet-60: #ef934d !important;
        --color-violet-70: #ef934d !important;
        --color-violet-80: #ef934d !important;
        --color-violet-90: #ef934d !important;
        --color-violet-desaturated-0:  #ef934d !important;
        --color-violet-desaturated-10: #ef934d !important;
        --color-violet-desaturated-20: #ef934d !important;
        --color-violet-desaturated-30: #ef934d !important;
        --color-violet-desaturated-40: #ef934d !important;
        --color-violet-desaturated-50: #ef934d !important;
        --color-violet-desaturated-60: #ef934d !important;
        --color-violet-desaturated-70: #ef934d !important;
        --color-violet-desaturated-80: #ef934d !important;
        --color-violet-desaturated-90: #ef934d !important;
        --color-yellow-0:  #efbf71 !important;
        --color-yellow-10: #efbf71 !important;
        --color-yellow-20: #efbf71 !important;
        --color-yellow-30: #efbf71 !important;
        --color-yellow-40: #efbf71 !important;
        --color-yellow-50: #efbf71 !important;
        --color-yellow-60: #efbf71 !important;
        --color-yellow-70: #efbf71 !important;
        --color-yellow-80: #efbf71 !important;
        --color-yellow-90: #efbf71 !important;
      }

      * {
        --background-color-box:                  #1e1f1e !important;
        --background-color-box-info:             #1e1f1e !important;
        --background-color-information:          #272a28 !important;
        --background-color-canvas:               #0f0f0f !important;
        --border-color:                          #3b403c !important;
        --border-color-deemphasized:             #3b403c !important;
        --button-background-color-muted:         #272a28 !important;
        --button-text-color-ghost-disabled:      #888e7b !important;
        --button-border:                         2px solid var(--border-color) !important;
        --table-row-background-color-alternate:  #1e1f1e !important;
        --text-color-accent-primary-selected:    var(--text-color) !important;
      }

      * {
        --table-background-color:        var(--background-color-box) !important;
        --table-border-color:            var(--border-color) !important;
        --table-header-background-color: var(--color-accent-primary) !important;
        --table-row-background-color:    var(--background-color-canvas) !important;
      }
    }
  '';

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
