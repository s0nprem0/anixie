{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.emoji;

  emoji = pkgs.writeShellScriptBin "emoji" (
    builtins.replaceStrings
      [
        "@EMOJI_TEST@"
        "@WTYPE@"
        "@ANIXIE_LIB@"
      ]
      [
        "${pkgs.unicode-emoji}/share/unicode/emoji/emoji-test.txt"
        "${pkgs.wtype}/bin/wtype"
        "${../../cli/lib.sh}"
      ]
      (builtins.readFile ./emoji.sh)
  );
in

{
  options.anixie.wm.emoji.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the emoji picker that types via wtype.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ emoji ];
  };
}
