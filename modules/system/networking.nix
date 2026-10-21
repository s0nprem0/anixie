{
  host,
  user,
  ...
}:

{
  networking.networkmanager.enable = true;
  time.timeZone = "Asia/Manila";
  networking.hostName = host;

  # The shell's Tailscale widget can read the daemon's status as this user, and
  # `tailscale up` / `down` work without sudo. The daemon itself starts at boot;
  # the account still has to be logged in with `tailscale up` once.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    extraSetFlags = [ "--operator=${user}" ];
  };
}
