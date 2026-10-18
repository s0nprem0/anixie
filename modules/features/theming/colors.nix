{ config, lib, ... }:

let
  # Every palette, from the one file that holds them. A JSON file rather than Nix
  # because the shell has to read the same list at runtime, and a shell script
  # cannot evaluate a Nix expression — so the data lives somewhere both can reach
  # and neither has to be kept in step with the other by hand.
  palettes = builtins.fromJSON (builtins.readFile ./themes.json);

  names = builtins.attrNames palettes;

  # Every palette has to carry every token: a missing one would render as an
  # empty string into a config file and only show up as a wrong colour somewhere
  # far away. Checked here rather than discovered there.
  tokenNames = builtins.attrNames palettes.${builtins.head names};
in
{
  options.my.theme = {
    theme = lib.mkOption {
      type = lib.types.enum names;
      default = "tokyo-night";
      description = ''
        Which palette the Nix-rendered configs are built from. This is the
        default, not the live choice: the `theme` command switches the shell and
        the apps that read a runtime file without a rebuild, and leaves this
        alone. Change it to change what a fresh install starts on.
      '';
    };

    palettes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      readOnly = true;
      default = palettes;
      description = ''
        Every palette, keyed by name. The shell embeds all of them so it can
        switch without a rebuild; nothing else should need this.
      '';
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "The selected palette's colours.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${config.xdg.stateHome}/anixie/theme";
      description = ''
        Where the live choice and the files it materialises are written. A state
        directory rather than ~/.config, which Home Manager owns as read-only
        store symlinks — a theme set at runtime has to be able to write.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (
          name: builtins.attrNames palettes.${name} == tokenNames
        ) names;
        message = "every palette in theming/themes.json must define the same tokens: ${toString tokenNames}";
      }
    ];

    my.theme.colors = palettes.${config.my.theme.theme};
  };
}
