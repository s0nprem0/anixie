{ pkgs, ... }:

{
  # Runtime tools the shared CLI scripts use. The desktop's common module also
  # carries Quickshell, brightnessctl and wl-clipboard; none of those have a job
  # in a WSL session, but jq is read by the anixie front door and its scripts.
  home.packages = [
    pkgs.jq
  ];
}
