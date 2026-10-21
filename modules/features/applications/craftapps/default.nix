{
  config,
  lib,
  ...
}:

let
  cfg = config.my.applications.craftapps;
in
{
  options.my.applications.craftapps.enable = lib.mkOption {
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
    # They share the toolkit, so they have the same Wayland limitation as
    # PhotoCraft: native file drag-and-drop. Only PhotoCraft's desktop entry carries
    # the XWayland workaround below — add the same for another if dropping files on
    # it matters.
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

    # Native file drag-and-drop does not exist on Wayland yet — a window cannot
    # hand a file to another application over the protocol — and PhotoCraft says so
    # and offers its own way out: run under XWayland. So it does.
    #
    # The desktop entry is overridden rather than the binary wrapped, so the menu,
    # a file manager and `xdg-open` all take the same path; clearing
    # WAYLAND_DISPLAY is exactly the invocation the app's own dialog suggests. One
    # application chooses the compatibility server for one feature; nothing else in
    # the session moves off Wayland.
    #
    # The alternative is Preferences → Performance → Linux display server → X11,
    # which the app remembers itself. This just means a fresh profile starts there.
    # Written by hand rather than through `xdg.desktopEntries`: that option is
    # broken against this nixpkgs — its module still passes `extraConfig` to
    # `makeDesktopItem`, which no longer takes it, so merely defining an entry
    # errors the build. The file is four lines of the same thing.
    xdg.configFile."applications/ai.storyteller.photocraft.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=PhotoCraft
      GenericName=Image Editor
      Comment=Edit photos and layered PSD documents
      Exec=env WAYLAND_DISPLAY= photocraft %F
      Icon=ai.storyteller.photocraft
      Terminal=false
      StartupNotify=false
      StartupWMClass=ai.storyteller.photocraft
      Categories=Graphics;2DGraphics;RasterGraphics;Photography;
      Keywords=photo;image;editor;psd;layers;retouch;paint;
      MimeType=application/x-photocraft;image/x-paintnet;image/openraster;application/x-krita;image/vnd.adobe.photoshop;image/x-psd;image/x-psb;image/png;image/jpeg;image/tiff;image/webp;image/gif;image/bmp;image/x-tga;image/x-icon;image/vnd.microsoft.icon;image/x-portable-anymap;image/x-portable-bitmap;image/x-portable-graymap;image/x-portable-pixmap;image/x-exr;image/vnd.radiance;image/avif;image/qoi;
    '';
  };
}
