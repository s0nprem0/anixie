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
  services = {
    # greetd owns PAM and the VT; tuigreet is just the terminal UI it starts.
    # GDM brought the GNOME session stack along to draw one login prompt.
    displayManager = {
      # Used by autologin and tooling, not by greetd: the greeter lists every
      # session and remembers the last choice in /var/cache/tuigreet.
      defaultSession = "hyprland-uwsm";
    };

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

    xserver.xkb = {
      layout = "us";
      variant = "";
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
