{
  # cups-filters is added on the home-manager side, in
  # features/applications/printer, since home.packages is not a NixOS option.
  services.printing.enable = true;

  # simple-scan is installed beside the printer apps, but it cannot see a
  # scanner until SANE's backends and udev rules are present. The module tags
  # scanners with `uaccess`, so the logged-in seat gets access without adding
  # the user to the `scanner` group.
  hardware.sane.enable = true;
}
