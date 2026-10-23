{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.display;

  # Monitor scaling, the internal panel, and mirroring — the things the brightness
  # and function keys do not reach. Built the same way as the capture commands:
  # paths substituted rather than left to $PATH, since these run from a bind.
  monitors = pkgs.writeShellScriptBin "monitors" (
    builtins.replaceStrings
      [
        "@HYPRCTL@"
        "@JQ@"
        "@ANIXIE_LIB@"
      ]
      [
        "${pkgs.hyprland}/bin/hyprctl"
        "${pkgs.jq}/bin/jq"
        "${../../cli/lib.sh}"
      ]
      (builtins.readFile ./monitors.sh)
  );
in
{
  options.anixie.wm.display.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the monitors script and wlr-randr for display management.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # Named `monitors`, not `display`: ImageMagick already ships a `display` — its
      # X11 image viewer — and shadowing it would take a name away from a package
      # that is installed here for the capture commands.
      monitors

      # Resolution, scale, refresh rate and output switching from the terminal, for
      # anything `monitors` does not cover.
      pkgs.wlr-randr
    ];
  };
}
