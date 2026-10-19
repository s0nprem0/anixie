{ pkgs, ... }:

{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];

      trusted-users = [
        "root"
        "@wheel"
      ];

      # Hard links identical files within the store instead of writing a second
      # copy. The helix config and the theme files are shared by several builds,
      # so this is where the deduplication actually pays.
      auto-optimise-store = true;
    };

    # Old generations are the store's growth. Nothing reclaimed them, so the
    # weekly sweep keeps a month of rollbacks before pruning the rest.
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };

    # The root channel was a stale 26.05 while the machine runs 26.11, and the
    # default search path pointed <nixpkgs> at it, so a bare `nix-shell`, `nix
    # run` or `nix-env` resolved against the old tree. flake:nixpkgs goes
    # through the registry to the nixpkgs the system was actually built from.
    nixPath = [ "nixpkgs=flake:nixpkgs" ];
    channel.enable = false;
  };

  # A flake pins nixpkgs, so security updates arrive only when someone runs
  # `nix flake update` and rebuilds. The bar's badge says the tree is newer than
  # the system; nothing says the tree itself is stale. This does, once a week,
  # and does nothing else — updating and rebuilding stays a deliberate act.
  systemd.user.services.flake-age = {
    description = "Notice when the pinned flake is a month old";
    serviceConfig.Type = "oneshot";
    script = ''
      lock="$HOME/nix-dots/flake.lock"
      [ -f "$lock" ] || exit 0

      days=$(( ( $(date +%s) - $(stat -c %Y "$lock") ) / 86400 ))
      [ "$days" -ge 30 ] || exit 0

      ${pkgs.libnotify}/bin/notify-send -a NixOS \
        "Updates are $days days old" "nix flake update && anixie update"
    '';
  };

  systemd.user.timers.flake-age = {
    description = "Weekly check on the flake's age";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
