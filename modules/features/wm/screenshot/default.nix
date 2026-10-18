{
  pkgs,
  ...
}:

{
  # Annotation is satty's job. It is written for Wayland and opens in crop mode,
  # so Super+Shift+A goes straight to cropping rather than making you pick the
  # crop tool first.
  #
  # swappy was here before and drew nothing at all: it is an X11-era GTK
  # application, and under XWayland its window never appeared — the client was in
  # hyprctl's list with nothing on screen. Worth knowing if an annotation tool
  # ever looks like it launched and then vanished.
  home.packages = [
    # Screenshots go through one command with the mode vocabulary the reference
    # shell uses, so the binds and any habit carry over, while nothing depends on
    # its own vendored tooling. hyprshot covers the modes natively, including the
    # interactive window picker and clipboard-only capture that grim cannot do.
    #
    # The paths are substituted in rather than left to $PATH: these run from a
    # Hyprland bind, which does not necessarily carry the user's profile path.
    (pkgs.writeShellScriptBin "shot" (
      builtins.replaceStrings
        [ "@HYPRSHOT@" "@SATTY@" ]
        [
          "${pkgs.hyprshot}/bin/hyprshot"
          "${pkgs.satty}/bin/satty"
        ]
        (builtins.readFile ./shot.sh)
    ))

    pkgs.hyprshot
    pkgs.satty
  ];
}