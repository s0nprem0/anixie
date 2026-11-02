{
  lib,
  pkgs,
  ...
}:

let
  focus = pkgs.writeShellScriptBin "focus" (
    builtins.replaceStrings [ "@QUICKSHELL@" ] [ "${pkgs.quickshell}/bin/quickshell" ] (
      builtins.readFile ./focus.sh
    )
  );
in
{
  options.anixie.wm.focus = {
    defaultMinutes = lib.mkOption {
      type = lib.types.ints.between 1 480;
      default = 25;
      description = "How long a focus block lasts when no duration is given.";
    };

    blockedClasses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "discord"
        "equicord"
        "vesktop"
        "telegram"
        "steam"
        "lutris"
        "heroic"
      ];
      description = ''
        Window app ids that are closed while focus is active. Matching is
        case-insensitive and substring-based, so `discord` covers
        `com.discordapp.Discord` as well as a bare `discord` class.
      '';
    };
  };

  config = {
    home.packages = [ focus ];
  };
}
