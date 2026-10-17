{ ... }:

{
  wayland.windowManager.hyprland.settings.exec-once = [
    "mako"
    "wl-paste --type text --watch cliphist store"
    "wl-paste --type image --watch cliphist store"

    # Push this Hyprland's socket and instance signature into the systemd user
    # manager. Home Manager only does that once, at session start, so a
    # compositor restart otherwise leaves the user manager holding the previous
    # signature and a socket that no longer exists — which is fatal to anything
    # started from it. The bar in particular crash-loops on "Failed to create
    # wl_display" until the session is logged into again.
    #
    # Named explicitly rather than importing the whole environment, which would
    # drag every variable Hyprland happens to be carrying into the user manager.
    "systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP"

    # awww-daemon aborts with SIGABRT if a second instance finds the socket
    # already taken, and it re-runs whenever Hyprland reloads its config, so
    # only start it when it is not already up. Matched on the process name
    # rather than the full command line: pgrep -f would match the shell running
    # this very line and the guard would never start anything.
    "pgrep awww-daemon > /dev/null || awww-daemon"
  ];
}
