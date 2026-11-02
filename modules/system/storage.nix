{
  # btrfs checksums catch bit rot only when something reads the damaged
  # blocks. A monthly scrub reads every block and repairs what the redundancy
  # allows, and it is the one maintenance job the filesystem cannot do on its
  # own. The module defaults to every btrfs mount point and deduplicates the
  # subvolumes, so `/`, `/home` and `/nix` are one scrub.
  services.btrfs.autoScrub.enable = true;

  # The NVMe is the only disk in the machine, and SMART is where a failing
  # drive says so before the filesystem has to. smartd autodetects the devices
  # at startup and reports through wall by default; mail is off because this
  # machine has no MTA.
  services.smartd.enable = true;
}
