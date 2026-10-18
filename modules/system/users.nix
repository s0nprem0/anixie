{
  pkgs,
  ...
}:

{
  security.sudo.wheelNeedsPassword = false;

  users.users.son = {
    isNormalUser = true;
    description = "son";
    shell = pkgs.zsh;
    # Allows a login shell that is not in environment.systemPackages.
    ignoreShellProgramCheck = true;

    extraGroups = [
      "networkmanager"
      "wheel"
      "podman"
      "libvirtd"
      "kvm"
    ];
  };
}
