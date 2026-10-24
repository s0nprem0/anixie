{
  config,
  lib,
  pkgs,
  ...
}:

let
  # greetd starts the greeter with a minimal environment, so tuigreet cannot
  # rely on XDG_DATA_DIRS to find the sessions. The display-manager module
  # builds the same directory the plain session entries point at.
  waylandSessions = "${config.services.displayManager.sessionData.desktops}/share/wayland-sessions";

  tuigreet = lib.concatStringsSep " " [
    "${pkgs.tuigreet}/bin/tuigreet"
    "--time"
    "--battery"
    "--remember"
    "--remember-user-session"
    "--asterisks"
    "--sessions"
    (lib.escapeShellArg waylandSessions)
    "--power-shutdown"
    (lib.escapeShellArg "${pkgs.systemd}/bin/systemctl poweroff")
    "--power-reboot"
    (lib.escapeShellArg "${pkgs.systemd}/bin/systemctl reboot")
  ];
in
{
  # ddcutil talks to external monitors over /dev/i2c-*. The NixOS module loads
  # i2c-dev and its udev rule grants the logged-in seat access, which is what
  # `monitors brightness` needs when focus is on an HDMI/DP display.
  hardware.i2c.enable = true;

  # The compositor and the shell both need OpenGL. Kept here rather than in
  # gaming.nix so turning Steam off does not take the graphics stack with it.
  hardware.graphics.enable = true;

  services = {
    # greetd owns PAM and the VT; tuigreet is just the terminal UI it starts.
    # GDM brought the GNOME session stack along to draw one login prompt.
    greetd = {
      enable = true;

      # Ties the service to the TTY and keeps systemd's boot log from writing
      # over the TUI.
      useTextGreeter = true;

      settings.default_session = {
        command = tuigreet;
        user = "greeter";
      };
    };

    libinput.enable = true;

    # Removable storage. Without udisks2 nothing mounts a USB stick when it is
    # plugged in — the block layer sees the disk and then it just sits there
    # unmounted — and there is nothing for a file manager to ask, so Thunar
    # reports an error instead of opening the volume. It also handles safe eject
    # and powers the device down rather than yanking it while buffers are unwritten.
    udisks2.enable = true;

    # The filesystem side of that: gvfs is what a file manager browses over, so
    # `thunar /run/media/$USER/<label>` resolves to a mounted volume rather than a
    # path that does not exist yet.
    gvfs.enable = true;

    # Thunar does not decode thumbnails itself: it asks this D-Bus service,
    # which ships image, video, PDF and RAW thumbnailers. Without it every
    # picture in the file manager is a generic icon.
    tumbler.enable = true;

    # NixOS turns Speech Dispatcher on for every graphical desktop, on the
    # assumption that a screen reader may need it. There is none here, and it is
    # not free: the package drags in the Mbrola voice set (~645 MiB), the daemon
    # is D-Bus-activated into every session, and mbrola keeps a synthesis process
    # resident once something has spoken. Set false rather than left at the
    # default; re-enable it if Orca or an app's read-aloud feature is wanted.
    speechd.enable = false;
  };

  # Registers the Hyprland sessions (plain and UWSM) with the display manager
  # and provides the compositor's security wrapper, portal config and wayland
  # session targets. UWSM owns the systemd session lifecycle, so the Home
  # Manager module's own integration is turned off there.
  programs.hyprland = {
    enable = true;
    withUWSM = true;
  };
}
