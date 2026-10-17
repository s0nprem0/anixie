{ ... }:

{
  wayland.windowManager.hyprland.settings.exec-once = [
    "mako"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"

    # awww-daemon aborts with SIGABRT if a second instance finds the socket
    # already taken, and it re-runs whenever Hyprland reloads its config, so
    # only start it when it is not already up. Matched on the process name
    # rather than the full command line: pgrep -f would match the shell running
    # this very line and the guard would never start anything.
    "pgrep awww-daemon > /dev/null || awww-daemon"
  ];
}
