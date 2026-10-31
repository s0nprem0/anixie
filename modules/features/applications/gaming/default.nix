{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.applications.gaming;
in
{
  options.anixie.applications.gaming = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the gaming launchers and overlays that sit beside Steam.";
    };

    lutris = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install Lutris for non-Steam Windows games.";
    };

    heroic = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install Heroic for Epic, GOG and Amazon games.";
    };

    retroarch = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install RetroArch with its core set.";
    };

    prismLauncher = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install Prism Launcher, a Minecraft launcher with modpack and instance management.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # Compositing and performance overlays used as Steam launch options:
      # `gamescope -- %command%` and `mangohud %command%`.
      pkgs.gamescope
      pkgs.mangohud

      # Installs GE-Proton builds, which is what non-Steam launchers and
      # Battle.net-style prefixes want.
      pkgs.protonup-qt
    ]
    ++ lib.optionals cfg.lutris [ pkgs.lutris ]
    ++ lib.optionals cfg.heroic [ pkgs.heroic ]
    ++ lib.optionals cfg.retroarch [ pkgs.retroarch ]
    ++ lib.optionals cfg.prismLauncher [ pkgs.prismlauncher ];
  };
}
