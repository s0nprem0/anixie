{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.power.batteryAutomation;
  state = "${config.xdg.stateHome}/anixie/powerprofile";

  powerprofile = pkgs.writeShellScriptBin "powerprofile" (
    builtins.replaceStrings
      [
        "@STATE@"
        "@PPD@"
        "@UDEVADM@"
        "@BRIGHTNESSCTL@"
        "@AC_PROFILE@"
        "@BATTERY_PROFILE@"
        "@AUTO@"
        "@LOW@"
        "@CRITICAL@"
        "@LOW_PROFILE@"
        "@CRITICAL_PROFILE@"
        "@LOW_BRIGHTNESS@"
        "@CRITICAL_BRIGHTNESS@"
        "@CHARGE_LIMIT@"
        "@CHARGE_STATE@"
        "@SUDO@"
        "@ANIXIE_LIB@"
      ]
      [
        state
        "${pkgs.power-profiles-daemon}/bin/powerprofilesctl"
        "${pkgs.systemd}/bin/udevadm"
        "${pkgs.brightnessctl}/bin/brightnessctl"
        config.anixie.power.acProfile
        config.anixie.power.batteryProfile
        (if cfg.enable then "1" else "0")
        (toString cfg.lowThreshold)
        (toString cfg.criticalThreshold)
        cfg.lowProfile
        cfg.criticalProfile
        (toString cfg.lowBrightness)
        (toString cfg.criticalBrightness)
        # The charge helper is a system package: writing the controller needs
        # root, so the write goes through the setuid sudo wrapper.
        "/run/current-system/sw/bin/charge-limit"
        # Read-only here: `show` uses it to report a saved value that the
        # controller has not taken yet.
        "/var/lib/anixie/charge-limit"
        "/run/wrappers/bin/sudo"
        "${../cli/lib.sh}"
      ]
      (builtins.readFile ./powerprofile.sh)
  );
in
{
  options.anixie.power = {
    acProfile = lib.mkOption {
      type = lib.types.enum [
        "power-saver"
        "balanced"
        "performance"
      ];
      default = "performance";
      description = ''
        The default profile while the adapter is connected. A profile chosen at
        runtime with `powerprofile set ac PROFILE` overrides this.
      '';
    };

    batteryProfile = lib.mkOption {
      type = lib.types.enum [
        "power-saver"
        "balanced"
        "performance"
      ];
      default = "power-saver";
      description = ''
        The default profile while on battery. Power-saver lowers the platform
        profile and EPP, which is the largest idle-power win on this machine; use
        `powerprofile set battery balanced` when the extra responsiveness is
        worth the drain. A runtime choice overrides this.
      '';
    };

    batteryAutomation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether the power-profile watcher reacts to the battery's charge by
          default: dim the screen and step down the profile at the two
          thresholds, then restore both on mains or when the charge recovers.
          The power panel toggles this at runtime, and its choice overrides this
          default until the state file is removed.
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

    };

    bin = lib.mkOption {
      type = lib.types.str;
      internal = true;
      readOnly = true;
      default = "${powerprofile}/bin/powerprofile";
      description = ''
        The powerprofile command, for callers that need its absolute path. The
        shell service does not inherit the user's profile path.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.lowThreshold > cfg.criticalThreshold;
        message = "anixie.power.batteryAutomation.lowThreshold must be above criticalThreshold";
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
