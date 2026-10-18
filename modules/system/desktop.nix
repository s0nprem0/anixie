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

  # Removable storage. Without udisks2 nothing mounts a USB stick when it is
  # plugged in — the block layer sees the disk and then it just sits there
  # unmounted — and there is nothing for a file manager to ask, so Thunar
  # reports an error instead of opening the volume. It also handles safe eject
  # and powers the device down rather than yanking it while buffers are unwritten.
  services.udisks2.enable = true;

  # The filesystem side of that: gvfs is what a file manager browses over, so
  # `thunar /run/media/$USER/<label>` resolves to a mounted volume rather than a
  # path that does not exist yet.
  services.gvfs.enable = true;
}
