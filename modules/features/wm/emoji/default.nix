{
  pkgs,
  ...
}:

let
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
  home.packages = [ emoji ];
}