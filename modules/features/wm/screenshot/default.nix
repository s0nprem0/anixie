{
  pkgs,
  ...
}:

let
  # Defined once and referred to by both commands: `shot` shells out to the
  # picker, and a second copy of it built separately would be a second thing to
  # keep in step.
  shotPick = pkgs.writeShellScriptBin "shot-pick" (
    builtins.replaceStrings
      [
        "@HYPERPICKER@"
        "@HYPRCTL@"
        "@JQ@"
      ]
      [
        "${pkgs.hyprpicker}/bin/hyprpicker"
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.jq}/bin/jq"
      ]
      (builtins.readFile ./pick.sh)
  );
in

{
  # Annotation is satty's job. It is written for Wayland and opens in crop mode,
  # so the annotate bind goes straight to cropping rather than making you pick the
  # crop tool first.
  #
  # swappy was here before and drew nothing at all: it is an X11-era GTK
  # application, and under XWayland its window never appeared — the client was in
  # hyprctl's list with nothing on screen. Worth knowing if an annotation tool
  # ever looks like it launched and then vanished.
  home.packages = [
    # The picker, and the screenshot command that uses it.
    #
    # Paths are substituted in rather than left to $PATH: these run from a
    # Hyprland bind, which does not necessarily carry the user's profile path.
    shotPick

    (pkgs.writeShellScriptBin "shot" (
      builtins.replaceStrings
        [
          "@SHOT_PICK@"
          "@GRIM@"
          "@WL_COPY@"
          "@SATTY@"
          "@HYPRCTL@"
          "@JQ@"
        ]
        [
          "${shotPick}/bin/shot-pick"
          "${pkgs.grim}/bin/grim"
          "${pkgs.wl-clipboard}/bin/wl-copy"
          "${pkgs.satty}/bin/satty"
          "${pkgs.hyprland}/bin/hyprctl"
          "${pkgs.jq}/bin/jq"
        ]
        (builtins.readFile ./shot.sh)
    ))

    pkgs.hyprpicker
    pkgs.slurp
    pkgs.grim
    pkgs.satty
  ];
}