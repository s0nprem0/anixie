{ config, lib, ... }:

let
  c = config.my.theme.colors;

  # Token names used in templates, keyed by colour option.
  shortNames = {
    background = "BG";
    surface = "SURFACE";
    foreground = "FG";
    muted = "MUTED";
    primary = "PRIMARY";
    accent = "ACCENT";
    accentAlt = "ACCENT_ALT";
    success = "SUCCESS";
    danger = "DANGER";
  };

  # Colour with the leading '#' stripped, so it can be reused in every notation.
  hex = value: builtins.substring 1 6 value;

  # Alphas the desktop uses: opaque, muted, and slightly translucent.
  alphas = [
    "FF"
    "AA"
    "F2"
  ];

  tokensFor =
    name: value:
    let
      short = shortNames.${name};
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

  placeholders = lib.concatMapAttrs tokensFor c;
in
{
  options.my.theme.template = {
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

  config.my.theme.template = {
    inherit placeholders;

    render =
      source:
      builtins.replaceStrings (lib.attrNames placeholders) (lib.attrValues placeholders) (
        if lib.isString source then source else builtins.readFile source
      );
  };
}
