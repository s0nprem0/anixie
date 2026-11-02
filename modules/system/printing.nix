{ pkgs, ... }:

{
  # cups-filters is added on the home-manager side, in
  # features/applications/printer, since home.packages is not a NixOS option.
  services.printing.enable = true;

  # simple-scan is installed beside the printer apps, but it cannot see a
  # scanner until SANE's backends and udev rules are present. The module tags
  # scanners with `uaccess`, so the logged-in seat gets access without adding
  # the user to the `scanner` group.
  hardware.sane.enable = true;

  # mDNS for network printers/scanners and NDI discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
    settings = {
      publish = {
        "disable-publishing" = false;
        "publish-addresses" = true;
        "disable-user-service-publishing" = false;
      };
    };
  };

  # avahi writes its own pid file and refuses to start if a stale one is left
  # behind by a crashed previous instance. Clear it before starting so a bad
  # shutdown cannot wedge mDNS (and anything that depends on it) until a manual
  # cleanup.
  systemd.services.avahi-daemon.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/rm -f /run/avahi-daemon/pid"
  ];
}
