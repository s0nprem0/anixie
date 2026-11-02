{
  user,
  ...
}:

{
  # Remote access to the WSL distro. SSH is the baseline; Tailscale gives the
  # distro its own tailnet identity when the Windows-side daemon is not enough.
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraSetFlags = [
      "--operator=${user}"
      "--accept-routes"
    ];
  };

  # The Windows SSH agent is surfaced through WSL via wsl.ssh-agent (enabled
  # in hosts/wsl). Nothing to configure here beyond that.
}
