{
  config,
  lib,
  pkgs,
  ...
}:

let
  render = config.my.theme.template.render;

  theme = pkgs.writeText "Theme.qml" (render ./Theme.qml);

  # Quickshell resolves `import "components"` relative to the directory holding
  # shell.qml. Home Manager deploys every xdg.configFile entry as a separate
  # symlink, which would scatter the QML tree across the store, so the config is
  # assembled into one real directory first.
  shellConfig = pkgs.runCommand "quickshell-config" { } ''
    cp -rL ${./.} $out
    chmod -R u+w $out
    cp ${theme} $out/Theme.qml
    rm -f $out/default.nix
  '';
in
{
  options.features.wm.quickshell.position = lib.mkOption {
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

      This is set here rather than in bar.json because the bar window is built
      once and cannot be re-anchored afterwards, so the edge has to be known
      before the first frame.
    '';
  };

  # Theme.qml is rendered through the shared palette renderer and carries the
  # bar's position the same way: a placeholder the theme module substitutes.
  config = {
    my.theme.template.placeholders."@POSITION@" = config.features.wm.quickshell.position;

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
    # Hyprland re-imports its environment (see startup.nix) and the next attempt
    # succeeds.
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
  };
}
