{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.wm.emoji;

  emoji = pkgs.writeShellScriptBin "emoji" (
    builtins.replaceStrings
      [
        "@EMOJI_TEST@"
        "@WTYPE@"
      ]
      [
        "${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt"
        "${pkgs.wtype}/bin/wtype"
      ]
      (builtins.readFile ./emoji.sh)
  );
in

{
  options.my.wm.emoji.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the emoji picker that types via wtype.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ emoji ];
  };
}
