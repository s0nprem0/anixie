{
  # cups-filters is added on the home-manager side, in
  # features/applications/printer, since home.packages is not a NixOS option.
  services.printing.enable = true;
}
