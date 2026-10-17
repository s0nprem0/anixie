# Single source of truth for the everyday CLI tools. Consumed by ./default.nix
# (installed into the user profile) and by the devshells, so `nix develop`
# covers the same ground without the two lists drifting apart.
{ pkgs, ... }:

with pkgs;
[
  # Monitoring. btop is also what the reference bar's CPU readout launches.
  btop
  duf
  dust
  procs

  # Archives and files.
  file
  unzip
  zip

  # Hardware, which a laptop is worth being able to inspect.
  pciutils
  usbutils

  difftastic
  github-cli
  gnumake

  # GNUPGHOME is already set in the zsh session variables, so signing is
  # intended here; the binary was simply never pulled in.
  gnupg

  httpie
  jq

  # The repo's .envrc is `use flake`; nix-direnv is what makes that cached
  # rather than re-evaluating the flake on every prompt.
  nix-direnv

  lazydocker
  lazygit
  nix-output-monitor
  ripgrep
  sd
  tealdeer
  tmux
  wget
  yq
]
