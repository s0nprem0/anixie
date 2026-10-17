{
  config,
  ...
}:

{
  imports = [
    ../features
  ];

  home.username = "son";
  home.homeDirectory = "/home/son";

  # NixOS ships no /etc/profile.d/xdg.sh, so unlike Debian or Arch it leaves
  # these unset. Home Manager resolves its own paths from xdg.* but does not
  # export them, so anything reading $XDG_CACHE_HOME or $XDG_STATE_HOME gets an
  # empty string. Export Home Manager's values so the two cannot drift.
  home.sessionVariables = {
    XDG_CONFIG_HOME = config.xdg.configHome;
    XDG_CACHE_HOME = config.xdg.cacheHome;
    XDG_DATA_HOME = config.xdg.dataHome;
    XDG_STATE_HOME = config.xdg.stateHome;
  };

  home.stateVersion = "26.05";
}
