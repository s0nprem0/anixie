{ pkgs, ... }:

{
  # Podman, rootless, with NO Docker CLI compatibility shim: the `docker`
  # command is the real Docker CLI (see docker.nix) for corporate-standard
  # workflows, while `podman` remains available for rootless/daemonless use.
  # The two engines coexist: dockerd on /var/run/docker.sock (rootful),
  # podman on $XDG_RUNTIME_DIR/podman/podman.sock (rootless).
  virtualisation = {
    containers.enable = true;

    podman = {
      enable = true;
      dockerCompat = false;
      defaultNetwork.settings.dns_enabled = true;
    };

    # QEMU/KVM virtual machines via libvirt.
    libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };
  };

  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    dive
    podman-tui
    podman-compose
    distrobox
    libvirt
  ];
}
