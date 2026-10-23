{ config, lib, ... }:

let
  cfg = config.anixie.gaming;
in
{
  options.anixie.gaming = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the Steam and GameMode stack.";
    };

    steam = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to install Steam.";
      };

      remotePlay = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to open the firewall for Steam Remote Play.";
      };

      gamescopeSession = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to add a gamescope session to the display manager.";
      };
    };

    gamemode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable GameMode, the daemon games ask for a temporary performance boost.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 32-bit graphics are what Steam's Proton and many older titles need. They
    # are also the reason Steam is a system-level package rather than a user one.
    hardware.graphics.enable = true;
    hardware.graphics.enable32Bit = true;

    programs.gamemode.enable = cfg.gamemode;

    programs.steam = lib.mkIf cfg.steam.enable {
      enable = true;
      remotePlay.openFirewall = cfg.steam.remotePlay;
      gamescopeSession.enable = cfg.steam.gamescopeSession;
    };
  };
}
