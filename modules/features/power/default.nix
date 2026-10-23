{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.power.batteryAutomation;
  state = "${config.xdg.stateHome}/anixie/powerprofile";

  powerprofile = pkgs.writeShellScriptBin "powerprofile" (
    builtins.replaceStrings
      [
        "@STATE@"
        "@PPD@"
        "@UDEV@"
        "@BRIGHTNESSCTL@"
        "@NOTIFY@"
        "@AUTO@"
        "@LOW@"
        "@CRITICAL@"
        "@LOW_PROFILE@"
        "@CRITICAL_PROFILE@"
        "@LOW_BRIGHTNESS@"
        "@CRITICAL_BRIGHTNESS@"
        "@NOTIFY_LEVEL@"
        "@ANIXIE_LIB@"
      ]
      [
        state
        "${pkgs.power-profiles-daemon}/bin/powerprofilesctl"
        "${pkgs.systemd}/bin/udevadm"
        "${pkgs.brightnessctl}/bin/brightnessctl"
        config.my.wm.notify.bin
        (if cfg.enable then "1" else "0")
        (toString cfg.lowThreshold)
        (toString cfg.criticalThreshold)
        cfg.lowProfile
        cfg.criticalProfile
        (toString cfg.lowBrightness)
        (toString cfg.criticalBrightness)
        (if cfg.notify then "1" else "0")
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./powerprofile.sh)
  );
in
{
  options.my.power.batteryAutomation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether the power-profile watcher also reacts to the battery's charge:
        dim the screen and step down the profile at the two thresholds, then
        restore both on mains or when the charge recovers.
      '';
    };

    lowThreshold = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 20;
      description = "Battery percentage at which the low state begins.";
    };

    criticalThreshold = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 8;
      description = "Battery percentage at which the critical state begins.";
    };

    lowProfile = lib.mkOption {
      type = lib.types.enum [
        "power-saver"
        "balanced"
        "performance"
      ];
      default = "power-saver";
      description = "Power profile applied at the low threshold.";
    };

    criticalProfile = lib.mkOption {
      type = lib.types.enum [
        "power-saver"
        "balanced"
        "performance"
      ];
      default = "power-saver";
      description = "Power profile applied at the critical threshold.";
    };

    lowBrightness = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 30;
      description = "Screen brightness percentage applied at the low threshold.";
    };

    criticalBrightness = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 15;
      description = "Screen brightness percentage applied at the critical threshold.";
    };

    notify = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether crossing a threshold sends one notification.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.lowThreshold > cfg.criticalThreshold;
        message = "my.power.batteryAutomation.lowThreshold must be above criticalThreshold";
      }
    ];

    home.packages = [
      powerprofile
      pkgs.brightnessctl
    ];

    # Applies the stored profile at login, on every plug or unplug, and while the
    # battery drains. A service rather than a login hook so it keeps working after
    # the cable moves, which is the whole point.
    systemd.user.services.anixie-powerprofile = {
      Unit = {
        Description = "Apply the power profile and battery thresholds for the current source";
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${powerprofile}/bin/powerprofile watch";
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
