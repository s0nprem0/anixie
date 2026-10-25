{
  description = "son's personal NixOS dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets at rest in the repository, decrypted at activation. Disabled by
    # default (see modules/system/secrets.nix) because it needs an age key that
    # belongs to this machine, not to the flake.
    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Hyprland plugins. The revisions are pinned to the compositor series this
    # flake builds against (0.56): an out-of-tree plugin compiles against
    # Hyprland's internal headers, so a nixpkgs bump that moves Hyprland is a
    # plugin-build break, not a cosmetic one.
    hyprland-preview-share-picker = {
      # Pinned to a revision like every other plugin input, rather than tracking
      # master. The picker is a separate binary, not an in-process plugin, but a
      # floating branch still makes `nix flake update` a larger, less reviewable
      # change than a compositor bump should be.
      url = "git+https://github.com/WhySoBad/hyprland-preview-share-picker?rev=07602efe7a65dcef5399e22c162edf9fc331c46d&submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprland-scroll-overview = {
      url = "github:yayuuu/hyprland-scroll-overview/7ff22457dc016239eff1b19c3ea57de93404b5c9";
      flake = false;
    };

    hyprglass = {
      url = "github:hyprnux/hyprglass/84c1a5ab217101a317d4edaab7fba2efcc1bf346";
      flake = false;
    };

    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors/5a224284872208b5324759d535d65061043725de";
      flake = false;
    };

    hypr-edgehover = {
      url = "github:gfhdhytghd/hypr-edgehover/77b5e1445361b3a1f7b6f03bb4bee15e91229c94";
      flake = false;
    };

    hymission = {
      url = "github:gfhdhytghd/hymission/cff1070f6ee9fbafacca7f7efd76397fe1975510";
      flake = false;
    };

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins/7644cecdb947060682891a0db2a0cdc5c0b9e704";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      # The identity of this machine and its user, stated once here and threaded
      # to every module through specialArgs. Nothing else in the tree hardcodes
      # a username, hostname or flake path.
      host = "2200h";
      user = "son";
      # Relative to the user's home directory, which is what every consumer
      # below prepends. Including the user here would make ~/son/nix-dots.
      flakeDir = "nix-dots";

      # Bound rather than inlined so the checks below can lint what the machine
      # actually installs — the quickshell tree with its placeholders rendered.
      nixos = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";

        specialArgs = {
          inherit
            host
            user
            flakeDir
            inputs
            ;
        };

        modules = [
          ./hosts/vivobook

          inputs.home-manager.nixosModules.default

          inputs.sops-nix.nixosModules.sops

          {
            nixpkgs.config.allowUnfree = true;

            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "hm-backup";

              # Forward the identity so Home Manager modules see the same
              # host/user/flakeDir arguments the NixOS modules do.
              extraSpecialArgs = {
                inherit
                  host
                  user
                  flakeDir
                  inputs
                  ;
              };

              # The secrets module is a Home Manager module, so it cannot sit in
              # the NixOS `modules` list above.
              sharedModules = [
                inputs.sops-nix.homeManagerModules.sops
              ];

              users.${user} = import ./modules/home;
            };
          }
        ];
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # A NixOS configuration belongs to a machine, not to a system, so it
      # lives under the `flake` freeform block rather than in perSystem.
      flake.nixosConfigurations.${host} = nixos;

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

          # The shell the machine installs, after Home Manager has rendered the
          # theme placeholders and assembled the QML tree into one directory.
          # Linting the sources would trip over the @TOKEN@ words; this is the
          # tree Quickshell actually loads.
          quickshellConfig = nixos.config.home-manager.users.${user}.xdg.configFile."quickshell".source;
        in
        {
          devShells = {
            default = pkgs.mkShell shells.default;
            lite = pkgs.mkShell shells.lite;
          };

          # `nix fmt` uses the same formatter as the check below, so a reformat
          # and a failed check cannot disagree about what "formatted" means.
          formatter = pkgs.nixfmt;

          # The shell scripts, checked as written. The @PLACEHOLDER@ words are
          # arguments in command position, so the syntax shellcheck sees is what
          # the installed script runs — a syntax error is caught here instead of
          # at a key press. `-S warning` leaves out the stylistic notes the
          # scripts deliberately ignore (single-quoted `$` for a later eval, and
          # so on) while still failing on anything that is a real mistake.
          checks = {
            shellcheck =
              pkgs.runCommand "shellcheck"
                {
                  nativeBuildInputs = [ pkgs.shellcheck ];
                }
                ''
                  set -eu
                  find ${./modules} -name '*.sh' -print0 |
                    xargs -0 shellcheck -S warning -f gcc
                  touch $out
                '';

            # The anixie group table advertises each command's subcommands for
            # help and completion. The commands' own dispatch cases are what
            # accept them, and a subcommand added to one without the other is
            # invisible. This check compares the two so the table cannot drift.
            anixie-table =
              pkgs.runCommand "anixie-table"
                {
                  nativeBuildInputs = [
                    pkgs.gawk
                    pkgs.gnugrep
                    pkgs.gnused
                    pkgs.findutils
                    pkgs.coreutils
                    pkgs.diffutils
                  ];
                }
                ''
                  set -eu
                  sh ${./modules/features/cli/check-table.sh} ${./.}
                  touch $out
                '';

            # The QML tree has a few pure JavaScript pieces — the JSONC parser,
            # the fuzzy matcher, the state migration seam and the launcher's
            # suggestions — and Node can load them because they export
            # themselves when run outside QML. These are the cases a QML
            # crash-loop would otherwise be the first to find.
            js-tests =
              pkgs.runCommand "js-tests"
                {
                  nativeBuildInputs = [ pkgs.nodejs ];
                }
                ''
                  set -eu
                  cd ${./.}
                  node --test tests/js/*.test.js
                  touch $out
                '';

            # QML has no compiler, so a typo in a binding is found when the shell
            # restarts and crash-loops — or here. The Qt and Quickshell import
            # paths let qmllint resolve every type the shell uses; warnings are
            # plenty (the tree has hundreds of unqualified accesses qmllint
            # cannot know are intentional), so only syntax errors fail the check.
            qmllint =
              pkgs.runCommand "qmllint"
                {
                  nativeBuildInputs = [ pkgs.qt6.qtdeclarative ];
                }
                ''
                  set -eu
                  cd ${quickshellConfig}
                  log="$NIX_BUILD_TOP/qmllint.log"
                  if ! find . -name '*.qml' -print0 |
                    xargs -0 qmllint \
                      -I . \
                      -I ${pkgs.qt6.qtdeclarative}/lib/qt-6/qml \
                      -I ${pkgs.quickshell}/lib/qt-6/qml > "$log" 2>&1; then
                    cat "$log"
                    exit 1
                  fi
                  touch $out
                '';

            # Formatting and dead code. nixfmt is the formatter the devshell
            # carries, so "formatted" is not a matter of taste; statix and
            # deadnix catch the two mistakes nixfmt cannot see. The generated
            # hardware file is left out of the linters that would rewrite its
            # idiomatic one-key-at-a-time shape, but it is still format-checked.
            formatting =
              pkgs.runCommand "formatting"
                {
                  nativeBuildInputs = [
                    pkgs.nixfmt
                    pkgs.statix
                    pkgs.deadnix
                  ];
                }
                ''
                  set -eu
                  cd ${./.}
                  find . -name '*.nix' -print0 | xargs -0 nixfmt --check
                  statix check --ignore 'hosts/*/hardware-configuration.nix' .
                  find . -name '*.nix' -not -name 'hardware-configuration.nix' -print0 |
                    xargs -0 deadnix --fail
                  touch $out
                '';
          };
        };
    };
}
