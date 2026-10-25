{
  config,
  pkgs,
  ...
}:

let
  # The ceiling is a controller setting, not a file, so the choice made with
  # `charge-limit full` is kept here for the boot/resume/plug helper to re-apply.
  chargeState = "/var/lib/anixie/charge-limit";

  chargeLimit = pkgs.writeShellScriptBin "charge-limit" (
    builtins.replaceStrings
      [ "@BAT@" "@STATE@" "@DEFAULT@" "@ANIXIE_LIB@" ]
      [
        "/sys/class/power_supply/BAT0/charge_control_end_threshold"
        chargeState
        "80"
        "${../features/cli/lib.sh}"
      ]
      (builtins.readFile ./charge-limit.sh)
  );
in
{
  environment.systemPackages = [ chargeLimit ];

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

  # A laptop that lives on a desk spends its life at 100%, which is the fastest
  # way to wear a battery out. The charge controller accepts a ceiling; 80% is the
  # usual compromise between wear and having enough to leave the house with.
  # `charge-limit full` lifts it for a trip and saves that choice, so this reads
  # the saved value rather than forcing 80 on every boot.
  systemd.services.battery-charge-limit = {
    description = "Apply the saved battery charge ceiling";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/sys/class/power_supply/BAT0/charge_control_end_threshold";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = "${chargeLimit}/bin/charge-limit apply";
  };

  # The controller can forget the ceiling across a firmware reset. Re-assert it
  # whenever the adapter is plugged in, and after resume, rather than trusting a
  # single boot-time write.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="${config.systemd.package}/bin/systemctl --no-block restart battery-charge-limit.service"
  '';

  powerManagement.resumeCommands = "${chargeLimit}/bin/charge-limit apply";

  # Compressed swap in RAM. The disk swap partition still exists for suspend,
  # but this keeps the common case off the slow device when memory fills.
  zramSwap.enable = true;
}
