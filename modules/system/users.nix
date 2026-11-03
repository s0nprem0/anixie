{
  config,
  lib,
  pkgs,
  user,
  ...
}:

{
  # sudo does not ask for a password. `nh` elevates itself and keeps the
  # credential for the whole activation, so a rebuild prompts once instead of
  # per step. Reconsider on a machine you do not fully control.
  #
  # The bar's key says so when it is the other way round, and opens this file
  # when clicked. It is not on here, and the module behind it
  # (wm/toggles/passwordless-sudo.sh) stays for a machine that does have
  # NOPASSWD. Rebuild after changing the line below; /etc/sudoers is generated.
  security.sudo.wheelNeedsPassword = false;

  users.users.${user} = {
    isNormalUser = true;
    description = user;
    shell = pkgs.zsh;
    # Allows a login shell that is not in environment.systemPackages.
    ignoreShellProgramCheck = true;

    # Only join groups that an enabled service actually created. A name no
    # module declares is a warning at activation, and on a host without that
    # service — WSL, for one — it is a group that does not exist.
    extraGroups = [
      "wheel"
    ]
    ++ lib.filter (group: builtins.hasAttr group config.users.groups) [
      "docker"
      "kvm"
      "libvirtd"
      "networkmanager"
      "podman"
    ]
    # GameMode's renice needs the user in the `gamemode` group.
    ++ lib.optionals (
      (config.anixie.gaming.enable or false) && (config.anixie.gaming.gamemode or false)
    ) [ "gamemode" ];
  };
}
