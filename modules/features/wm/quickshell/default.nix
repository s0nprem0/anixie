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
  systemd.user.services.quickshell = {
    Unit.Description = "Quickshell status bar";
    Unit.After = [ "graphical-session-pre.target" ];
    Service = {
      Type = "simple";
      ExecStart = "${lib.getExe pkgs.quickshell} -p %h/.config/quickshell";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
