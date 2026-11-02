{
  config,
  lib,
  ...
}:

let
  c = config.anixie.theme.colors;
  spec = builtins.fromJSON (builtins.readFile ./tokens.json);

  shortNames = spec.colors;
  alphas = spec.alphas or [ ];

  derived = lib.mapAttrs (key: source: c.${key} or c.${source}) (spec.derived or { });
  allColors = derived // c;

  tokenName =
    key:
    shortNames.${key}
      or (if lib.hasPrefix "ansi" key then "ANSI_" + lib.removePrefix "ansi" key else lib.toUpper key);

  hex = value: builtins.substring 1 6 value;

  tokensFor =
    name: value:
    let
      short = tokenName name;
      h = hex value;
    in
    {
      "@${short}@" = value;
      "@${short}_HEX@" = h;
    }
    // lib.concatMapAttrs (a: _: {
      "@${short}_ALPHA_${a}@" = "#${h}${lib.strings.toLower a}";
      "@${short}_BARE_${a}@" = "${h}${lib.strings.toLower a}";
      "@${short}_RGBA_${a}@" = "rgba(${h}${lib.strings.toLower a})";
    }) (lib.listToAttrs (map (a: lib.nameValuePair a a) alphas));

  placeholders = lib.concatMapAttrs tokensFor allColors;
in
{
  options.anixie.theme.template = {
    placeholders = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Maps every `@TOKEN@` to the colour it stands for.";
    };

    render = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      default = _: "";
      description = ''
        Substitutes `@TOKEN@` placeholders with theme colours. Takes either a
        path to a template file or the template source as a string, so whole
        files (stylesheets, themes) and single values can share one scheme.
      '';
    };
  };

  config.anixie.theme.template = {
    inherit placeholders;

    render =
      source:
      let
        tokens = config.anixie.theme.template.placeholders;
      in
      builtins.replaceStrings (lib.attrNames tokens) (lib.attrValues tokens) (
        if lib.isString source then source else builtins.readFile source
      );
  };
}
