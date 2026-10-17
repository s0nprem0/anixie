{ pkgs, ... }:

{
  # Podman with Docker CLI compatibility. `docker` on PATH is podman under the
  # hood, so Dockerfiles and images work unchanged; no root daemon runs.
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  # QEMU/KVM virtual machines via libvirt.
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
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
