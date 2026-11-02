_:

{
  # systemd-oomd is enabled by default but monitors nothing until a unit opts
  # in, so on this machine the kernel's global OOM killer was the only thing
  # acting when a batch of ImageMagick workers filled RAM and both swaps. It
  # fired 17 times in a row, taking the shell and the user manager with it.
  #
  # Point it at the user and system slices instead: only leaf cgroups below a
  # monitored unit are candidates, so the kill lands on the unit that is
  # actually under pressure (the terminal running the batch) and the session
  # survives. 80% is the limit the NixOS module and Fedora both use; the
  # process is already unresponsive by then, but it fires before the kernel.
  systemd.oomd = {
    enableUserSlices = true;
    enableSystemSlice = true;
  };

  # Swap-based kills work on whole-system figures, so the root slice is the
  # right place for the setting: when swap is more than 90% full, oomd kills
  # the leaf cgroup using the most of it. This is the case the crash above
  # walked into; pressure-based kills alone would have come later.
  systemd.slices."-".sliceConfig.ManagedOOMSwap = "kill";
}
