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

    kernelPackages = pkgs.linuxPackages_latest;

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
    resumeDevice = lib.findFirst (d: lib.hasPrefix "/dev/disk/by-uuid/" d) "" (
      map (swap: swap.device) config.swapDevices
    );
  };
}
