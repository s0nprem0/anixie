{ pkgs, ... }:

{
  # Shared runtime tools used by several feature modules. Centralized here so
  # each feature does not have to re-declare (and keep in sync) the same
  # dependency. Feature modules may still reference these via `pkgs.<name>` for
  # path substitution in their scripts.
  home.packages = [
    pkgs.brightnessctl
    pkgs.jq
    pkgs.quickshell
    pkgs.wl-clipboard
  ];
}
