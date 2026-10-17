{
  pkgs,
  # Consumed by the `lite` shell.
  tools ? pkgs,
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

  # Everyday CLI with no configuration of its own. Mirrors
  # features/shell/tools.nix so `nix develop .#lite` covers the same ground
  # without a rebuild.
  cliTools = with tools; [
    difftastic
    github-cli
    httpie
    jq
    lazygit
    ripgrep
    tmux
    yq
  ];

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
    packages = nixTools ++ cliTools ++ fullStack;
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

  # Everything except the toolchains, for quick shellcheck-style work.
  lite = {
    name = "nix-dots-dev-lite";
    packages = nixTools ++ cliTools;
  };
}
