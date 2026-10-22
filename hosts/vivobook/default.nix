{
  imports = [
    ./hardware-configuration.nix

    ../../modules/system
  ];

  # Set explicitly so NixOS stops guessing. This is the release the machine is
  # actually running, which is what a freshly provisioned system should declare.
  system.stateVersion = "26.11";

  # This machine's clock, not a default for every host sharing modules/system.
  # Set it here so another host can sit in a different zone without editing the
  # common networking module.
  time.timeZone = "Asia/Manila";
}
