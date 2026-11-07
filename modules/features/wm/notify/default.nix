{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.notify;
in
{
  # The sender is notify-send itself now: the glyph/action/click
  # contract that `notify` used to translate into hints is written
  # by callers directly (see features/wm/mixer and Ui/PowerAlert).
  options.anixie.wm.notify = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the notification daemon's sender path is set.";
    };

    bin = lib.mkOption {
      type = lib.types.str;
      default = "${pkgs.libnotify}/bin/notify-send";
      description = ''
        The sender command, for modules that need its path rather than the name
        on PATH: the notification daemon, Hyprland binds and systemd timers do
        not necessarily carry the user's profile path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.libnotify ];
  };
}
