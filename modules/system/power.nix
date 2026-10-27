_:

{
  services = {
    power-profiles-daemon.enable = true;

    # The power key opens a menu, not the off switch. logind's default is to power
    # off the moment the key is pressed, which is the right answer for a server and
    # the wrong one for a laptop whose power key sits next to the keyboard: one
    # press should ask, and a deliberate hold still forces it.
    logind.settings.Login = {
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "poweroff";

      # Docked or on mains, closing the lid should leave the external screen
      # usable. On battery the default suspend still applies unless the
      # stay-awake inhibitor is on; clamshell display handling itself lives in
      # Hyprland's lid binds.
      HandleLidSwitchDocked = "ignore";
      HandleLidSwitchExternalPower = "ignore";
    };

    # The battery readout comes from here rather than from sysfs directly. UPower
    # normalises the micro-units the kernel reports, tells "on mains but holding"
    # apart from "on battery", and hands out both time estimates, none of which
    # the raw files do — and it is event-driven, so nothing has to be watched.
    upower = {
      enable = true;

      # Match the two levels anixie.power.batteryAutomation uses, so UPower's
      # notion of low and critical agrees with the bar's warning colour and the
      # dimming watcher instead of warning at a different point. Keep these in
      # step if the automation thresholds change.
      percentageLow = 20;
      percentageCritical = 8;

      # At the critical level (2%, from the stock PercentageAction), suspend rather
      # than hibernate. Hibernation writes a resume image to the swap partition and
      # boot.resumeDevice (set in boot.nix) points the kernel at it, but suspend is
      # the faster and more reliable action here: it holds the session until a
      # charger is found without the risk of a failed resume. NixOS gates suspend
      # behind the "risky" flag.
      criticalPowerAction = "Suspend";
      allowRiskyCriticalPowerAction = true;
    };
  };

  # The NMI watchdog spends a PMU counter and a periodic NMI on a machine that
  # is not being debugged. Disable it once at boot rather than toggling it with
  # the power profile, so every profile gets the same saving.
  #
  # PCIe ASPM parks idle links. `powersave` is the conservative setting: it
  # still wakes the NVMe and GPU on demand, unlike `powersupersave`, and it is
  # what the performance tuner restores when it leaves the performance profile.
  boot.kernelParams = [
    "nmi_watchdog=0"
    "pcie_aspm.policy=powersave"
  ];

  # Compressed swap in RAM. The disk swap partition still exists for suspend,
  # but this keeps the common case off the slow device when memory fills.
  zramSwap.enable = true;
}
