{
  services.power-profiles-daemon.enable = true;

  # The battery readout comes from here rather than from sysfs directly. UPower
  # normalises the micro-units the kernel reports, tells "on mains but holding"
  # apart from "on battery", and hands out both time estimates, none of which
  # the raw files do — and it is event-driven, so nothing has to be watched.
  services.upower.enable = true;
}
