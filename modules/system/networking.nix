{
  host,
  user,
  ...
}:

{
  networking = {
    networkmanager = {
      enable = true;

      # Wi-Fi power saving trades a fraction of a watt for latency spikes and,
      # on some Intel radios, dropped links. This machine is usually plugged in,
      # so keep the radio awake.
      wifi.powersave = false;
    };

    hostName = host;

    firewall.interfaces.tailscale0 = {
      allowedTCPPorts = [ 2222 ];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
    };
  };

  # The shell's Tailscale widget can read the daemon's status as this user, and
  # `tailscale up` / `down` work without sudo. The daemon itself starts at boot;
  # the account still has to be logged in with `tailscale up` once.
  #
  # `--ssh` serves shells through Tailscale's own SSH server, so no public
  # sshd is needed. `--accept-routes` makes subnet routes advertised by other
  # tailnet nodes usable here; it does not advertise anything from this host.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    extraSetFlags = [
      "--operator=${user}"
      "--ssh"
      "--accept-routes"
    ];
  };

  # Mosh bootstraps through OpenSSH, not Tailscale SSH, so it needs a real sshd
  # on a separate port. Neither sshd nor Mosh is exposed to the LAN: the
  # firewall admits port 2222 and Mosh's UDP range only on tailscale0. Normal
  # interactive shells can use Tailscale SSH; use Mosh with
  # `mosh --ssh="ssh -p 2222" ${user}@<tailnet-host>`.
  services.openssh = {
    enable = true;
    ports = [ 2222 ];
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  programs.mosh = {
    enable = true;
    openFirewall = false;
  };
}
