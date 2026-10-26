{
  lib,
  user,
  ...
}:

{
  imports = [
    ../features
  ];

  # NixOS ships no /etc/profile.d/xdg.sh, unlike Debian or Arch, so the XDG
  # variables are otherwise unset. Enabling Home Manager's XDG module exports
  # them to both the login shell and the systemd user manager, and makes every
  # program that supports it prefer ~/.config and ~/.local/state over a dotfile
  # in the home directory. `localBinInPath` also puts ~/.local/bin on PATH.
  xdg = {
    enable = true;
    localBinInPath = true;
  };

  home = {
    username = user;
    homeDirectory = "/home/${user}";
    stateVersion = "26.11";

    # Let modules that have both layouts use the XDG one (readline, npm,
    # atuin's logs, GTK2 and friends). This is a no-op for programs that only
    # support the legacy path.
    preferXdgDirectories = true;

    # ~/.local/bin is on PATH above, but nothing creates it on a fresh home.
    activation.ensureLocalBin = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p "$HOME/.local/bin"
    '';
  };
}
