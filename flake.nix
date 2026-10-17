{
  description = "son's personal NixOS dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ nixpkgs, home-manager, ... }:
    {
      nixosConfigurations.vivobook = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        modules = [
          ./hosts/vivobook

          home-manager.nixosModules.default

          {
            nixpkgs.config.allowUnfree = true;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";

              users.son = import ./modules/home;
            };
          }
        ];
      };

      devShells.x86_64-linux.default = import ./modules/devshell {
        inherit inputs nixpkgs;
        system = "x86_64-linux";
      };
    };
}
