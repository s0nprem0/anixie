# Single source of truth for the everyday CLI tools. Consumed by ./default.nix
# (installed into the user profile) and by the devshells, so `nix develop`
# covers the same ground without the two lists drifting apart.
{ pkgs, ... }:

with pkgs;
[
  # Monitoring. btop is also what the reference bar's CPU readout launches.
  btop
  fastfetch
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

  # Key injection, for the emoji picker to type its choice through. The picker
  # itself is `emoji` (see features/wm/emoji); bemoji used to be here for it, and
  # went with the fuzzel it drew its list through.
  wtype

  # The notification client. The daemon that draws what it sends is the shell's.
  libnotify

  difftastic
  github-cli
  gnumake

  # The interpreter on PATH, for scripts and one-off venvs. uv, which builds the
  # venvs the skills use, stays in the dev shell with the other toolchains.
  python3

  # The other interpreter worth having without a project: php -S serves a
  # directory, and the CLI covers one-off scripts. Composer comes from the same
  # PHP so its platform check matches the interpreter on PATH.
  php
  php.packages.composer

  # GNUPGHOME is already set in the zsh session variables, so signing is
  # intended here; the binary was simply never pulled in.
  gnupg

  # The CLI halves of the secrets path: sops edits the encrypted file, age holds
  # the key it is encrypted to. sops-nix itself does the activation-time
  # decryption (see modules/system/secrets.nix).
  sops
  age

  httpie
  jq

  # direnv (and its nix-direnv caching) comes from programs.direnv in
  # modules/system/dev.nix, which installs both.

  lazydocker
  lazygit
  # The rebuild helper. NH_FLAKE is exported alongside it, so `nh os switch`
  # finds ~/nix-dots without being told.
  nh
  nix-output-monitor
  ripgrep
  sd
  tealdeer
  tmux
  wget
  yq

  # Everyday shell: the alternatives that change what typing feels like — fuzzy
  # finding, a listing with icons, a directory jump, and fast file search.
  fd
  eza
  fzf
  zoxide

  # Diagnostics for when something is wrong: the hardware, the IO, the power, and
  # the network in the order they are usually suspected.
  lshw
  inxi
  iotop
  powertop
  psmisc
  dnsutils
  iperf3
  nmap
  netcat-openbsd
  socat

  # Archives the file manager cannot open on its own. p7zip provides 7z; the
  # package is old, so `_7zz` is the drop-in if it is ever marked insecure.
  p7zip
  unrar

  # The GPU. One integrated card on this laptop, so the basic view is enough.
  nvtopPackages.full
]
