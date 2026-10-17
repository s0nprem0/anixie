{
  pkgs,
  ...
}:

{
  home.packages = [ pkgs.hyprsunset ];

  # hyprsunset 0.4 reads ~/.config/hypr/hyprsunset.conf and only understands
  # profile blocks. The old sunset.conf with its top-level bezier/duration keys
  # was silently ignored, which is why it logged "Loaded 0 profiles".
  xdg.configFile."hypr/hyprsunset.conf".text = ''
    # Warms the display colour temperature towards 4500K so late-night use is
    # easier on the eyes. Add profiles with a `time` key to schedule a warmer
    # filter at night and a neutral one by day.
    profile {
      time = 00:00
      temperature = 4500
    }
  '';

  # Hypridle owns the display power management, so hyprsunset only has to
  # attach itself to the graphical session. It is a long-running daemon rather
  # than a one-shot, so the unit is `simple`, and it restarts itself because the
  # first attempt at session start can abort while Hyprland's IPC socket is
  # still coming up.
  systemd.user.services.hyprsunset = {
    Unit.Description = "hyprsunset blue light filter";
    Unit.After = [ "graphical-session-pre.target" ];
    Service.ExecStart = "${pkgs.hyprsunset}/bin/hyprsunset";
    Service.Type = "simple";
    Service.Restart = "on-failure";
    Service.RestartSec = 5;
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
