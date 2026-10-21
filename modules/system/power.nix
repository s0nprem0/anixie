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

  # A laptop that lives on a desk spends its life at 100%, which is the fastest
  # way to wear a battery out. The charge controller accepts a ceiling; 80% is the
  # usual compromise between wear and having enough to leave the house with.
  # Re-asserted at boot because the setting lives in the controller, not on disk.
  systemd.services.battery-charge-limit = {
    description = "Cap battery charging at 80%";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/sys/class/power_supply/BAT0/charge_control_end_threshold";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'';
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
    # than hibernate. Hibernation writes a resume image to the swap partition and
    # boot.resumeDevice (set in boot.nix) points the kernel at it, but suspend is
    # the faster and more reliable action here: it holds the session until a
    # charger is found without the risk of a failed resume. NixOS gates suspend
    # behind the "risky" flag.
    criticalPowerAction = "Suspend";
    allowRiskyCriticalPowerAction = true;
  };
}
