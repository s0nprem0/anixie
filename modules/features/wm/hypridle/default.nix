# The daemon is enabled in modules/system/lock.nix; this supplies its config.
{ pkgs, ... }:

let
  # Hypridle's suspend listener runs this. On mains the machine may be building,
  # downloading or serving something, so it should stay awake; battery idle is
  # the case the listener is for. Any online AC supply is enough to skip.
  suspendIfOnBattery = pkgs.writeShellScript "suspend-if-on-battery" ''
    for ac in /sys/class/power_supply/AC*/online; do
      [ -e "$ac" ] || continue
      [ "$(cat "$ac")" = 1 ] && exit 0
    done

    exec ${pkgs.systemd}/bin/systemctl suspend
  '';
in
{
  xdg.configFile."hypr/hypridle.conf".text =
    builtins.replaceStrings [ "@SUSPEND@" ] [ "${suspendIfOnBattery}" ] (
      builtins.readFile ./hypridle.conf
    );
}
