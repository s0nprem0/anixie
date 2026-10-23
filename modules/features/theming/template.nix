{ config, lib, ... }:

let
  c = config.anixie.theme.colors;

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
    yellow = "YELLOW";
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
    # Seeded from the palette.
    inherit placeholders;

    render =
      source:
      # Read through the option rather than captured from the let binding, so a
      # module that adds its own placeholder — the bar's position, say — is
      # actually substituted here. Reading the local binding would only ever see
      # the palette, and silently drop every other module's tokens.
      let
        tokens = config.anixie.theme.template.placeholders;
      in
      builtins.replaceStrings (lib.attrNames tokens) (lib.attrValues tokens) (
        if lib.isString source then source else builtins.readFile source
      );
  };
}
