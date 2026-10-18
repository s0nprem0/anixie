{
  pkgs,
  ...
}:

let
  # Nix tooling. Always cheap, so both shells carry it.
  nixTools = with pkgs; [
    deadnix
    nil
    nixfmt
    statix
  ];

  # The shell scripts the desktop modules install — the screenshot and recording
  # commands, the launcher, the reminder — are shellcheck's subject. Nothing ran
  # it before, so the two `shellcheck disable` comments already in shot.sh were
  # advice nobody was taking.
  shellTools = with pkgs; [
    shellcheck
  ];

  # Everyday CLI with no configuration of its own. Shared with
  # features/shell/tools so `nix develop` and the user profile stay in step.
  cliTools = import ../features/shell/tools/packages.nix { inherit pkgs; };

  # Language runtimes and build toolchains. ~2.3 GiB unpacked, realised only
  # when the default shell is entered, never by `nixos-rebuild switch`.
  fullStack = with pkgs; [
    cargo
    clippy
    clang
    clang-tools
    cmake
    gnumake
    nodejs
    openssl
    pkg-config
    python3
    rustc
    rustfmt
    uv
  ];
in
{
  # Language runtimes and build toolchains. Lets rust-analyzer resolve the
  # standard library, matching the `nil` LSP.
  default = {
    name = "nix-dots-dev";
    packages = nixTools ++ shellTools ++ cliTools ++ fullStack;
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

  # Everything except the toolchains, for quick shellcheck-style work.
  lite = {
    name = "nix-dots-dev-lite";
    packages = nixTools ++ shellTools ++ cliTools;
  };
}
