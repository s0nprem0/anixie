{ lib, ... }:

{
  options.myDots.theme = {
    name = lib.mkOption {
      type = lib.types.str;
      default = "midnight-ember";
      description = "Name of the personal desktop theme.";
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;

      default = {
        background = "#111318";
        surface = "#1b1f27";
        foreground = "#e6e8ef";
        muted = "#9298a8";
        accent = "#e0a458";
        accentAlt = "#8da9c4";
        success = "#a6c48a";
        danger = "#e58b8b";
      };

      description = "Shared color palette for personal dotfiles.";
    };
  };
}
