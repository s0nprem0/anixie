{
  # BIOS, SSD and dock firmware from the Linux Vendor Firmware Service. Nothing
  # installs it automatically: `fwupdmgr refresh && fwupdmgr update` is a
  # deliberate act, and some of it can only be written during a reboot.
  services.fwupd.enable = true;
}
