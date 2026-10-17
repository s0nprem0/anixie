{ lib, ... }:

{
  options.my.theme = {
    colors = {
      background = lib.mkOption {
        type = lib.types.str;
        default = "#0f111a";
      };

      surface = lib.mkOption {
        type = lib.types.str;
        default = "#171a24";
      };

      foreground = lib.mkOption {
        type = lib.types.str;
        default = "#c8d3f5";
      };

      muted = lib.mkOption {
        type = lib.types.str;
        default = "#828bb8";
      };

      accent = lib.mkOption {
        type = lib.types.str;
        default = "#82aaff";
      };

      accentAlt = lib.mkOption {
        type = lib.types.str;
        default = "#c099ff";
      };

      success = lib.mkOption {
        type = lib.types.str;
        default = "#c3e88d";
      };

      danger = lib.mkOption {
        type = lib.types.str;
        default = "#ff757f";
      };
    };
  };
}
