{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.anixie.wm.network;

  # The QR for the current network, as a PNG in the state directory. Built as a
  # script with the two tool paths substituted, since the shell reads the network
  # manager and the encoder rather than the panel doing either itself.
  wifiQr = pkgs.writeShellScriptBin "wifi-qr" (
    builtins.replaceStrings
      [ "@NMCLI@" "@QRENCODE@" ]
      [
        "${pkgs.networkmanager}/bin/nmcli"
        "${pkgs.qrencode}/bin/qrencode"
      ]
      (builtins.readFile ./wifi-qr.sh)
  );

  taildropReceive = pkgs.writeShellScriptBin "taildrop-receive" (
    builtins.replaceStrings
      [ "@TAILSCALE@" "@NOTIFY@" "@XDG_OPEN@" ]
      [
        "${pkgs.tailscale}/bin/tailscale"
        config.anixie.wm.notify.bin
        "${pkgs.xdg-utils}/bin/xdg-open"
      ]
      (builtins.readFile ./taildrop-receive.sh)
  );

  wifiPassword = pkgs.writeShellScriptBin "wifi-password" (
    builtins.replaceStrings
      [ "@WIFI_QR@" "@WL_COPY@" ]
      [
        "${wifiQr}/bin/wifi-qr"
        "${pkgs.wl-clipboard}/bin/wl-copy"
      ]
      (builtins.readFile ./wifi-password.sh)
  );

  wifiBand = pkgs.writeShellScriptBin "wifi-band" (
    builtins.replaceStrings [ "@NMCLI@" ] [ "${pkgs.networkmanager}/bin/nmcli" ] (
      builtins.readFile ./wifi-band.sh
    )
  );
in
{
  options.anixie.wm.network.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the network helpers: Wi-Fi QR/password/band commands and the Taildrop receiver.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      wifiQr
      wifiPassword
      wifiBand
      taildropReceive
    ];

    systemd.user.services.anixie-taildrop = {
      Unit = {
        Description = "Receive Taildrop files into Downloads";
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStart = "${taildropReceive}/bin/taildrop-receive";
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
