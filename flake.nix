{
  description = "son's personal NixOS dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Community packaging of the ArtCraft Crafting Apps (PhotoCraft and
    # friends) from their upstream release tarballs. Not in nixpkgs.
    nix-craftapps = {
      url = "github:olafkfreund/nix-craftapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # A NixOS configuration belongs to a machine, not to a system, so it
      # lives under the `flake` freeform block rather than in perSystem.
      flake.nixosConfigurations.vivobook = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          ./hosts/vivobook

          inputs.home-manager.nixosModules.default

          # Provides programs.craftapps at the system level, which the machine
          # uses only to link /usr/share/fonts for the apps (they bypass
          # fontconfig). The apps themselves are installed per-user below.
          inputs.nix-craftapps.nixosModules.default

          {
            nixpkgs.config.allowUnfree = true;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";

              # The apps are Home Manager modules, so they cannot sit in the
              # NixOS `modules` list above.
              sharedModules = [ inputs.nix-craftapps.homeManagerModules.default ];

              users.son = import ./modules/home;
            };
          }
        ];
      };

      perSystem =
        { pkgs, ... }:
        let
          # Both shells share one package list, split into tiers by cost.
          shells = import ./modules/devshell { inherit pkgs; };
        in
        {
          devShells = {
            default = pkgs.mkShell shells.default;
            lite = pkgs.mkShell shells.lite;
          };
        };
    };
}
