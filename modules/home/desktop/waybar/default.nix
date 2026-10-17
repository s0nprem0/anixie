{ config, ... }:

{
  programs.waybar = {
    enable = true;
    style = config.my.theme.template.render ./style.css;

    settings.mainBar = {
      layer = "top";
      position = "top";
      height = 32;
      spacing = 8;

      modules-left = [
        "hyprland/workspaces"
        "hyprland/window"
      ];

      modules-center = [ "clock" ];

      modules-right = [
        "network"
        "pulseaudio"
        "battery"
        "tray"
      ];

      clock = {
        format = "{:%a %d %b  %H:%M}";
        tooltip = true;
      };

      network = {
        format-wifi = "Wi-Fi {essid}";
        format-ethernet = "LAN {ipaddr}";
        format-disconnected = "Offline";
      };

      pulseaudio = {
        format = "VOL {volume}%";
        format-muted = "MUTE";
      };

      battery = {
        format = "BAT {capacity}%";
        format-charging = "CHG {capacity}%";
        format-full = "BAT FULL";
      };

      "hyprland/workspaces" = {
        disable-scroll = true;
        all-outputs = true;
      };
    };
  };
}
