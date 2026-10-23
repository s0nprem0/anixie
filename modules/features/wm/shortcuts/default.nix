{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.shortcuts;
in
{
  options.my.wm.shortcuts.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the shortcuts command, a searchable sheet built from Hyprland's bind descriptions.";
  };

  config = lib.mkIf cfg.enable {
    # Hyprland is the source of truth: every bind is described in the Lua config,
    # and `hyprctl binds -j` already carries those descriptions. This reads them
    # instead of keeping a second list that would drift.
    home.packages = [
      (pkgs.writeShellScriptBin "shortcuts" (
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
          (builtins.readFile ./shortcuts.sh)
      ))
    ];
  };
}
