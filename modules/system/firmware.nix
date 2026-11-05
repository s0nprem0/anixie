{
  # BIOS, SSD and dock firmware from the Linux Vendor Firmware Service. Nothing
  # installs it automatically: `fwupdmgr refresh && fwupdmgr update` is a
  # deliberate act, and some of it can only be written during a reboot.
  services.fwupd.enable = true;

  # Ship the redistributable firmware (AMD/Intel GPU microcode, Wi-Fi, etc.).
  # Without it the AMD iGPU on the Vivobook never gets its firmware, so the
  # kernel falls back to llvmpipe software rendering.
  hardware.enableRedistributableFirmware = true;
}
