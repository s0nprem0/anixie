{
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  
  programs.hyprland = {
   enable = true;
   xwayland.enable = true;
  };

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.libinput.enable = true;
}
