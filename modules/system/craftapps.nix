{
  # The Craft Apps' text tools look for fonts only in /usr/share/fonts and do
  # not use fontconfig, which NixOS leaves empty. The apps themselves are
  # installed per-user in features/applications/craftapps; this points
  # /usr/share/fonts at the system font directory for them.
  fonts.fontDir.enable = true;

  systemd.tmpfiles.rules = [
    "d /usr/share 0755 root root -"
    "L+ /usr/share/fonts - - - - /run/current-system/sw/share/X11/fonts"
  ];
}
