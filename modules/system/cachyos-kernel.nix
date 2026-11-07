{ inputs, pkgs, ... }:

{
  # CachyOS kernel via the pinned overlay (binary-cache friendly).
  nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];

  # Initial selection: regular latest CachyOS kernel (no LTO/BORE/v3).
  boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
}
