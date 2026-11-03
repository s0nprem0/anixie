_:

{
  # Docker Engine running inside the WSL distro itself. WSL2 ships a real
  # Linux kernel and systemd, so dockerd runs here without a Windows-side
  # Docker Desktop; the `docker` group created by this module is what lets
  # the default user talk to the daemon.
  virtualisation.docker = {
    enable = true;

    # WSL and the desktop both accumulate dangling images and stopped containers
    # across rebuilds; prune them on a schedule so the store-backed VHD does
    # not fill up unnoticed.
    autoPrune = {
      enable = true;
      dates = "weekly";
    };
  };
}
