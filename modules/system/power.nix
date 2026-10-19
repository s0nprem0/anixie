{
  services.power-profiles-daemon.enable = true;

  # The power key opens a menu, not the off switch. logind's default is to power
  # off the moment the key is pressed, which is the right answer for a server and
  # the wrong one for a laptop whose power key sits next to the keyboard: one
  # press should ask, and a deliberate hold still forces it.
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "poweroff";
  };

  # Compressed swap in RAM. The disk swap partition still exists for suspend,
  # but this keeps the common case off the slow device when memory fills.
  zramSwap.enable = true;

  # The battery readout comes from here rather than from sysfs directly. UPower
  # normalises the micro-units the kernel reports, tells "on mains but holding"
  # apart from "on battery", and hands out both time estimates, none of which
  # the raw files do — and it is event-driven, so nothing has to be watched.
  services.upower = {
    enable = true;

    # At the critical level (2%, from the stock PercentageAction), suspend rather
    # than hibernate. The default of HybridSleep writes a resume image nothing is
    # configured to read back — there is no `resume=` on the kernel command line
    # and no boot.resumeDevice — so it would fail and leave the machine to run
    # flat. Suspend is the action that actually works here; it holds the session
    # until a charger is found. NixOS gates suspend behind the "risky" flag.
    criticalPowerAction = "Suspend";
    allowRiskyCriticalPowerAction = true;
  };
}
