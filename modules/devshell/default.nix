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

  # The QML tools — qmllint, qmlformat, qmlls and qmlscene — live in
  # qtdeclarative, the same package the flake's qmllint check builds with, so a
  # hand-run lint and the check cannot disagree about which Qt is being read.
  # quickshell is here for its QML module directory: qmllint does not read
  # QML_IMPORT_PATH, so `import Quickshell` only resolves when the call passes
  # `-I ${pkgs.quickshell}/lib/qt-6/qml`, as the check does.
  #
  # Both are here rather than in the shared CLI list because they are around
  # 700 MiB of Qt: worth it while editing the shell, not worth it on the
  # profile at large, and not needed by the lite shell.
  qmlTools = with pkgs; [
    qt6.qtdeclarative
    quickshell
  ];

  # Everyday CLI with no configuration of its own. Shared with
  # features/shell/tools so `nix develop` and the user profile stay in step.
  cliTools = import ../features/shell/tools/packages.nix { inherit pkgs; };

  # Language runtimes and build toolchains. ~2.3 GiB unpacked, realised only
  # when the default shell is entered, never by `nixos-rebuild switch`. python3
  # is not here: it lives in the shared CLI list, so it is on the user's PATH
  # too, and appears in the lite shell as well.
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
    packages = nixTools ++ shellTools ++ qmlTools ++ cliTools ++ fullStack;
    RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

  # Everything except the toolchains, for quick shellcheck-style work.
  lite = {
    name = "nix-dots-dev-lite";
    packages = nixTools ++ shellTools ++ cliTools;
  };
}
