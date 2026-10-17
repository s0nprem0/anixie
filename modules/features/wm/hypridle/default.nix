# The daemon is enabled in modules/system/lock.nix; this supplies its config.
{
  xdg.configFile."hypr/hypridle.conf".text = builtins.readFile ./hypridle.conf;
}
