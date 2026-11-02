{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.notify;

  # The sender contract for everything in the tree. notify-send is named by its
  # full path because the wrapper is also called from systemd timers and from
  # Hyprland binds, neither of which necessarily carries the user's profile path.
  notify = pkgs.writeShellScriptBin "notify" (
    builtins.replaceStrings
      [ "@NOTIFY_SEND@" "@JQ@" ]
      [ "${pkgs.libnotify}/bin/notify-send" "${pkgs.jq}/bin/jq" ]
      (builtins.readFile ./notify.sh)
  );
in
{
  options.anixie.wm.notify = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install `notify`, the sender the notification daemon understands.";
    };

    bin = lib.mkOption {
      type = lib.types.str;
      default = "${notify}/bin/notify";
      description = ''
        The sender command, for modules that need its path rather than the name
        on PATH: the notification daemon, Hyprland binds and systemd timers do
        not necessarily carry the user's profile path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ notify ];
  };
}
