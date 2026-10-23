{ config, pkgs, ... }:

{
  # Matugen derives a Material You palette from an image. It is used here as a
  # source of the same nine colours as a curated palette, not as the generator of
  # every config: the template below writes a file in the shape of themes.json,
  # and `theme` stamps matugen's light/dark choice into it as `_mode`. The shell
  # and the applications read it exactly as they read a curated theme, so which
  # palette you are on is still one name, `wallpaper`.
  home.packages = [ pkgs.matugen ];

  xdg.configFile."matugen/config.toml".text = ''
    [config]

    [templates.anixie]
    input_path = '${./wallpaper-palette.json}'
    output_path = '${config.anixie.theme.stateDir}/palette.json'
  '';
}
