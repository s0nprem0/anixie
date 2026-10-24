{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.network;

  mkScript = import ../../cli/scripts.nix { inherit pkgs; };

  # The four Wi-Fi operations are internal: the panel reaches them through the
  # `wifi` dispatcher below, so none of them needs a name on PATH.
  wifiQr = mkScript {
    name = "wifi-qr";
    file = ./wifi-qr.sh;
    bins = {
      "@NMCLI@" = "${pkgs.networkmanager}/bin/nmcli";
      "@QRENCODE@" = "${pkgs.qrencode}/bin/qrencode";
    };
  };

  wifiPassword = mkScript {
    name = "wifi-password";
    file = ./wifi-password.sh;
    bins = {
      "@WIFI_QR@" = wifiQr.command;
      "@WL_COPY@" = "${pkgs.wl-clipboard}/bin/wl-copy";
    };
  };

  wifiBand = mkScript {
    name = "wifi-band";
    file = ./wifi-band.sh;
    bins = {
      "@NMCLI@" = "${pkgs.networkmanager}/bin/nmcli";
    };
  };

  wifiDns = mkScript {
    name = "wifi-dns";
    file = ./wifi-dns.sh;
    bins = {
      "@NMCLI@" = "${pkgs.networkmanager}/bin/nmcli";
    };
  };

  # The one public command. A dispatcher rather than a merged script keeps each
  # operation's usage and error messages intact while removing four entries from
  # PATH.
  wifi = mkScript {
    name = "wifi";
    file = ./wifi.sh;
    bins = {
      "@WIFI_BAND@" = wifiBand.command;
      "@WIFI_DNS@" = wifiDns.command;
      "@WIFI_PASSWORD@" = wifiPassword.command;
      "@WIFI_QR@" = wifiQr.command;
    };
  };

  # Only the user unit starts this; it is not something to run by hand.
  taildropReceive = mkScript {
    name = "taildrop-receive";
    file = ./taildrop-receive.sh;
    bins = {
      "@TAILSCALE@" = "${pkgs.tailscale}/bin/tailscale";
      "@NOTIFY@" = config.anixie.wm.notify.bin;
      "@XDG_OPEN@" = "${pkgs.xdg-utils}/bin/xdg-open";
      "@JQ@" = "${pkgs.jq}/bin/jq";
    };
  };
in
{
  options.anixie.wm.network.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the Wi-Fi command and the Taildrop receiver.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ wifi.package ];

    systemd.user.services.anixie-taildrop = {
      Unit = {
        Description = "Receive Taildrop files into Downloads";
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStart = taildropReceive.command;
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
