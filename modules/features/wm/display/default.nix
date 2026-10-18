{ pkgs, ... }:

let
  # Monitor scaling, the internal panel, and mirroring — the things the brightness
  # and function keys do not reach. Built the same way as the capture commands:
  # paths substituted rather than left to $PATH, since these run from a bind.
  monitors = pkgs.writeShellScriptBin "monitors" (
    builtins.replaceStrings
      [
        "@HYPRCTL@"
        "@JQ@"
      ]
      [
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.jq}/bin/jq"
      ]
      (builtins.readFile ./monitors.sh)
  );
in
{
  home.packages = [
    # Named `monitors`, not `display`: ImageMagick already ships a `display` — its
    # X11 image viewer — and shadowing it would take a name away from a package
    # that is installed here for the capture commands.
    monitors

    # Resolution, scale, refresh rate and output switching from the terminal, for
    # anything `monitors` does not cover.
    pkgs.wlr-randr
  ];
}
