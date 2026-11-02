{
  # The desktop profile in ./default.nix is mostly the window manager and the
  # applications that draw on it. A WSL session has no compositor, no audio
  # server and no seat, so this profile keeps the parts that work over a
  # terminal and leaves the rest to the desktop host.
  imports = [
    ./base.nix

    ../features/cli
    ../features/common/headless.nix

    ../features/shell/git
    ../features/shell/helix
    ../features/shell/neovim
    ../features/shell/opencode
    ../features/shell/tools
    ../features/shell/yazi
    ../features/shell/zsh
  ];
}
