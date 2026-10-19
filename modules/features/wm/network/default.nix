{ pkgs, ... }:

let
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
  home.packages = [ wifiQr ];
}
