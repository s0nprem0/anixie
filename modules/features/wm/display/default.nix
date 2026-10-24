{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.display;

  # Monitor scaling, the internal panel, and mirroring — the things the brightness
  # and function keys do not reach. Built the same way as the capture commands:
  # paths substituted rather than left to $PATH, since these run from a bind.
  monitors = pkgs.writeShellScriptBin "monitors" (
    builtins.replaceStrings
      [
        "@HYPRCTL@"
        "@JQ@"
        "@BRIGHTNESSCTL@"
        "@DDCUTIL@"
        "@QUICKSHELL@"
        "@ANIXIE_LIB@"
      ]
      [
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.jq}/bin/jq"
        "${pkgs.brightnessctl}/bin/brightnessctl"
        "${pkgs.ddcutil}/bin/ddcutil"
        "${pkgs.quickshell}/bin/quickshell"
        "${../../cli/lib.sh}"
      ]
      (builtins.readFile ./monitors.sh)
  );
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
        # Named `monitors`, not `display`: ImageMagick already ships a `display` — its
        # X11 image viewer — and shadowing it would take a name away from a package
        # that is installed here for the capture commands.
        monitors

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
          ExecStart = "${monitors}/bin/monitors recover";
        };
        Install.WantedBy = [ "graphical-session-pre.target" ];
      };
    })
  ];
}
