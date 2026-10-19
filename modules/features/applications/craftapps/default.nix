{ ... }:

{
  # The Craft apps — clean-room takes on the creative suite — from the
  # nix-craftapps flake (see flake.nix), which ships upstream's prebuilt binaries
  # rather than building the Rust workspace from source. Enabled here, in a Home
  # Manager module, so they land in the user profile: the NixOS side of the same
  # module exists only to link /usr/share/fonts, and installs nothing.
  #
  # All five share the toolkit, so all five have the same Wayland limitation as
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
}
