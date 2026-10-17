{ ... }:

{
  wayland.windowManager.hyprland.settings.exec-once = [
    "mako"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"
    "awww-daemon"
  ];
}
