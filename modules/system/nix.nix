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
}
