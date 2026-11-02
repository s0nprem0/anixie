{ config, lib, ... }:

let
  cfg = config.anixie.security.luks;
in
{
  options.anixie.security.luks = {
    enable = lib.mkEnableOption "a declaratively declared LUKS root";

    name = lib.mkOption {
      type = lib.types.str;
      default = "cryptroot";
      description = "The device-mapper name used in initrd.";
    };

    device = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
      description = "The encrypted block device, by UUID rather than by kernel name.";
    };

    allowDiscards = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pass discards through to the encrypted device (TRIM); leaks some usage patterns.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.device != "";
        message = "anixie.security.luks.enable needs anixie.security.luks.device";
      }
    ];

    warnings = [
      ''
        anixie.security.luks.enable is set. This only works on a system whose root is
        already inside that LUKS container; adding it to an unencrypted install
        makes the machine unbootable. See the README's "Disk encryption" section.
      ''
    ];

    boot.initrd.luks.devices.${cfg.name} = {
      inherit (cfg) device allowDiscards;
    };
  };
}
