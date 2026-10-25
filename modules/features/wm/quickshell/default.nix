{
  config,
  lib,
  pkgs,
  ...
}:

let
  render = config.anixie.theme.template.render;

  # Where the `theme` command records the live choice, and the resolved palette
  # a wallpaper-derived theme leaves beside it. A restarted shell reads both: the
  # name is not in the embedded list, so it needs the colours too.
  themeState = "${config.anixie.theme.stateDir}/current";
  themePalette = "${config.anixie.theme.stateDir}/palette.json";

  # Focus mode's blocked app ids, rendered where FocusHost can read them without
  # depending on the user's profile. The state (whether a block is running) lives
  # in the state directory, not here.
  focusConfig = pkgs.writeText "focus.json" (
    builtins.toJSON {
      blocked = config.anixie.wm.focus.blockedClasses;
      defaultMinutes = config.anixie.wm.focus.defaultMinutes;
    }
  );

  # The whole palette list goes into the shell, not just the selected one, so it
  # can switch without a rebuild. JSON is a valid QML object literal, so the file
  # the `theme` command reads in the shell is the one that feeds this build.
  theme = pkgs.writeText "Theme.qml" (
    builtins.replaceStrings
      [ "@PALETTES_JSON@" "@DEFAULT_THEME@" "@THEME_STATE@" "@THEME_PALETTE@" ]
      [
        (builtins.toJSON config.anixie.theme.palettes)
        config.anixie.theme.theme
        themeState
        themePalette
      ]
      (render ./Theme.qml)
  );

  # The low-battery warning's sender and shell paths, rendered in the same pass as
  # the theme so the QML can call them without depending on the shell service's
  # PATH (see Ui/PowerAlert.qml and the two placeholders below).
  powerAlert = pkgs.writeText "PowerAlert.qml" (render ./Ui/PowerAlert.qml);

  # The lock screen needs fprintd-list and the hyprlock fallback by full path:
  # the shell service's PATH is the user manager's, not the profile's.
  lockHost = pkgs.writeText "LockHost.qml" (render ./Ui/LockHost.qml);

  # The clock's calendar panel carries the calendar-events path, so the shell
  # does not have to trust the user manager's PATH for it. Rendered in the same
  # pass as the theme, which the panel also reads.
  clock = pkgs.writeText "Clock.qml" (
    builtins.replaceStrings [ "@CALENDAR_EVENTS@" ] [ config.anixie.wm.calendar.bin ] (
      render ./components/Clock.qml
    )
  );

  # The notification display choice is read by the shell's window loop; the
  # panel writes it to NotificationHost, and this is the initial default.
  shell = pkgs.writeText "shell.qml" (render ./shell.qml);

  # NotificationHost carries the build-time default display mode; the panel
  # overrides it at runtime and persists the choice beside the quiet state.
  notificationHost = pkgs.writeText "NotificationHost.qml" (render ./Ui/NotificationHost.qml);

  # `loginctl lock-session` and anything else that uses logind's Lock signal do
  # not know the lock lives in the shell. One small listener turns that signal
  # into the same IPC call the key uses, filtered to this session.
  lockSignal = pkgs.writeShellScript "anixie-lock-signal" (
    builtins.replaceStrings
      [ "@BUSCTL@" "@DBUS_MONITOR@" "@STDBUF@" "@QUICKSHELL@" "@HYPRCTL@" ]
      [
        "${pkgs.systemd}/bin/busctl"
        "${pkgs.dbus}/bin/dbus-monitor"
        "${pkgs.coreutils}/bin/stdbuf"
        "${pkgs.quickshell}/bin/quickshell"
        "${pkgs.hyprland}/bin/hyprctl"
      ]
      (builtins.readFile ./lock-signal.sh)
  );

  # Quickshell resolves `import "components"` relative to the directory holding
  # shell.qml. Home Manager deploys every xdg.configFile entry as a separate
  # symlink, which would scatter the QML tree across the store, so the config is
  # assembled into one real directory first.
  shellConfig = pkgs.runCommand "quickshell-config" { } ''
    cp -rL ${./.} $out
    chmod -R u+w $out
    cp ${shell} $out/shell.qml
    cp ${theme} $out/Theme.qml
    cp ${notificationHost} $out/Ui/NotificationHost.qml
    cp ${clock} $out/components/Clock.qml
    cp ${powerAlert} $out/Ui/PowerAlert.qml
    cp ${lockHost} $out/Ui/LockHost.qml
    cp ${focusConfig} $out/focus.json
    rm -f $out/default.nix
  '';
in
{
  options.anixie.wm.quickshell.notificationsDisplay = lib.mkOption {
    type = lib.types.enum [
      "focused"
      "all"
    ];
    default = "focused";
    description = ''
      Which outputs show notification popups. `focused` follows the active
      monitor; `all` draws the same stack on every connected output.
    '';
  };

  options.anixie.wm.quickshell.position = lib.mkOption {
    type = lib.types.enum [
      "top"
      "bottom"
      "left"
      "right"
    ];
    default = "top";
    description = ''
      Which edge the bar sits on. A side bar becomes a column and its modules
      drop their labels, since a 28px-wide bar has room for an icon only.

      This is the default for a fresh state; `bar position` saves a runtime
      override in the writable bar layout, so changing the edge does not need a
      rebuild.
    '';
  };

  # Theme.qml is rendered through the shared palette renderer and carries the
  # bar's position the same way: a placeholder the theme module substitutes.
  config = {
    anixie.theme.template.placeholders = {
      "@POSITION@" = config.anixie.wm.quickshell.position;
      "@NOTIFICATIONS_DISPLAY@" = config.anixie.wm.quickshell.notificationsDisplay;

      # The warning's sender and IPC entry point, by full path: the shell service
      # runs under the user manager, whose PATH is not guaranteed to carry the
      # profile. The sender is the same one the rest of the tree uses (see
      # features/wm/notify), so a battery toast can carry a glyph or a click
      # action.
      "@NOTIFY_SEND@" = config.anixie.wm.notify.bin;
      "@QUICKSHELL@" = "${pkgs.quickshell}/bin/quickshell";
      "@FPRINTD_LIST@" = "${pkgs.fprintd}/bin/fprintd-list";
      "@HYPRLOCK@" = "${pkgs.hyprlock}/bin/hyprlock";
    };

    home.packages = [ pkgs.quickshell ];

    xdg.configFile."quickshell" = {
      recursive = true;
      source = shellConfig;
    };

    # A service rather than an exec-once line. Three reasons:
    #   - exec-once re-runs on every Hyprland config reload, which stacked a
    #     second bar over the first.
    #   - Hand-starting it from a shell does not reliably carry the session
    #     environment, and without HYPRLAND_INSTANCE_SIGNATURE the Hyprland IPC
    #     module never connects, so the workspace list silently stays empty.
    #   - A crashed bar stays crashed.
    #
    # graphical-session.target is started by Home Manager's Hyprland activation,
    # after it has pushed the session environment into the user manager, so the
    # bar is running with the variables it needs. %h is the user's home, since
    # systemd does not expand ~.
    #
    # That push happens once, at session start, so a compositor restart leaves
    # the user manager holding a signature and socket that no longer exist. The
    # bar then fails to connect and would otherwise be given up on: the default
    # start limit is five restarts in ten seconds, easily reached while Hyprland
    # is still coming back. Unlimiting it lets the bar keep retrying until
    # Hyprland re-imports its environment on the next attempt
    # (see the hl.on("hyprland.start", ...) handler in
    # hyprland/config/70-startup.lua) and
    # the next attempt succeeds.
    systemd.user.services.quickshell = {
      Unit = {
        Description = "Quickshell status bar";
        After = [ "graphical-session-pre.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStart = "${lib.getExe pkgs.quickshell} -p %h/.config/quickshell";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # The bridge from logind's Lock signal to the shell's lock. Separate from the
    # shell so a shell restart does not drop the listener.
    systemd.user.services.anixie-lock-signal = {
      Unit = {
        Description = "Forward logind lock requests to the shell";
        After = [ "quickshell.service" ];
        PartOf = [ "graphical-session.target" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStart = "${lockSignal}";
        Restart = "always";
        RestartSec = 2;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
