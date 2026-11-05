{
  host,
  pkgs,
  user,
  ...
}:

{
  imports = [
    ../../modules/system/dev.nix
    ../../modules/system/docker.nix
    ../../modules/system/fonts.nix
    ../../modules/system/memory.nix
    ../../modules/system/nix.nix
    ../../modules/system/remote.nix
    ../../modules/system/secrets.nix
    ../../modules/system/users.nix
  ];

  # NixOS-WSL supplies the kernel, init and the /bin shims. The Windows-managed
  # VHD replaces the disk layout, so the desktop host's boot, firmware,
  # encryption and storage modules have nothing to do here.
  programs.gnupg.agent.pinentryPackage = pkgs.pinentry-curses;

  # Local SSH agent so encrypted keys are cached and the passphrase is only
  # asked once per session, instead of depending on the Windows bridge.
  programs.ssh.startAgent = true;

  # WSL networking is owned by Windows; a NixOS firewall here can only block
  # forwarded traffic (localhost/Windows host) without adding any real isolation.
  networking.firewall.enable = false;

  wsl = {
    enable = true;
    defaultUser = user;

    # Register the binfmt handler so a .exe can start at all; without it even
    # an absolute /mnt/c path fails. Windows directories stay off $PATH (below),
    # so call binaries by absolute path, e.g. /mnt/c/Windows/System32/cmd.exe.
    interop.register = true;

    # Keep Windows' directories off $PATH. Otherwise every command lookup has
    # to scan the 9p mounts under /mnt/c, which costs ~0.2s the first time zsh
    # builds its command hash on each start. Both switches are needed:
    # `includePath` filters the login environment, `wslConf` stops WSL itself
    # from appending them. Set them back to true to restore interop by bare
    # name and accept that cost.
    interop.includePath = false;
    wslConf.interop.appendWindowsPath = false;

    # systemd is the init; keep it explicit so a future WSL default change
    # cannot silently disable the service manager the rest of this config
    # assumes (dockerd, tailscaled, sshd, oomd).
    wslConf.boot.systemd = true;

    # Use the Windows host's GPU drivers for WSLg applications.
    useWindowsDriver = true;

    # Reuse the Windows SSH agent (and its keys) inside the distro.
    ssh-agent.enable = false;

    # USB/IP passthrough for devices plugged into the Windows host.
    usbip.enable = true;
  };

  networking.hostName = host;

  # The distro is installed from this flake's own tarball (see the README), so
  # the first boot already has the right user. Match the release the desktop
  # host declares; WSL still runs the same NixOS tree.
  system.stateVersion = "26.11";
  time.timeZone = "Asia/Manila";
}
