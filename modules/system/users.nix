{
  pkgs,
  ...
}:

{
  # sudo asks for a password. Anything that reaches this session — a stolen
  # laptop, an unlocked screen, a shell in a notification — is a session that
  # cannot already do anything to the machine, and the cost is one prompt at the
  # end of a rebuild: `nh` elevates itself, so it asks once and keeps it for the
  # activation rather than asking for every step.
  #
  # The bar's key says so when it is the other way round. It is not on here, and
  # the module behind it (wm/toggles/passwordless-sudo.sh) stays for a machine
  # that does have NOPASSWD.
  security.sudo.wheelNeedsPassword = true;

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
