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
        { system, ... }:
        let
          # The dev shell and the checks want the same unfree allowance the
          # machine has (unrar is in the shared CLI list), or `nix develop` and
          # `nix flake check` refuse to evaluate before they do anything.
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };

          # Both shells share one package list, split into tiers by cost.
          shells = import ./modules/devshell { inherit pkgs; };
        in
        {
          devShells = {
            default = pkgs.mkShell shells.default;
            lite = pkgs.mkShell shells.lite;
          };

          # The shell scripts, checked as written. The @PLACEHOLDER@ words are
          # arguments in command position, so the syntax shellcheck sees is what
          # the installed script runs — a syntax error is caught here instead of
          # at a key press. `-S warning` leaves out the stylistic notes the
          # scripts deliberately ignore (single-quoted `$` for a later eval, and
          # so on) while still failing on anything that is a real mistake.
          checks.shellcheck =
            pkgs.runCommand "shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                set -eu
                find ${./modules} -name '*.sh' -print0 |
                  xargs -0 shellcheck -S warning -f gcc
                shellcheck -S warning -f gcc ${./revert-hyprland.sh}
                touch $out
              '';
        };
    };
}
