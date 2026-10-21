{
  # The Craft Apps' text tools look for fonts only in /usr/share/fonts and do
  # not use fontconfig, which NixOS leaves empty. Enabling the NixOS module with
  # no apps on this side installs nothing; linkFonts is what points
  # /usr/share/fonts at the system font directory. The apps themselves are
  # installed per-user in features/applications/craftapps.
  programs.craftapps = {
    enable = true;
    linkFonts = true;
  };
}
