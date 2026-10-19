{ pkgs, ... }:

let
  # Kept on the root btrfs subvolume, never inside /home: a snapshot of a
  # subvolume placed within itself is exactly what btrfs refuses to make.
  dest = "/var/lib/anixie/snapshots";

  snapshot = pkgs.writeShellScriptBin "snapshot" (
    builtins.replaceStrings
      [
        "@DEST@"
        "@KEEP@"
        "@BTRFS@"
        "@SUDO@"
        "@RSYNC@"
      ]
      [
        dest
        "20"
        "${pkgs.btrfs-progs}/bin/btrfs"
        # The setuid wrapper, not the store copy: only the wrapper under
        # /run/wrappers is owned by root, and the store has no setuid bits.
        "/run/wrappers/bin/sudo"
        "${pkgs.rsync}/bin/rsync"
      ]
      (builtins.readFile ./snapshot.sh)
  );
in
{
  # btrfs-progs for the command line, rsync for restore.
  environment.systemPackages = [
    snapshot
    pkgs.btrfs-progs
    pkgs.rsync
  ];

  # One snapshot a day, tagged "auto". The timer is persistent, so a machine that
  # was off when it was due takes one at the next boot rather than skipping it.
  systemd = {
    services.anixie-snapshot = {
      description = "Btrfs snapshot of /home";
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${snapshot}/bin/snapshot create auto";
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
