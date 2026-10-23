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
in
{
  options.anixie.wm.network.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether to install the wifi-qr script, which encodes the current network credentials as a QR code.";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ wifiQr ];
  };
}
