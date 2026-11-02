{
  host,
  user,
  ...
}:

{
  imports = [
    ../../modules/system/dev.nix
    ../../modules/system/docker.nix
    ../../modules/system/nix.nix
    ../../modules/system/secrets.nix
    ../../modules/system/users.nix
  ];

  # NixOS-WSL supplies the kernel, init and the /bin shims. The Windows-managed
  # VHD replaces the disk layout, so the desktop host's boot, firmware,
  # encryption and storage modules have nothing to do here.
  wsl = {
    enable = true;
    defaultUser = user;

    # Let Windows executables (cmd.exe, explorer.exe, wslpath) run from the
    # Linux shell. WSL already writes this into /etc/wsl.conf; registering the
    # binfmt handler is what actually makes a .exe start.
    interop.register = true;
  };

  networking.hostName = host;

  # The distro is installed from this flake's own tarball (see the README), so
  # the first boot already has the right user. Match the release the desktop
  # host declares; WSL still runs the same NixOS tree.
  system.stateVersion = "26.11";
  time.timeZone = "Asia/Manila";
}
