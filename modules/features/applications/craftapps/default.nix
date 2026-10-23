{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.craftapps;

  enabledApps = lib.filterAttrs (_: app: app.enable) config.programs.craftapps.apps;

  # Rewrite the Exec line of the entry shipped in the package, leaving every other
  # key as upstream wrote it.
  xwaylandEntry =
    name: app:
    pkgs.runCommand "ai.storyteller.${name}.desktop" { } ''
      sed 's|^Exec=|Exec=env WAYLAND_DISPLAY= |' \
        ${app.package}/share/applications/ai.storyteller.${name}.desktop > $out
    '';
in
{
  options.anixie.applications.craftapps.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the Craft Apps (PhotoCraft, VectorCraft, etc.) from the nix-craftapps flake.";
  };

  config = lib.mkIf cfg.enable {
    # The Craft apps — clean-room takes on the creative suite — from the
    # nix-craftapps flake (see flake.nix), which ships upstream's prebuilt binaries
    # rather than building the Rust workspace from source. Enabled here, in a Home
    # Manager module, so they land in the user profile: the NixOS side of the same
    # module exists only to link /usr/share/fonts, and installs nothing.
    #
    # They share the toolkit, so they share the Wayland limitation: native file
    # drag-and-drop does not exist in the protocol. Every enabled app gets the
    # XWayland workaround below.
    programs.craftapps = {
      enable = true;
      apps = {
        photocraft.enable = true;
        vectorcraft.enable = true;
        effectcraft.enable = true;
        filmcraft.enable = true;
        soundcraft.enable = true;
        wordcraft.enable = true;
        deckcraft.enable = true;
        gridcraft.enable = true;
      };
    };

    # The Office formats the three document apps declare in their own desktop
    # entries. Plain text, Markdown, TeX, HTML and CSV are deliberately absent:
    # they are text files first, and handing them to a word processor would be a
    # worse default than whatever opens them now.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document" =
          "ai.storyteller.wordcraft.desktop";
        "application/vnd.ms-word.document.macroEnabled.12" = "ai.storyteller.wordcraft.desktop";
        "application/vnd.openxmlformats-officedocument.wordprocessingml.template" =
          "ai.storyteller.wordcraft.desktop";
        "application/vnd.ms-word.template.macroEnabled.12" = "ai.storyteller.wordcraft.desktop";
        "application/msword" = "ai.storyteller.wordcraft.desktop";
        "application/msword-template" = "ai.storyteller.wordcraft.desktop";
        "application/vnd.oasis.opendocument.text" = "ai.storyteller.wordcraft.desktop";
        "application/rtf" = "ai.storyteller.wordcraft.desktop";
        "text/rtf" = "ai.storyteller.wordcraft.desktop";

        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" =
          "ai.storyteller.gridcraft.desktop";
        "application/vnd.ms-excel.sheet.macroEnabled.12" = "ai.storyteller.gridcraft.desktop";
        "application/vnd.ms-excel.sheet.binary.macroEnabled.12" = "ai.storyteller.gridcraft.desktop";
        "application/vnd.oasis.opendocument.spreadsheet" = "ai.storyteller.gridcraft.desktop";

        "application/vnd.openxmlformats-officedocument.presentationml.presentation" =
          "ai.storyteller.deckcraft.desktop";
        "application/vnd.openxmlformats-officedocument.presentationml.template" =
          "ai.storyteller.deckcraft.desktop";
        "application/vnd.openxmlformats-officedocument.presentationml.slideshow" =
          "ai.storyteller.deckcraft.desktop";
        "application/x-deckcraft" = "ai.storyteller.deckcraft.desktop";
      };
    };

    # A window cannot hand a file to another application over Wayland, so the
    # apps say so and offer their own way out: run under XWayland. So they do.
    #
    # The desktop entries are overridden rather than the binaries wrapped, so the
    # menu, a file manager and `xdg-open` all take the same path; clearing
    # WAYLAND_DISPLAY is exactly the invocation the apps' own dialogs suggest. The
    # GUI chooses the compatibility server for one feature; the CLI and the rest of
    # the session stay on Wayland.
    #
    # The alternative is Preferences → Performance → Linux display server → X11,
    # which each app remembers itself. This just means a fresh profile starts there.
    #
    # Each entry is generated from the one in the package by replacing the Exec
    # line, rather than copied here: a copied file shadows upstream's, so every key
    # they add would have to be mirrored or it would silently vanish. Written this
    # way rather than through `xdg.desktopEntries` because that option is broken
    # against this nixpkgs — its module still passes `extraConfig` to
    # `makeDesktopItem`, which no longer takes it, so merely defining an entry
    # errors the build.
    xdg.configFile = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "applications/ai.storyteller.${name}.desktop" {
        source = xwaylandEntry name app;
      }
    ) enabledApps;
  };
}
