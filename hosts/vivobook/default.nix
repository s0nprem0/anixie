{
  imports = [
    ./hardware-configuration.nix

    ../../modules/system
  ];

  # Set explicitly so NixOS stops guessing. This is the release the machine is
  # actually running, which is what a freshly provisioned system should declare.
  system.stateVersion = "26.11";
}
