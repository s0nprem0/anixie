{
  config,
  lib,
  pkgs,
  ...
}:

{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;

      # Every rebuild adds an entry and a kernel to the ESP, and nothing removes
      # them. Ten generations is months of rollbacks on this machine and still
      # nowhere near filling a 512MB /boot.
      systemd-boot.configurationLimit = 10;

      # The stock five-second menu countdown was a quarter of the boot. One
      # second still leaves time to hold a key for an older generation.
      timeout = 1;
    };

    # Default to the stock kernel; cachyos-kernel.nix (imported after this
    # module) overrides it when enabled. Keeping it as mkDefault preserves a
    # fallback if the CachyOS module is removed.
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    # Nothing expects a file in /tmp to survive a reboot. /tmp is not a tmpfs
    # here, so without this a build's leftovers stay on the root subvolume until
    # something happens to remove them.
    tmp.cleanOnBoot = true;

    # Hibernation's resume partition. Taken from the swap device declared in
    # hardware-configuration.nix rather than repeated here, so the two cannot
    # drift apart. The filter keeps the disk swap: zram's swap is added by
    # zram-generator and is not a resume target — an image written to RAM is
    # exactly what a power loss throws away. A swap *file* would need
    # boot.resumeDevice plus a resume_offset; a partition, like this one, does
    # not.
    resumeDevice =
      let
        swapDevices = lib.filter (s: s.device != null) config.swapDevices;
        partitionSwaps = lib.filter (s: lib.hasPrefix "/dev/disk/by-uuid/" s.device) swapDevices;
        fileSwaps = lib.filter (
          s: lib.hasSuffix ".swap" s.device || lib.hasInfix "/swapfile" s.device
        ) swapDevices;
        # Never treat zram or swap files as resume partitions
        valid = lib.filter (
          s: !(lib.elem s fileSwaps) && !(lib.hasPrefix "/dev/zram" s.device)
        ) partitionSwaps;
      in
      if valid == [ ] then
        lib.warn "boot.nix: no UUID-based swap partition found for hibernation resume; boot.resumeDevice left unset" null
      else
        (builtins.head valid).device;
  };
}
