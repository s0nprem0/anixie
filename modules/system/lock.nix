{
  # Session lock. The NixOS modules are used rather than plain packages
  # because programs.hyprlock also registers the PAM service, and
  # services.hypridle wires the daemon's systemd unit PATH to hyprlock.
  programs.hyprlock.enable = true;
  services.hypridle.enable = true;
}
