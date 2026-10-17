{
  services.displayManager.gdm.enable = true;

  # Registers the Hyprland session with the display manager and provides
  # the compositor's security wrapper, portal config and wayland session
  # targets. Compositor configuration lives in modules/home.
  programs.hyprland.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.libinput.enable = true;
}
