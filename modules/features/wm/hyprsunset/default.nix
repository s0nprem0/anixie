{
  pkgs,
  ...
}:

{
  home.packages = [ pkgs.hyprsunset ];

  # hyprsunset 0.4 reads ~/.config/hypr/hyprsunset.conf and only understands
  # profile blocks. The old sunset.conf with its top-level bezier/duration keys
  # was silently ignored, which is why it logged "Loaded 0 profiles".
  #
  # Profiles activate at their time and override each other, with the most
  # recent activation winning. A single profile at 00:00 therefore means "always
  # on", which is not what a night filter should do: it tinted the display all
  # day. These two turn it off by day and warm it after dark.
  xdg.configFile."hypr/hyprsunset.conf".text = ''
    # Daytime: 6500K, the neutral white. Stated as a temperature rather than the
    # identity matrix so the bar's night light indicator can tell which way it is
    # in: hyprsunset reports its temperature, and identity leaves that reading at
    # whatever it was instead of clearing it, so a day spent after a warm night
    # would still report itself as tinted.
    profile {
      time = 06:00
      temperature = 6500
    }

    # Evening onwards, and wrapping through to early morning.
    profile {
      time = 21:00
      temperature = 3500
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
