{ config, lib, pkgs, ... }:

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
    # The base graphics stack is enabled by desktop.nix, because Hyprland needs
    # it whether or not gaming is installed. 32-bit graphics are the gaming-only
    # part: Steam's Proton and many older titles need them, and they are also
    # why Steam is a system-level package rather than a user one.
    hardware.graphics.enable32Bit = true;

    programs.gamemode = {
      enable = cfg.gamemode;

      # Make GameMode actually do something useful for a game like Minecraft:
      # raise the game's niceness window, hand it the performance CPU governor
      # and the high GPU DPM level, and stop the screen from blanking mid-match.
      # Renice needs the user in the `gamemode` group (see users.nix).
      settings = lib.mkIf cfg.gamemode {
        general = {
          renice = 10;
          ioprio = 0;
          inhibit_screensaver = 1;
        };

        gpu = {
          apply_gpu_optimisations = "accept-responsibility";
          gpu_device = 0;
          amd_performance_level = "high";
        };

        custom = {
          start = "${pkgs.libnotify}/bin/notify-send 'GameMode started'";
          end = "${pkgs.libnotify}/bin/notify-send 'GameMode ended'";
        };
      };
    };

    programs.steam = lib.mkIf cfg.steam.enable {
      enable = true;
      remotePlay.openFirewall = cfg.steam.remotePlay;
      gamescopeSession.enable = cfg.steam.gamescopeSession;
    };
  };
}
