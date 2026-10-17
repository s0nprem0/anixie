{
  config,
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

  wayland.windowManager.hyprland.settings.exec-once = [
    "quickshell -p ~/.config/quickshell"
  ];
}
