{
  user,
  ...
}:

let
  # Wallpapers that ship with the host rather than the user's home, so a fresh
  # install comes up with the same background. The flake copies the directory to
  # the store; the library scans it and `default` names one of its pictures.
  wallpapers = ../../modules/wallpaper;
in
{
  imports = [
    ./hardware-configuration.nix

    ../../modules/system
    ../../modules/system/ndi.nix
  ];

  home-manager.users.${user}.anixie.theme.wallpaper = {
    default = "${wallpapers}/cat_sigar.jpg";
    extraDirs = [ "${wallpapers}" ];
  };

  # Set explicitly so NixOS stops guessing. This is the release the machine is
  # actually running, which is what a freshly provisioned system should declare.
  system.stateVersion = "26.11";

  # This machine's clock, not a default for every host sharing modules/system.
  # Set it here so another host can sit in a different zone without editing the
  # common networking module.
  time.timeZone = "Asia/Manila";
}
