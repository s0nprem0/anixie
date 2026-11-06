{
  config,
  lib,
  pkgs,
  inputs ? { },
  ...
}:

let
  cfg = config.anixie.wm.display;
  alexiePkg = inputs.alexie.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.anixie.wm.display = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the monitors script and wlr-randr for display management.";
    };

    defaultScale = lib.mkOption {
      type = lib.types.either lib.types.number (lib.types.enum [ "auto" ]);
      default = 1;
      example = "auto";
      description = ''
        Scale for an output that has no saved per-output rule. The catch-all
        monitor rule is a fallback, not a setting: changing a scale from the
        panel or the `monitors` command writes a per-output state line, never
        this value. `auto` lets Hyprland pick from the panel's PPI.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # The Hyprland config is rendered through the theme template renderer,
      # which is also how the bar's position reaches QML. A number is emitted
      # bare; "auto" has to keep its quotes so Lua passes a string.
      anixie.theme.template.placeholders."@MONITOR_DEFAULT_SCALE@" =
        if cfg.defaultScale == "auto" then "\"auto\"" else toString cfg.defaultScale;
    }

    (lib.mkIf cfg.enable {
      home.packages = [
        # Resolution, scale, refresh rate and output switching from the terminal, for
        # anything `monitors` does not cover.
        pkgs.wlr-randr

        # External monitor brightness over DDC/CI. The internal panel keeps using
        # brightnessctl; ddcutil is only reached when the focused output is not an
        # eDP/LVDS/DSI panel.
        pkgs.ddcutil
      ];

      # Before Hyprland reads display.conf, clear an internal panel that was left
      # switched off while docked. Without this, booting undocked applies
      # disabled = true to the only output and leaves no usable screen.
      systemd.user.services.anixie-display-recover = {
        Unit = {
          Description = "Clear stale display and clamshell state";
          Before = [ "graphical-session-pre.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${alexiePkg}/bin/alexie monitors recover";
        };
        Install.WantedBy = [ "graphical-session-pre.target" ];
      };
    })
  ];
}
