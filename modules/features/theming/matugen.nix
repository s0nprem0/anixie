{ config, pkgs, ... }:

{
  # Matugen derives a Material You palette from an image. It is used here as a
  # source of ten colours, not as the generator of every config: the template
  # below writes a file in the same shape as themes.json, and the shell and the
  # applications read it exactly as they read a curated theme. Which palette you
  # are on is then one name, `wallpaper`, rather than a second theming system.
  home.packages = [ pkgs.matugen ];

  xdg.configFile."matugen/config.toml".text = ''
    [config]

    [templates.anixie]
    input_path = '${./wallpaper-palette.json}'
    output_path = '${config.my.theme.stateDir}/palette.json'
  '';
}
