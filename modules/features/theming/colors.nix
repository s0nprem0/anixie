{ config, lib, ... }:

let
  # Every palette, from the one file that holds them. A JSON file rather than Nix
  # because the shell has to read the same list at runtime, and a shell script
  # cannot evaluate a Nix expression — so the data lives somewhere both can reach
  # and neither has to be kept in step with the other by hand.
  #
  # `_mode` is metadata, not a colour. It stays in the embedded palette the shell
  # reads (so QML can tell light from dark) and is stripped before a palette is
  # rendered or written to the state directory.
  palettes = builtins.fromJSON (builtins.readFile ./themes.json);

  # `muted` is the secondary text token — panel section headers, hints, empty
  # states. It has to clear WCAG AA (4.5:1) against the panel surface, not only
  # the background, or those labels become unreadable in a dark palette. Several
  # of the upstream colours did not, so they carry a lightened `muted` here.
  names = builtins.attrNames palettes;

  colours = builtins.mapAttrs (_: palette: removeAttrs palette [ "_mode" ]) palettes;
  modeOf = name: palettes.${name}._mode or "dark";

  # Every palette has to carry every token: a missing one would render as an
  # empty string into a config file and only show up as a wrong colour somewhere
  # far away. Checked here rather than discovered there.
  tokenNames = builtins.attrNames colours.${builtins.head names};
in
{
  options.anixie.theme = {
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

    mode = lib.mkOption {
      type = lib.types.enum [
        "dark"
        "light"
      ];
      readOnly = true;
      default = modeOf config.anixie.theme.theme;
      description = ''
        Whether the selected palette is light or dark. It drives the build-time
        app configs; a runtime switch reads the same value from the theme state
        directory instead.
      '';
    };

    palettes = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      readOnly = true;
      default = palettes;
      description = ''
        Every palette, keyed by name, including each one's `_mode`. The shell
        embeds all of them so it can switch without a rebuild; nothing else
        should need this.
      '';
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      description = "The selected palette's colours, without the `_mode` metadata.";
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
        assertion = builtins.all (name: builtins.attrNames colours.${name} == tokenNames) names;
        message = "every palette in theming/themes.json must define the same tokens: ${toString tokenNames}";
      }
      {
        assertion = builtins.all (
          name:
          builtins.elem (modeOf name) [
            "dark"
            "light"
          ]
        ) names;
        message = "every palette in theming/themes.json must set _mode to \"dark\" or \"light\"";
      }
    ];

    anixie.theme.colors = colours.${config.anixie.theme.theme};
  };
}
