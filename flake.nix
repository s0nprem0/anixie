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

    # The WSL host reuses the parts of this flake that make sense on Windows
    # (Nix settings, the user, Home Manager's CLI and shell modules) while the
    # module supplies WSL's kernel, boot shims and default-user handling.
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
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

    # alexie: Rust daemon + CLI replacing anixie's shell tooling. Optional;
    # enabled via anixie.daemon.enable. Lives in a separate repo.
    alexie = {
      url = "github:s0nprem0/alexie";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprglass = {
      url = "github:hyprnux/hyprglass/85b8a8ed8431d7b6f1ef8dad8ae0470d8ea7f291";
      flake = false;
    };

    hypr-dynamic-cursors = {
      url = "github:VirtCode/hypr-dynamic-cursors/2a8d0b735328d874a78ca93b2f201649f712a74a";
      flake = false;
    };

    hypr-edgehover = {
      url = "github:gfhdhytghd/hypr-edgehover/c50461a109cfb71c81c0adc96fa24e754f323e21";
      flake = false;
    };

    hymission = {
      url = "github:gfhdhytghd/hymission/46348feebd65242c3ef65353292e074d85393200";
      flake = false;
    };

    hyprland-scroll-overview = {
      url = "github:yayuuu/hyprland-scroll-overview/a8dcca6fe3ddc2164774cb6925bc67c0b974a78f";
      flake = false;
    };

    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins/d2427d4d15b36df40468f5a58bbd67cdba19835d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    voidstrap = {
      url = "git+https://github.com/KloBraticc/Voidstrap?submodules=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    let
      # The identity of the desktop and its user, stated once here and threaded
      # to every module through specialArgs. The WSL host reuses the user and
      # flake path but has a hostname of its own.
      desktopHost = "2200h";
      wslHost = "wsl";
      user = "son";
      # Relative to the user's home directory, which is what every consumer
      # below prepends. Including the user here would make ~/son/nix-dots.
      flakeDir = "anixie";

      # One system builder for both hosts. The desktop and WSL differ in which
      # host module and Home Manager profile they import, not in how Nix,
      # Home Manager or the secrets module are wired.
      mkNixos =
        {
          host,
          home,
          modules,
        }:
        inputs.nixpkgs.lib.nixosSystem {
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

                # The secrets module is a Home Manager module, so it cannot sit
                # in the NixOS `modules` list above.
                sharedModules = [
                  inputs.sops-nix.homeManagerModules.sops
                ];

                users.${user} = import home;
              };
            }
          ]
          ++ modules;
        };

      # Bound rather than inlined so the checks below can lint what the machine
      # actually installs — the quickshell tree with its placeholders rendered.
      nixos = mkNixos {
        host = desktopHost;
        home = ./modules/home;
        modules = [ ./hosts/vivobook ];
      };

      # WSL keeps the same user and rebuild entry point. Its host module leaves
      # out the desktop stack (Hyprland, greetd, hardware, boot loader) and the
      # NixOS-WSL module supplies WSL's kernel and boot shims instead.
      wsl = mkNixos {
        host = wslHost;
        home = ./modules/home/wsl.nix;
        modules = [
          inputs.nixos-wsl.nixosModules.default
          ./hosts/wsl
        ];
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # A NixOS configuration belongs to a machine, not to a system, so it
      # lives under the `flake` freeform block rather than in perSystem.
      flake.nixosConfigurations = {
        ${desktopHost} = nixos;
        ${wslHost} = wsl;
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
          # nixfmt-tree is the directory-aware wrapper around nixfmt: a bare
          # `nix fmt` walks the tree instead of reading stdin, which is what the
          # deprecation warning below asks for.
          formatter = pkgs.nixfmt-tree;

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
                  # monitors is assembled from parts at build time, so check
                  # the same concatenation the build installs rather than the
                  # fragments on their own.
                  cat ${./modules/features/wm/display/monitors}/*.bash |
                    shellcheck -S warning -f gcc -
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

            # The theming scripts keep their state, colour maths and template
            # rendering in small shell libraries. These tests exercise those
            # pieces directly, without needing a running desktop.
            shell-tests =
              pkgs.runCommand "shell-tests"
                {
                  nativeBuildInputs = [
                    pkgs.bash
                    pkgs.coreutils
                    pkgs.findutils
                    pkgs.gawk
                    pkgs.gnugrep
                    pkgs.gnused
                    pkgs.jq
                    pkgs.util-linux
                  ];
                }
                ''
                  set -eu
                  cd ${./.}
                  for test in tests/shell/*.test.sh; do
                    bash "$test"
                  done
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
