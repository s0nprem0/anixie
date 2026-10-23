{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.reminder;
in
{
  options.anixie.wm.reminder.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the reminder command, which uses systemd-run timers and notify-send.";
  };

  config = lib.mkIf cfg.enable {
    # notify is the sender the shell understands (features/wm/notify); it is the
    # client that asks for a notification, while the daemon that draws it lives
    # in the shell (features/wm/quickshell).
    #
    # systemd-run is already on the system path, and is what turns a duration into
    # a timer that outlives the command that set it.
    home.packages = [
      # The path is substituted in rather than left to $PATH, because the timer
      # runs as a service under the user manager and that does not necessarily
      # carry the path of whatever set the reminder.
      (pkgs.writeShellScriptBin "reminder" (
        builtins.replaceStrings
          [ "@NOTIFY_SEND@" "@QUICKSHELL@" ]
          [ config.anixie.wm.notify.bin "${pkgs.quickshell}/bin/quickshell" ]
          (builtins.readFile ./reminder.sh)
      ))
    ];
  };
}
