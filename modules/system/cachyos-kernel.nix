{ inputs, pkgs, ... }:

{
  # CachyOS kernel via the pinned overlay (binary-cache friendly).
  nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

  # x86-64-v3 variant: your Ryzen 5 5500U has AVX2/BMI2/FMA, so v3 is safe.
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-x86_64-v3;
}
