{ ... }:

{
  # PhotoCraft is an open-source, clean-room Photoshop reimplementation. It
  # comes from the nix-craftapps flake (see flake.nix), which ships upstream's
  # prebuilt binaries rather than building the Rust workspace from source.
  programs.craftapps = {
    enable = true;
    apps.photocraft.enable = true;
  };
}
