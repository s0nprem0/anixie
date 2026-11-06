{
  lib,
  pkgs,
  inputs ? { },
  ...
}:

let
  # `snapshot` is native in alexie now; the timer calls the binary directly.
  alexiePkg = inputs.alexie.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # btrfs-progs for the command line, rsync for restore.
  environment.systemPackages = [
    pkgs.btrfs-progs
    pkgs.rsync
  ];

  # One snapshot a day, tagged "auto". The timer is persistent, so a machine that
  # was off when it was due takes one at the next boot rather than skipping it.
  systemd = {
    services.anixie-snapshot = {
      description = "Btrfs snapshot of /home";
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${alexiePkg}/bin/alexie snapshot create auto";
      # The timer is what starts this; a boot-time catch-up on its own is wrong.
      unitConfig.ConditionPathIsMountPoint = "/home";
    };

    timers.anixie-snapshot = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };
}
