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

  systemd = {
    services = {
      # UPower 1.90+ can own the charge thresholds itself. When enabled it
      # re-applies the hwdb default (75/80 on every battery) at startup, which
      # silently overwrote the value saved by `charge-limit full`. The helper
      # below is the single writer here, so leave UPower's automation off; it
      # persists that choice in /var/lib/upower/charging-threshold-status.
      upower-charge-threshold = {
        description = "Leave charge thresholds to charge-limit";
        wantedBy = [ "multi-user.target" ];
        after = [ "upower.service" ];
        wants = [ "upower.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          # UPower can be up before its battery object is in the list, so give
          # enumeration a few tries rather than leaving the automation enabled.
          for _ in 1 2 3 4 5; do
            found=
            for dev in $(${pkgs.upower}/bin/upower -e 2>/dev/null || true); do
              case "$dev" in
                */battery_*)
                  found=1
                  ${config.systemd.package}/bin/busctl call --system \
                    org.freedesktop.UPower "$dev" \
                    org.freedesktop.UPower.Device EnableChargeThreshold b false || true
                  ;;
              esac
            done
            [ -n "$found" ] && break
            sleep 1
          done
        '';
      };

      # A laptop that lives on a desk spends its life at 100%, which is the
      # fastest way to wear a battery out. The charge controller accepts a
      # ceiling; 80% is the usual compromise between wear and having enough to
      # leave the house with. `charge-limit full` lifts it for a trip and saves
      # that choice, so this reads the saved value rather than forcing 80 on
      # every boot.
      battery-charge-limit = {
        description = "Apply the saved battery charge ceiling";
        wantedBy = [ "multi-user.target" ];
        after = [ "upower-charge-threshold.service" ];
        unitConfig.ConditionPathExists = "/sys/class/power_supply/BAT0/charge_control_end_threshold";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = "${chargeLimit}/bin/charge-limit apply";
      };
    };

    # Some firmware resets the controller while the machine sits idle, not only
    # at boot or on a cable event. The write is one sysfs line, so re-asserting
    # it every quarter hour is cheaper than being surprised by an 80% cap after a
    # firmware reset — and it never touches the battery itself.
    timers.battery-charge-limit = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "15min";
        AccuracySec = "1min";
      };
    };
  };

  # The controller can forget the ceiling across a firmware reset. Re-assert it
  # on either cable movement and after resume, rather than trusting a single
  # boot-time write. Matching without `online` covers the unplug too: the EC on
  # this machine drops back to its own default when the adapter goes away.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${config.systemd.package}/bin/systemctl --no-block restart battery-charge-limit.service"
  '';

  powerManagement.resumeCommands = "${chargeLimit}/bin/charge-limit apply";

  # The NMI watchdog spends a PMU counter and a periodic NMI on a machine that
  # is not being debugged. The performance tuner clears it while the performance
  # profile is active; clearing it at boot means the power-saver profile gets the
  # same saving instead of leaving it on by default.
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
