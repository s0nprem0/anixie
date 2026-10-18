{ config, ... }:

{
  programs.fuzzel = {
    enable = true;

    settings = {
      main = {
        terminal = "kitty";
        font = "JetBrains Mono:size=11";
        prompt = "❯ ";
        width = 50;
        horizontal-pad = 20;
        vertical-pad = 12;
        inner-pad = 8;

        # The colours come from the file the `theme` command writes rather than
        # from here. They cannot be overridden from here: fuzzel reads an include
        # where it appears, and a `[colors]` section of its own would come later
        # and win. Home Manager's fuzzel module generates from an attrset and has
        # no way to append one, so the colours are simply left to the include.
        include = "${config.my.theme.stateDir}/fuzzel.ini";
      };

      border = {
        width = 2;
        radius = 8;
      };
    };
  };
}
