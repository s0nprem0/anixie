{
  pkgs,
  ...
}:

{
  home.packages = [ pkgs.hyprsunset ];

  xdg.configFile."hypr/sunset.conf".text = ''
    # Warms the display colour temperature towards 4500K so late-night use is
    # easier on the eyes. Applied on session start by the systemd unit below.
    bezier = 0.0, 0.0, 1.0, 1.0
    duration = 0.5
    temperature = 4500
    gamma = 1.0
  '';

  # Hypridle owns the display power management, so hyprsunset only has to
  # attach itself to the graphical session.
  systemd.user.services.hyprsunset = {
    Unit.Description = "hyprsunset blue light filter";
    Service.ExecStart = "${pkgs.hyprsunset}/bin/hyprsunset";
    Service.Type = "oneshot";
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
